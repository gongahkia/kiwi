//! wasm-bindgen browser bindings for kumeyuri rendering.

use std::time::Duration;

use kumeyuri_core::{
    animator::{AnimationOptions, Animator, KeyFrame, Timeline},
    ast::Diagram,
    cast::Kumecast,
    frame::{Charset, StaticFrameRenderer},
    parser::{ParseErrorKind, Parser as MermaidParser},
    text::{TextOutputBackend, TextOutputConfig},
    theme::{BuiltInTheme, RgbColor, Theme},
};
use kumeyuri_render_svg::{SvgAnimationMode, SvgRenderConfig, SvgRenderer};
use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;

/// Browser-facing renderer wrapper.
#[wasm_bindgen]
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct WasmRenderer;

#[wasm_bindgen]
impl WasmRenderer {
    /// Create a browser renderer.
    #[wasm_bindgen(constructor)]
    pub fn new() -> Self {
        Self
    }

    /// Render Mermaid source to SVG plus text frames.
    pub fn render(&self, source: &str, options: JsValue) -> Result<JsValue, JsValue> {
        render(source, options)
    }

    /// Render a `.kumecast` JSON payload to SVG plus text frames.
    #[wasm_bindgen(js_name = renderCast)]
    pub fn render_cast(&self, source: &str, options: JsValue) -> Result<JsValue, JsValue> {
        render_cast(source, options)
    }
}

/// Render Mermaid source to SVG plus text frames.
#[wasm_bindgen]
pub fn render(source: &str, options: JsValue) -> Result<JsValue, JsValue> {
    let options = decode_options(options)?;
    render_output(source, &options)
        .and_then(|output| serde_wasm_bindgen::to_value(&output).map_err(|error| error.to_string()))
        .map_err(|error| JsValue::from_str(&error))
}

/// Render a `.kumecast` JSON payload to SVG plus text frames.
#[wasm_bindgen(js_name = renderCast)]
pub fn render_cast(source: &str, options: JsValue) -> Result<JsValue, JsValue> {
    let options = decode_options(options)?;
    render_cast_output(source, &options)
        .and_then(|output| serde_wasm_bindgen::to_value(&output).map_err(|error| error.to_string()))
        .map_err(|error| JsValue::from_str(&error))
}

