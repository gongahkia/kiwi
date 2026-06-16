use kumeyuri_core::{
    animator::{AnimationOptions, Animator, KeyFrame, Timeline},
    ast::Diagram,
    frame::{Charset, StaticFrameRenderer},
    parser::Parser as MermaidParser,
    text::{TextOutputBackend, TextOutputConfig},
    theme::{BuiltInTheme, RgbColor, Theme},
};
use kumeyuri_render_svg::{SvgAnimationMode, SvgRenderConfig, SvgRenderer};
use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct WasmRenderer;

#[wasm_bindgen]
impl WasmRenderer {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Self {
        Self
    }

    pub fn render(&self, source: &str, options: JsValue) -> Result<JsValue, JsValue> {
        render(source, options)
    }
}

#[wasm_bindgen]
pub fn render(source: &str, options: JsValue) -> Result<JsValue, JsValue> {
    let options = decode_options(options)?;
    render_output(source, &options)
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
        format!(
            "parse error {:?} at {}..{}",
            error.kind, error.span.start, error.span.end
        )
    })
}

#[cfg(test)]
mod tests {
    use super::{WasmRenderOptions, render_output};

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
}
