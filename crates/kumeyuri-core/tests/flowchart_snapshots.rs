use std::{fs, path::Path};

use kumeyuri_core::{
    ast::DiagramKind,
    frame::StaticFrameRenderer,
    parser::Parser,
    text::{TextOutputBackend, TextOutputConfig},
};

const SNAPSHOT_NAMES: [&str; 29] = [
    "01_single_node",
    "02_two_nodes_linked",
    "03_three_node_chain",
    "04_fan_out",
    "05_fan_in",
    "06_left_right_chain",
    "07_bottom_top_chain",
    "08_right_left_chain",
    "09_labelled_edge",
    "10_pipe_label",
    "11_dotted_edge",
    "12_thick_edge",
    "13_bidirectional_edge",
    "14_mixed_shapes",
    "15_round_and_stadium",
    "16_subgraph_simple",
    "17_nested_subgraph",
    "18_class_styles",
    "19_directive_comment",
    "20_disconnected_roots",
    "21_classic_shapes",
    "22_nested_subgraph_direction",
    "23_external_subgraph_edges",
    "24_self_loop",
    "25_left_right_back_edge",
    "26_long_labels",
    "27_disconnected_clusters",
    "28_dense_fan_in_out",
    "29_quoted_punctuation",
];

#[test]
fn flowchart_static_snapshots_match() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let renderer = StaticFrameRenderer::default();
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });

    for name in SNAPSHOT_NAMES {
        let source_path = root
            .join("tests/snapshots/flowchart/input")
            .join(format!("{name}.mmd"));
        let expected_path = root
            .join("tests/golden/kumeyuri-static/flowchart")
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
        assert!(matches!(diagram.kind, DiagramKind::Flowchart(_)));
        let actual = text.render_frame(&renderer.render_diagram(&diagram));

        assert_eq!(actual, expected, "snapshot mismatch for {name}");
    }
}