#[derive(Debug, Default, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct WasmRenderOptions {
    theme: Option<String>,
    dark_theme: Option<String>,
    charset: Option<String>,
    width: Option<usize>,
    padding: Option<u16>,
    font: Option<String>,
    speed: Option<f32>,
    repeat: Option<bool>,
    svg_animation: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct WasmRenderOutput {
    svg: String,
    frames: Vec<WasmFrame>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct WasmFrame {
    text: String,
    duration_ms: u64,
}

fn decode_options(value: JsValue) -> Result<WasmRenderOptions, JsValue> {
    if value.is_null() || value.is_undefined() {
        return Ok(WasmRenderOptions::default());
    }
    serde_wasm_bindgen::from_value(value).map_err(|error| JsValue::from_str(&error.to_string()))
}

fn render_output(source: &str, options: &WasmRenderOptions) -> Result<WasmRenderOutput, String> {
    let timeline = timeline_from_source(source, options)?;
    Ok(WasmRenderOutput {
        svg: SvgRenderer::new(svg_config(options)?).render_timeline(&timeline),
        frames: timeline_frames(&timeline, options),
    })
}

fn render_cast_output(
    source: &str,
    options: &WasmRenderOptions,
) -> Result<WasmRenderOutput, String> {
    let timeline = timeline_from_cast_source(source, options)?;
    Ok(WasmRenderOutput {
        svg: SvgRenderer::new(svg_config(options)?).render_timeline(&timeline),
        frames: timeline_frames(&timeline, options),
    })
}

fn timeline_from_source(source: &str, options: &WasmRenderOptions) -> Result<Timeline, String> {
    let diagram = parse_diagram(source)?;
    let animation_options = AnimationOptions::new(options.speed, options.repeat)
        .map_err(|error| format!("invalid animation options: {error:?}"))?;
    let timeline = Animator::animate_diagram_with_options_and_renderer(
        &diagram,
        animation_options,
        frame_renderer(options)?,
    )
    .map_err(|error| format!("animation config error: {error:?}"))?;
    Ok(apply_timeline_width(timeline, options))
}

fn timeline_from_cast_source(
    source: &str,
    options: &WasmRenderOptions,
) -> Result<Timeline, String> {
    let cast = Kumecast::from_json_str(source).map_err(|error| error.to_string())?;
    let timeline = cast.to_timeline().map_err(|error| error.to_string())?;
    Ok(apply_timeline_width(
        apply_cast_playback_options(timeline, options)?,
        options,
    ))
}

fn apply_cast_playback_options(
    timeline: Timeline,
    options: &WasmRenderOptions,
) -> Result<Timeline, String> {
    let animation_options = AnimationOptions::new(options.speed, options.repeat)
        .map_err(|error| format!("invalid animation options: {error:?}"))?;
    let repeat = animation_options.repeat().unwrap_or(timeline.repeat());
    let Some(speed) = animation_options.speed() else {
        return Ok(timeline.with_repeat(repeat));
    };
    let mut scaled = Timeline::new().with_repeat(repeat);
    for keyframe in timeline.keyframes() {
        scaled.push(KeyFrame::new(
            keyframe.frame().clone(),
            Duration::from_secs_f64(keyframe.duration().as_secs_f64() / f64::from(speed)),
        ));
    }
    Ok(scaled)
}

fn frame_renderer(options: &WasmRenderOptions) -> Result<StaticFrameRenderer, String> {
    Ok(StaticFrameRenderer::default().with_theme(render_theme(options)?))
}

fn render_theme(options: &WasmRenderOptions) -> Result<Theme, String> {
    let mut theme = built_in_theme(options.theme.as_deref().unwrap_or("default"))?.theme();
    if let Some(charset) = options.charset.as_deref() {
        theme.charset = match charset {
            "ascii" => Charset::Ascii,
            "unicode" => Charset::Unicode,
            charset => return Err(format!("unknown charset {charset:?}")),
        };
    }
    Ok(theme)
}

fn svg_config(options: &WasmRenderOptions) -> Result<SvgRenderConfig, String> {
    let theme = render_theme(options)?;
    let dark_theme = options
        .dark_theme
        .as_deref()
        .map(built_in_theme)
        .transpose()?
        .map(BuiltInTheme::theme);
    let animation = match options.svg_animation.as_deref().unwrap_or("smil") {
        "smil" => SvgAnimationMode::Smil,
        "css-keyframes" => SvgAnimationMode::CssKeyframes,
        animation => return Err(format!("unknown svgAnimation {animation:?}")),
    };
    let mut config = SvgRenderConfig {
        padding: options.padding.unwrap_or_default(),
        font_family: options
            .font
            .clone()
            .unwrap_or_else(|| SvgRenderConfig::default().font_family),
        foreground: css_color(theme.colors.foreground),
        background: css_color(theme.colors.background),
        animation,
        ..SvgRenderConfig::default()
    };
    if let Some(dark_theme) = dark_theme {
        config.dark_foreground = Some(css_color(dark_theme.colors.foreground));
        config.dark_background = Some(css_color(dark_theme.colors.background));
    }
    Ok(config)
}

fn built_in_theme(name: &str) -> Result<BuiltInTheme, String> {
    BuiltInTheme::from_name(name).ok_or_else(|| format!("unknown theme {name:?}"))
}

fn apply_timeline_width(timeline: Timeline, options: &WasmRenderOptions) -> Timeline {
    let Some(width) = options.width else {
        return timeline;
    };
    let mut resized = Timeline::new().with_repeat(timeline.repeat());
    for keyframe in timeline.keyframes() {
        resized.push(KeyFrame::new(
            keyframe.frame().with_min_width(width),
            keyframe.duration(),
        ));
    }
    resized
}

fn timeline_frames(timeline: &Timeline, options: &WasmRenderOptions) -> Vec<WasmFrame> {
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: options.width.is_none(),
        final_newline: false,
    });
    timeline
        .keyframes()
        .iter()
        .map(|keyframe| WasmFrame {
            text: text.render_frame(keyframe.frame()),
            duration_ms: duration_ms(keyframe),
        })
        .collect()
}

