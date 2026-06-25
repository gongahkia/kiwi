use std::{fs, path::Path};

use kumeyuri_core::{animator::Animator, parser::Parser};

const STATIC_ONLY_FIXTURES: &[(&str, &str)] = &[
    ("architecture", "01_basic"),
    ("block", "01_basic"),
    ("c4", "01_context"),
    ("cynefin", "01_basic"),
    ("event_modeling", "01_basic"),
    ("ishikawa", "01_basic"),
    ("kanban", "01_basic"),
    ("packet", "01_tcp"),
    ("quadrant", "01_basic"),
    ("radar", "01_basic"),
    ("railroad", "01_basic"),
    ("requirement", "01_basic"),
    ("sankey", "01_basic"),
    ("swimlanes", "01_basic"),
    ("tree_view", "01_basic"),
    ("treemap", "01_basic"),
    ("venn", "01_basic"),
    ("wardley", "01_basic"),
    ("xychart", "01_basic"),
    ("zenuml", "01_basic"),
];

#[test]
fn static_only_roots_collapse_animation_to_single_frame() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");

    for (kind, name) in STATIC_ONLY_FIXTURES {
        let source_path = root
            .join("tests/snapshots")
            .join(kind)
            .join("input")
            .join(format!("{name}.mmd"));
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
        let timeline = Animator::animate_diagram(&diagram).unwrap_or_else(|error| {
            panic!("failed to animate {}: {error:?}", source_path.display())
        });

        assert_eq!(
            timeline.len(),
            1,
            "static-only {kind}/{name} should collapse to one frame",
        );
    }
}
