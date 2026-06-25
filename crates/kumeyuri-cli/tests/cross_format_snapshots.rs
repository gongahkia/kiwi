use std::{
    fmt::Write as _,
    fs,
    path::{Path, PathBuf},
};

use kumeyuri_core::{
    animator::{AnimationOptions, Animator, Timeline},
    frame::StaticFrameRenderer,
    parser::Parser,
    text::{TextOutputBackend, TextOutputConfig},
    theme::{RgbColor, Theme},
};
use kumeyuri_render_raster::{RasterRenderConfig, RasterRenderer, RgbaColor};
use kumeyuri_render_svg::{SvgRenderConfig, SvgRenderer};
use kumeyuri_render_tui::TuiRenderer;

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
fn all_supported_roots_have_cross_format_hash_snapshots() {
    let root = repo_root();
    let actual = cross_format_hashes(&root);
    let expected_path = root
        .join("tests/golden/kumeyuri-cross-format")
        .join("render_hashes.txt");
    let expected = fs::read_to_string(&expected_path).unwrap_or_else(|error| {
        panic!(
            "failed to read {}: {error}\nexpected contents:\n{actual}",
            expected_path.display(),
        )
    });

    assert_eq!(actual, expected);
}

fn cross_format_hashes(root: &Path) -> String {
    let theme = Theme::github();
    let frame_renderer = StaticFrameRenderer::default().with_theme(theme);
    let svg_renderer = SvgRenderer::new(SvgRenderConfig {
        padding: 1,
        foreground: css_color(theme.colors.foreground),
        background: css_color(theme.colors.background),
        ..SvgRenderConfig::default()
    });
    let raster_renderer = RasterRenderer::new(RasterRenderConfig {
        scale: 1,
        padding: 1,
        foreground: rgba_color(theme.colors.foreground),
        background: rgba_color(theme.colors.background),
    })
    .expect("cross-format raster config is valid");
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });
    let tui = TuiRenderer::default();
    let mut output = String::new();

    for fixture in FIXTURES {
        let source = read_fixture(root, fixture);
        let diagram = Parser::parse_diagram(&source).unwrap_or_else(|error| {
            panic!(
                "failed to parse {}/{}: {:?} at {}..{}",
                fixture.kind, fixture.name, error.kind, error.span.start, error.span.end,
            )
        });
        let timeline = Animator::animate_diagram_with_options_and_renderer(
            &diagram,
            AnimationOptions::default(),
            frame_renderer,
        )
        .unwrap_or_else(|error| {
            panic!(
                "failed to animate {}/{}: {error:?}",
                fixture.kind, fixture.name
            )
        });
        let frame = timeline
            .keyframes()
            .first()
            .expect("timeline has at least one frame")
            .frame();
        let text_hash = hash_text_timeline(&timeline, &text);
        let svg_hash = hash_str(&normalize_svg(&svg_renderer.render_timeline(&timeline)));
        let png_hash = hash_bytes(
            &raster_renderer
                .render_frame(frame)
                .expect("fixture renders to png"),
        );
        let gif_hash = hash_bytes(
            &raster_renderer
                .render_gif(&timeline)
                .expect("fixture renders to gif"),
        );
        let apng_hash = hash_bytes(
            &raster_renderer
                .render_apng(&timeline)
                .expect("fixture renders to apng"),
        );
        let webp_hash = hash_bytes(
            &raster_renderer
                .render_webp(&timeline)
                .expect("fixture renders to webp"),
        );
        let tui_hash = hash_tui_timeline(&timeline, tui);

        writeln!(
            &mut output,
            "{}/{} text={text_hash:016x} svg={svg_hash:016x} png={png_hash:016x} gif={gif_hash:016x} apng={apng_hash:016x} webp={webp_hash:016x} tui={tui_hash:016x}",
            fixture.kind, fixture.name,
        )
        .expect("failed to write hash line");
    }
    output
}

fn hash_text_timeline(timeline: &Timeline, text: &TextOutputBackend) -> u64 {
    let mut output = String::new();
    for (index, keyframe) in timeline.keyframes().iter().enumerate() {
        writeln!(
            &mut output,
            "frame:{index}:duration_ms:{}",
            keyframe.duration().as_millis()
        )
        .expect("failed to write text frame header");
        output.push_str(&text.render_frame(keyframe.frame()));
        output.push('\n');
    }
    hash_str(&output)
}

fn hash_tui_timeline(timeline: &Timeline, tui: TuiRenderer) -> u64 {
    let mut output = String::new();
    for (index, keyframe) in timeline.keyframes().iter().enumerate() {
        writeln!(
            &mut output,
            "frame:{index}:duration_ms:{}",
            keyframe.duration().as_millis()
        )
        .expect("failed to write tui frame header");
        output.push_str(&tui.frame_text(keyframe.frame()));
        output.push('\n');
    }
    hash_str(&output)
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
    hash_bytes(value.as_bytes())
}

fn hash_bytes(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn css_color(color: RgbColor) -> String {
    format!("#{:02x}{:02x}{:02x}", color.red, color.green, color.blue)
}

fn rgba_color(color: RgbColor) -> RgbaColor {
    RgbaColor::rgb(color.red, color.green, color.blue)
}

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}
