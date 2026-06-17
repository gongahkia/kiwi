use kumeyuri_core::parser::{ParseErrorKind, Parser};

const FIXTURES: &[(&str, &str, ParseErrorKind)] = &[
    (
        "flowchart_end_label",
        include_str!("../../../tests/fuzz/negative-mermaid/flowchart_end_label.mmd"),
        ParseErrorKind::ReservedFlowNodeLabel,
    ),
    (
        "flowchart_nested_shape",
        include_str!("../../../tests/fuzz/negative-mermaid/flowchart_nested_shape.mmd"),
        ParseErrorKind::UnknownFlowStatement,
    ),
    (
        "directive_like_comment",
        include_str!("../../../tests/fuzz/negative-mermaid/directive_like_comment.mmd"),
        ParseErrorKind::UnknownFlowStatement,
    ),
    (
        "malformed_frontmatter",
        include_str!("../../../tests/fuzz/negative-mermaid/malformed_frontmatter.mmd"),
        ParseErrorKind::ExpectedDiagramHeader,
    ),
    (
        "unknown_root_typo",
        include_str!("../../../tests/fuzz/negative-mermaid/unknown_root_typo.mmd"),
        ParseErrorKind::ExpectedDiagramHeader,
    ),
];

#[test]
fn negative_mermaid_fixtures_fail_fast() {
    for (name, source, expected) in FIXTURES {
        let error = Parser::parse_diagram(source).unwrap_err();

        assert_eq!(error.kind, *expected, "{name}");
    }
}
