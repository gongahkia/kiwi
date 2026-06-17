use std::{fs, path::Path};

use kumeyuri_core::{
    ast::DiagramKind,
    frame::StaticFrameRenderer,
    parser::Parser,
    text::{TextOutputBackend, TextOutputConfig},
};

const SNAPSHOT_NAMES: [&str; 4] = [
    "01_basic",
    "02_sections_actors",
    "03_directive_comment",
    "04_actor_styles_config",
];

#[test]
fn journey_static_snapshots_match() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let renderer = StaticFrameRenderer::default();
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });

    for name in SNAPSHOT_NAMES {
        let source_path = root
            .join("tests/snapshots/journey/input")
            .join(format!("{name}.mmd"));
        let expected_path = root
            .join("tests/golden/kumeyuri-static/journey")
            .join(format!("{name}.txt"));
        let source = fs::read_to_string(&source_path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", source_path.display()));
        let expected = fs::read_to_string(&expected_path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", expected_path.display()));
        let diagram = Parser::parse_diagram(&source).unwrap_or_else(|error| {
            panic!(
                "failed to parse {}: {:?} at {}..{}",
                source_path.display(),
                error.kind,
                error.span.start,
                error.span.end,
            )
        });
        assert!(matches!(diagram.kind, DiagramKind::Journey(_)));
        let actual = text.render_frame(&renderer.render_diagram(&diagram));

        assert_eq!(actual, expected, "snapshot mismatch for {name}");
    }
}