fn duration_ms(keyframe: &KeyFrame) -> u64 {
    keyframe
        .duration()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

fn css_color(color: RgbColor) -> String {
    format!("#{:02x}{:02x}{:02x}", color.red, color.green, color.blue)
}

fn parse_diagram(source: &str) -> Result<Diagram, String> {
    MermaidParser::parse_diagram(source).map_err(|error| {
        let location = parse_error_location(source, error.span.start);
        format!(
            "parse error {} at {}..{} line {} column {}\n{}\n{}{}",
            parse_error_kind_label(error.kind),
            error.span.start,
            error.span.end,
            location.line,
            location.column,
            location.line_text,
            location.caret,
            parse_error_suggestion(error.kind)
                .map(|suggestion| format!("\nsuggestion: {suggestion}"))
                .unwrap_or_default()
        )
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParseErrorLocation {
    line: usize,
    column: usize,
    line_text: String,
    caret: String,
}

fn parse_error_location(source: &str, offset: usize) -> ParseErrorLocation {
    let offset = floor_char_boundary(source, offset.min(source.len()));
    let line_start = source[..offset].rfind('\n').map_or(0, |index| index + 1);
    let line_end = source[offset..]
        .find('\n')
        .map_or(source.len(), |index| offset + index);
    let line = source[..offset]
        .bytes()
        .filter(|byte| *byte == b'\n')
        .count()
        + 1;
    let column = source[line_start..offset].chars().count() + 1;
    ParseErrorLocation {
        line,
        column,
        line_text: source[line_start..line_end].to_owned(),
        caret: format!("{}^", " ".repeat(column.saturating_sub(1))),
    }
}

fn floor_char_boundary(source: &str, offset: usize) -> usize {
    if source.is_char_boundary(offset) {
        return offset;
    }
    source
        .char_indices()
        .map(|(index, _)| index)
        .take_while(|index| *index < offset)
        .last()
        .unwrap_or(0)
}

fn parse_error_kind_label(kind: ParseErrorKind) -> String {
    match kind {
        ParseErrorKind::UnsupportedMermaidConfig => concat!(
            "UnsupportedMermaidConfig: Mermaid frontmatter/init/layout/theme config is outside ",
            "kumeyuri's compatibility surface; use kumeyuri options or %%{ animate: ... }%%"
        )
        .to_owned(),
        _ => format!("{kind:?}"),
    }
}

fn parse_error_suggestion(kind: ParseErrorKind) -> Option<&'static str> {
    match kind {
        ParseErrorKind::ExpectedDiagramHeader => Some(
            "start with a supported Mermaid root such as graph, sequenceDiagram, stateDiagram-v2, classDiagram, erDiagram, gantt, pie, mindmap, journey, gitGraph, or timeline",
        ),
        ParseErrorKind::UnsupportedMermaidConfig => Some(
            "remove Mermaid frontmatter/init/layout/theme config and use kumeyuri options or %%{ animate: ... }%%",
        ),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use std::{
        fmt::Write as _,
        fs,
        path::{Path, PathBuf},
    };

    use super::{WasmRenderOptions, duration_ms, render_cast_output, render_output, svg_config};
    use kumeyuri_core::{
        animator::{KeyFrame, Timeline},
        cast::Kumecast,
        frame::Frame,
        theme::Theme,
    };

    const FIXTURES: [Fixture; 31] = [
        Fixture::new("flowchart", "01_single_node"),
        Fixture::new("sequence", "01_single_message"),
        Fixture::new("state", "01_start_to_idle"),
        Fixture::new("class", "01_basic_class"),
        Fixture::new("er", "01_basic_relationship"),
        Fixture::new("gantt", "01_basic_schedule"),
        Fixture::new("pie", "01_basic"),
        Fixture::new("quadrant", "01_basic"),
        Fixture::new("zenuml", "01_basic"),
        Fixture::new("sankey", "01_basic"),
        Fixture::new("xychart", "01_basic"),
        Fixture::new("block", "01_basic"),
        Fixture::new("packet", "01_tcp"),
        Fixture::new("kanban", "01_basic"),
        Fixture::new("architecture", "01_basic"),
        Fixture::new("radar", "01_basic"),
        Fixture::new("event_modeling", "01_basic"),
        Fixture::new("treemap", "01_basic"),
        Fixture::new("venn", "01_basic"),
        Fixture::new("ishikawa", "01_basic"),
        Fixture::new("wardley", "01_basic"),
        Fixture::new("tree_view", "01_basic"),
        Fixture::new("mindmap", "01_basic_tree"),
        Fixture::new("journey", "01_basic"),
        Fixture::new("gitgraph", "01_basic"),
        Fixture::new("timeline", "01_basic"),
        Fixture::new("requirement", "01_basic"),
        Fixture::new("c4", "01_context"),
        Fixture::new("cynefin", "01_basic"),
        Fixture::new("railroad", "01_basic"),
        Fixture::new("swimlanes", "01_basic"),
    ];

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    struct Fixture {
        kind: &'static str,
        name: &'static str,
    }

    impl Fixture {
        const fn new(kind: &'static str, name: &'static str) -> Self {
            Self { kind, name }
        }
    }

    #[test]
    fn renders_svg_and_text_frames() {
        let output = render_output(
            "graph TD\nA --> B",
            &WasmRenderOptions {
                theme: Some("tokyo-night".to_owned()),
                dark_theme: Some("dracula".to_owned()),
                charset: Some("unicode".to_owned()),
                width: Some(40),
                padding: Some(4),
                font: Some("Fira Code".to_owned()),
                ..WasmRenderOptions::default()
            },
        )
        .unwrap();

        assert!(output.svg.starts_with("<svg "));
        assert!(output.svg.contains(r#"font-family="Fira Code""#));
        assert!(output.svg.contains(r##"fill="#1a1b26""##));
        assert!(output.svg.contains("@media (prefers-color-scheme: dark)"));
        assert!(output.svg.contains(r##"rect { fill: #282a36; }"##));
        assert!(output.svg.contains(r#"<text x="4""#));
        assert!(!output.frames.is_empty());
        assert!(output.frames[0].text.contains('┌'));
        assert!(
            output.frames[0]
                .text
                .lines()
                .all(|line| line.chars().count() == 40)
        );
    }

    #[test]
    fn renders_kumecast_svg_and_text_frames() {
        let mut frame = Frame::new(1, 1);
        frame.write_text(0, 0, "A", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![KeyFrame::new(
            frame,
            std::time::Duration::from_millis(100),
        )]);
        let cast = Kumecast::from_timeline("flowchart", "graph TD\nA", Theme::github(), &timeline)
            .to_json_string()
            .unwrap();
        let output = render_cast_output(
            &cast,
            &WasmRenderOptions {
                speed: Some(2.0),
                repeat: Some(true),
                ..WasmRenderOptions::default()
            },
        )
        .unwrap();

        assert!(output.svg.starts_with("<svg "));
        assert_eq!(output.frames[0].text, "A");
        assert_eq!(output.frames[0].duration_ms, 50);
    }

    #[test]
    fn rejects_unknown_options() {
        assert!(
            render_output(
                "graph TD\nA --> B",
                &WasmRenderOptions {
                    theme: Some("missing".to_owned()),
                    ..WasmRenderOptions::default()
                },
            )
            .is_err()
        );
        assert!(
            render_output(
                "graph TD\nA --> B",
                &WasmRenderOptions {
                    dark_theme: Some("missing".to_owned()),
                    ..WasmRenderOptions::default()
                },
            )
            .is_err()
        );
        assert!(
            render_output(
                "graph TD\nA --> B",
                &WasmRenderOptions {
                    charset: Some("nerdfont".to_owned()),
                    ..WasmRenderOptions::default()
                },
            )
            .is_err()
        );
    }

    #[test]
    fn rejects_invalid_animation_and_svg_options() {
        let speed_error = render_output(
            "graph TD\nA --> B",
            &WasmRenderOptions {
                speed: Some(0.0),
                ..WasmRenderOptions::default()
            },
        )
        .unwrap_err();
        assert!(speed_error.contains("invalid animation options"));

        let animation_error = render_output(
            "graph TD\nA --> B",
            &WasmRenderOptions {
                svg_animation: Some("blink".to_owned()),
                ..WasmRenderOptions::default()
            },
        )
        .unwrap_err();
        assert!(animation_error.contains("unknown svgAnimation"));

        let parse_error =
            render_output("notARealRoot\nA", &WasmRenderOptions::default()).unwrap_err();
        assert!(parse_error.contains("parse error"));
        assert!(parse_error.contains("line 1 column 1"));
        assert!(parse_error.contains("suggestion: start with a supported Mermaid root"));

        let config_error = render_output(
            "---\ntitle: bad\n---\ngraph TD\nA --> B",
            &WasmRenderOptions::default(),
        )
        .unwrap_err();
        assert!(config_error.contains("Mermaid frontmatter/init/layout/theme config"));
        assert!(
            config_error
                .contains("suggestion: remove Mermaid frontmatter/init/layout/theme config")
        );
    }

    #[test]
    fn supports_css_keyframe_svg_mode() {
        let config = svg_config(&WasmRenderOptions {
            svg_animation: Some("css-keyframes".to_owned()),
            padding: Some(6),
            font: Some("IBM Plex Mono".to_owned()),
            ..WasmRenderOptions::default()
        })
        .unwrap();

        assert_eq!(config.padding, 6);
        assert_eq!(config.font_family, "IBM Plex Mono");
        assert_eq!(
            config.animation,
            kumeyuri_render_svg::SvgAnimationMode::CssKeyframes
        );
    }

    #[test]
    fn render_cast_rejects_invalid_json_and_invalid_speed() {
        let json_error = render_cast_output("{", &WasmRenderOptions::default()).unwrap_err();
        assert!(!json_error.is_empty());

        let mut frame = Frame::new(1, 1);
        frame.write_text(0, 0, "A", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![KeyFrame::new(
            frame,
            std::time::Duration::from_millis(100),
        )]);
        let cast = Kumecast::from_timeline("flowchart", "graph TD\nA", Theme::github(), &timeline)
            .to_json_string()
            .unwrap();
        let speed_error = render_cast_output(
            &cast,
            &WasmRenderOptions {
                speed: Some(f32::NAN),
                ..WasmRenderOptions::default()
            },
        )
        .unwrap_err();
        assert!(speed_error.contains("invalid animation options"));
    }

    #[test]
    fn render_cast_can_override_repeat_without_scaling_speed() {
        let mut frame = Frame::new(1, 1);
        frame.write_text(0, 0, "A", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![KeyFrame::new(
            frame,
            std::time::Duration::from_millis(125),
        )])
        .with_repeat(true);
        let cast = Kumecast::from_timeline("flowchart", "graph TD\nA", Theme::github(), &timeline)
            .to_json_string()
            .unwrap();
        let output = render_cast_output(
            &cast,
            &WasmRenderOptions {
                repeat: Some(false),
                ..WasmRenderOptions::default()
            },
        )
        .unwrap();

        assert_eq!(output.frames[0].duration_ms, 125);
        assert!(!output.svg.contains("animation-iteration-count: infinite"));
    }

    #[test]
    fn duration_milliseconds_saturate_to_u64_max() {
        let frame = Frame::new(1, 1);
        let keyframe = KeyFrame::new(frame, std::time::Duration::from_secs(u64::MAX));

        assert_eq!(duration_ms(&keyframe), u64::MAX);
    }

    #[test]
    fn all_supported_roots_have_wasm_output_hash_snapshots() {
        let root = repo_root();
        let actual = wasm_hashes(&root);
        let expected_path = root
            .join("tests/golden/kumeyuri-cross-format")
            .join("wasm_hashes.txt");
        let expected = fs::read_to_string(&expected_path).unwrap_or_else(|error| {
            panic!(
                "failed to read {}: {error}\nexpected contents:\n{actual}",
                expected_path.display(),
            )
        });

        assert_eq!(actual, expected);
    }

    fn wasm_hashes(root: &Path) -> String {
        let mut output = String::new();
        for fixture in FIXTURES {
            let source = read_fixture(root, fixture);
            let rendered =
                render_output(&source, &WasmRenderOptions::default()).unwrap_or_else(|error| {
                    panic!(
                        "failed to render {}/{}: {error}",
                        fixture.kind, fixture.name
                    )
                });
            let mut fingerprint = String::new();
            fingerprint.push_str(&normalize_svg(&rendered.svg));
            for (index, frame) in rendered.frames.iter().enumerate() {
                writeln!(
                    &mut fingerprint,
                    "frame:{index}:duration_ms:{}",
                    frame.duration_ms
                )
                .expect("failed to write wasm frame header");
                fingerprint.push_str(&frame.text);
                fingerprint.push('\n');
            }
            writeln!(
                &mut output,
                "{}/{} wasm={:016x}",
                fixture.kind,
                fixture.name,
                hash_str(&fingerprint),
            )
            .expect("failed to write wasm hash line");
        }
        output
    }

    fn normalize_svg(svg: &str) -> String {
        let mut normalized = svg
            .lines()
            .map(str::trim_end)
            .collect::<Vec<_>>()
            .join("\n");
        normalized.push('\n');
        normalized
    }

    fn read_fixture(root: &Path, fixture: Fixture) -> String {
        let path = root
            .join("tests/snapshots")
            .join(fixture.kind)
            .join("input")
            .join(format!("{}.mmd", fixture.name));
        fs::read_to_string(&path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()))
    }

    fn hash_str(value: &str) -> u64 {
        let mut hash = 0xcbf29ce484222325u64;
        for byte in value.as_bytes() {
            hash ^= u64::from(*byte);
            hash = hash.wrapping_mul(0x100000001b3);
        }
        hash
    }

    fn repo_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
    }
}
