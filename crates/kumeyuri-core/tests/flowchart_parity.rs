use kumeyuri_core::{
    ast::{DiagramKind, FlowNode, FlowShape, FlowchartAst, LabelKind},
    parser::{ParseErrorKind, Parser},
};

#[derive(Debug, Clone, Copy)]
struct FlowchartParityFixture {
    name: &'static str,
    source: &'static str,
    expected: FlowchartParityExpectation,
}

#[derive(Debug, Clone, Copy)]
enum FlowchartParityExpectation {
    Parses,
    Rejects(ParseErrorKind),
}

const FIXTURES: &[FlowchartParityFixture] = &[
    FlowchartParityFixture {
        name: "v11_named_shapes",
        source: include_str!("../../../tests/fuzz/flowchart-parity/v11_named_shapes.mmd"),
        expected: FlowchartParityExpectation::Parses,
    },
    FlowchartParityFixture {
        name: "markdown_strings",
        source: include_str!("../../../tests/fuzz/flowchart-parity/markdown_strings.mmd"),
        expected: FlowchartParityExpectation::Parses,
    },
    FlowchartParityFixture {
        name: "entity_escapes",
        source: include_str!("../../../tests/fuzz/flowchart-parity/entity_escapes.mmd"),
        expected: FlowchartParityExpectation::Parses,
    },
    FlowchartParityFixture {
        name: "multiline_labels",
        source: include_str!("../../../tests/fuzz/flowchart-parity/multiline_labels.mmd"),
        expected: FlowchartParityExpectation::Rejects(ParseErrorKind::UnknownFlowStatement),
    },
    FlowchartParityFixture {
        name: "edge_ids",
        source: include_str!("../../../tests/fuzz/flowchart-parity/edge_ids.mmd"),
        expected: FlowchartParityExpectation::Rejects(ParseErrorKind::UnknownFlowStatement),
    },
    FlowchartParityFixture {
        name: "edge_animation_classes",
        source: include_str!("../../../tests/fuzz/flowchart-parity/edge_animation_classes.mmd"),
        expected: FlowchartParityExpectation::Rejects(ParseErrorKind::UnknownFlowStatement),
    },
    FlowchartParityFixture {
        name: "link_style",
        source: include_str!("../../../tests/fuzz/flowchart-parity/link_style.mmd"),
        expected: FlowchartParityExpectation::Rejects(ParseErrorKind::UnknownFlowStatement),
    },
    FlowchartParityFixture {
        name: "style_statement",
        source: include_str!("../../../tests/fuzz/flowchart-parity/style_statement.mmd"),
        expected: FlowchartParityExpectation::Rejects(ParseErrorKind::UnknownFlowStatement),
    },
    FlowchartParityFixture {
        name: "click_statement",
        source: include_str!("../../../tests/fuzz/flowchart-parity/click_statement.mmd"),
        expected: FlowchartParityExpectation::Rejects(ParseErrorKind::UnknownFlowStatement),
    },
];

#[test]
fn flowchart_parity_fixtures_have_expected_parser_status() {
    for fixture in FIXTURES {
        let parsed = Parser::parse_diagram(fixture.source);

        match fixture.expected {
            FlowchartParityExpectation::Parses => {
                let diagram = parsed.unwrap_or_else(|error| {
                    panic!(
                        "{} should parse, got {:?} at {}..{}",
                        fixture.name, error.kind, error.span.start, error.span.end,
                    )
                });
                assert!(
                    matches!(diagram.kind, DiagramKind::Flowchart(_)),
                    "{}",
                    fixture.name,
                );
            }
            FlowchartParityExpectation::Rejects(kind) => {
                let error = parsed.unwrap_err();

                assert_eq!(error.kind, kind, "{}", fixture.name);
            }
        }
    }
}

#[test]
fn v11_named_shape_fixture_preserves_shape_names() {
    let diagram = Parser::parse_diagram(FIXTURES[0].source).unwrap();
    let DiagramKind::Flowchart(ast) = diagram.kind else {
        panic!("expected flowchart");
    };

    assert_eq!(
        [
            node_by_id(&ast, "A").shape.value.clone(),
            node_by_id(&ast, "B").shape.value.clone(),
            node_by_id(&ast, "C").shape.value.clone(),
        ],
        [
            FlowShape::Named("notch-rect".to_owned()),
            FlowShape::Named("hourglass".to_owned()),
            FlowShape::Named("bolt".to_owned()),
        ],
    );
}

#[test]
fn markdown_string_fixture_preserves_markdown_label_kind() {
    let diagram = Parser::parse_diagram(FIXTURES[1].source).unwrap();
    let DiagramKind::Flowchart(ast) = diagram.kind else {
        panic!("expected flowchart");
    };
    let label = node_by_id(&ast, "A")
        .label
        .as_ref()
        .expect("node has label");

    assert_eq!(label.kind, LabelKind::Markdown);
    assert_eq!(label.text, "bold");
}

#[test]
fn entity_escape_fixture_tracks_literal_decode_gap() {
    let diagram = Parser::parse_diagram(FIXTURES[2].source).unwrap();
    let DiagramKind::Flowchart(ast) = diagram.kind else {
        panic!("expected flowchart");
    };
    let label = node_by_id(&ast, "A")
        .label
        .as_ref()
        .expect("node has label");

    assert_eq!(label.text, "Tom &amp; Jerry #35;");
}

fn node_by_id<'a>(ast: &'a FlowchartAst, id: &str) -> &'a FlowNode {
    ast.nodes
        .iter()
        .chain(ast.edges.iter().flat_map(|edge| [&edge.from, &edge.to]))
        .find(|node| node.id.value == id)
        .unwrap_or_else(|| panic!("missing node {id}"))
}
