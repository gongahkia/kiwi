use std::{fs, path::Path};

use kumeyuri_core::{
    animator::Animator,
    ast::DiagramKind,
    frame::StaticFrameRenderer,
    parser::Parser,
    text::{TextOutputBackend, TextOutputConfig},
};

const SNAPSHOT_NAMES: [&str; 2] = ["01_basic", "02_handoffs"];

#[test]
fn swimlanes_static_snapshots_match() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let renderer = StaticFrameRenderer::default();
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });

    for name in SNAPSHOT_NAMES {
        let source_path = root
            .join("tests/snapshots/swimlanes/input")
            .join(format!("{name}.mmd"));
        let expected_path = root
            .join("tests/golden/kumeyuri-static/swimlanes")
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
        assert!(matches!(diagram.kind, DiagramKind::Swimlanes(_)));
        let actual = text.render_frame(&renderer.render_diagram(&diagram));

        assert_eq!(actual, expected, "snapshot mismatch for {name}");
    }
}

#[test]
fn swimlanes_animation_collapses_to_static_frame() {
    let source = include_str!("../../../tests/snapshots/swimlanes/input/02_handoffs.mmd");
    let diagram = Parser::parse_diagram(source).unwrap();
    assert!(matches!(diagram.kind, DiagramKind::Swimlanes(_)));

    let timeline = Animator::animate_diagram(&diagram).unwrap();

    assert_eq!(timeline.len(), 1);
}
