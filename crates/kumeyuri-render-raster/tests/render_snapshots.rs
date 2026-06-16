use std::{
    fs,
    path::{Path, PathBuf},
};

use image_compare::Algorithm;
use kumeyuri_core::{
    frame::{Frame, StaticFrameRenderer},
    parser::Parser,
    theme::{RgbColor, Theme},
};
use kumeyuri_render_raster::{RasterRenderConfig, RasterRenderer, RgbaColor};
use kumeyuri_render_svg::{SvgRenderConfig, SvgRenderer};

const UPDATE_ENV: &str = "KUMEYURI_UPDATE_RENDER_SNAPSHOTS";
const FIXTURES: [Fixture; 3] = [
    Fixture {
        kind: "flowchart",
        name: "03_three_node_chain",
    },
    Fixture {
        kind: "sequence",
        name: "03_multiple_messages",
    },
    Fixture {
        kind: "state",
        name: "03_three_state_chain",
    },
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Fixture {
    kind: &'static str,
    name: &'static str,
}

#[test]
fn svg_and_raster_outputs_match_snapshots() {
    let root = repo_root();
    let update = std::env::var_os(UPDATE_ENV).is_some();
    let theme = Theme::github();
    let frame_renderer = StaticFrameRenderer::default().with_theme(theme);
    let svg_renderer = SvgRenderer::new(SvgRenderConfig {
        padding: 2,
        foreground: css_color(theme.colors.foreground),
        background: css_color(theme.colors.background),
        ..SvgRenderConfig::default()
    });
    let raster_renderer = RasterRenderer::new(RasterRenderConfig {
        scale: 1,
        padding: 2,
        foreground: rgba_color(theme.colors.foreground),
        background: rgba_color(theme.colors.background),
    })
    .expect("snapshot raster config is valid");

    for fixture in FIXTURES {
        let frame = render_fixture_frame(&root, fixture, &frame_renderer);
        let actual_svg = normalize_svg_snapshot(&svg_renderer.render_frame(&frame));
        let actual_png = raster_renderer
            .render_frame(&frame)
            .expect("snapshot frame renders to png");
        let snapshot_dir = root.join("tests/golden/kumeyuri-render").join(fixture.kind);
        let svg_path = snapshot_dir.join(format!("{}.svg", fixture.name));
        let png_path = snapshot_dir.join(format!("{}.png", fixture.name));

        if update {
            fs::create_dir_all(&snapshot_dir).unwrap_or_else(|error| {
                panic!("failed to create {}: {error}", snapshot_dir.display())
            });
            fs::write(&svg_path, actual_svg)
                .unwrap_or_else(|error| panic!("failed to write {}: {error}", svg_path.display()));
            fs::write(&png_path, actual_png)
                .unwrap_or_else(|error| panic!("failed to write {}: {error}", png_path.display()));
            continue;
        }

        let expected_svg = fs::read_to_string(&svg_path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", svg_path.display()));
        assert_eq!(
            actual_svg, expected_svg,
            "SVG snapshot mismatch for {}/{}",
            fixture.kind, fixture.name,
        );

        let expected_png = fs::read(&png_path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", png_path.display()));
        let similarity = png_similarity(&actual_png, &expected_png);
        assert_eq!(
            similarity, 1.0,
            "PNG snapshot mismatch for {}/{}: RMS similarity {similarity}",
            fixture.kind, fixture.name,
        );
    }
}

fn render_fixture_frame(root: &Path, fixture: Fixture, renderer: &StaticFrameRenderer) -> Frame {
    let source_path = root
        .join("tests/snapshots")
        .join(fixture.kind)
        .join("input")
        .join(format!("{}.mmd", fixture.name));
    let source = fs::read_to_string(&source_path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", source_path.display()));
    let diagram = Parser::parse_diagram(&source).unwrap_or_else(|error| {
        panic!(
            "failed to parse {}: {:?} at {}..{}",
            source_path.display(),
            error.kind,
            error.span.start,
            error.span.end,
        )
    });
    renderer.render_diagram(&diagram)
}

fn png_similarity(actual_png: &[u8], expected_png: &[u8]) -> f64 {
    let actual = image::load_from_memory(actual_png)
        .expect("actual snapshot png decodes")
        .into_rgb8();
    let expected = image::load_from_memory(expected_png)
        .expect("expected snapshot png decodes")
        .into_rgb8();
    image_compare::rgb_similarity_structure(&Algorithm::RootMeanSquared, &actual, &expected)
        .expect("snapshot png dimensions match")
        .score
}

fn normalize_svg_snapshot(svg: &str) -> String {
    let mut normalized = svg
        .lines()
        .map(str::trim_end)
        .collect::<Vec<_>>()
        .join("\n");
    normalized.push('\n');
    normalized
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
