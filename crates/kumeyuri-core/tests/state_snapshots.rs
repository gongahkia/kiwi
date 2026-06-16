use std::{fs, path::Path};

use kumeyuri_core::{
    ast::DiagramKind,
    frame::StaticFrameRenderer,
    parser::Parser,
    text::{TextOutputBackend, TextOutputConfig},
};

const SNAPSHOT_NAMES: [&str; 10] = [
    "01_start_to_idle",
    "02_left_right_direction",
    "03_three_state_chain",
    "04_transition_labels",
    "05_state_alias",
    "06_choice_state",
    "07_fork_state",
    "08_directive_comment",
    "09_state_declarations",
    "10_composite_opening",
];

#[test]
fn state_static_snapshots_match() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let renderer = StaticFrameRenderer::default();
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });

    for name in SNAPSHOT_NAMES {
        let source_path = root
            .join("tests/snapshots/state/input")
            .join(format!("{name}.mmd"));
        let expected_path = root
            .join("tests/snapshots/state/output")
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
        assert!(matches!(diagram.kind, DiagramKind::State(_)));
        let actual = text.render_frame(&renderer.render_diagram(&diagram));

        assert_eq!(actual, expected, "snapshot mismatch for {name}");
    }
}
