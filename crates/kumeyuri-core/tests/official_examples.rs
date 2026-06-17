use kumeyuri_core::{ast::DiagramKind, parser::Parser};
use proptest::prelude::*;

const FIXTURES: &[(&str, &str)] = &[
    (
        "flowchart",
        include_str!("../../../tests/fuzz/official-mermaid/flowchart.mmd"),
    ),
    (
        "sequence",
        include_str!("../../../tests/fuzz/official-mermaid/sequence.mmd"),
    ),
    (
        "state",
        include_str!("../../../tests/fuzz/official-mermaid/state.mmd"),
    ),
    (
        "class",
        include_str!("../../../tests/fuzz/official-mermaid/class.mmd"),
    ),
    (
        "er",
        include_str!("../../../tests/fuzz/official-mermaid/er.mmd"),
    ),
    (
        "gantt",
        include_str!("../../../tests/fuzz/official-mermaid/gantt.mmd"),
    ),
    (
        "pie",
        include_str!("../../../tests/fuzz/official-mermaid/pie.mmd"),
    ),
    (
        "quadrant",
        include_str!("../../../tests/fuzz/official-mermaid/quadrant.mmd"),
    ),
    (
        "zenuml",
        include_str!("../../../tests/fuzz/official-mermaid/zenuml.mmd"),
    ),
    (
        "sankey",
        include_str!("../../../tests/fuzz/official-mermaid/sankey.mmd"),
    ),
    (
        "xychart",
        include_str!("../../../tests/fuzz/official-mermaid/xychart.mmd"),
    ),
    (
        "block",
        include_str!("../../../tests/fuzz/official-mermaid/block.mmd"),
    ),
    (
        "mindmap",
        include_str!("../../../tests/fuzz/official-mermaid/mindmap.mmd"),
    ),
    (
        "journey",
        include_str!("../../../tests/fuzz/official-mermaid/journey.mmd"),
    ),
    (
        "gitgraph",
        include_str!("../../../tests/fuzz/official-mermaid/gitgraph.mmd"),
    ),
    (
        "timeline",
        include_str!("../../../tests/fuzz/official-mermaid/timeline.mmd"),
    ),
    (
        "requirement",
        include_str!("../../../tests/fuzz/official-mermaid/requirement.mmd"),
    ),
    (
        "c4",
        include_str!("../../../tests/fuzz/official-mermaid/c4.mmd"),
    ),
];

proptest! {
    #[test]
    fn official_mermaid_fuzz_corpus_parses(
        (root, fixture) in prop::sample::select(FIXTURES.to_vec()),
        leading_blank_lines in 0usize..=2,
        indent_width in 0usize..=4,
        line_ending in prop::sample::select(vec!["\n", "\r\n"]),
        trailing_blank_line in any::<bool>(),
    ) {
        let source = fuzz_whitespace(fixture, leading_blank_lines, indent_width, line_ending, trailing_blank_line);
        let parsed = Parser::parse_diagram(&source);

        prop_assert!(parsed.is_ok(), "{root}: {parsed:?}\n{source}");
        let diagram = parsed.unwrap();

        prop_assert_eq!(diagram_kind_name(&diagram.kind), root);
    }
}

fn fuzz_whitespace(
    source: &str,
    leading_blank_lines: usize,
    indent_width: usize,
    line_ending: &str,
    trailing_blank_line: bool,
) -> String {
    let indent = " ".repeat(indent_width);
    let mut lines = Vec::new();
    lines.extend(std::iter::repeat_n(String::new(), leading_blank_lines));
    lines.extend(
        source
            .lines()
            .map(str::trim_end)
            .filter(|line| !line.trim().is_empty())
            .map(|line| format!("{indent}{line}")),
    );
    if trailing_blank_line {
        lines.push(String::new());
    }
    lines.join(line_ending)
}

fn diagram_kind_name(kind: &DiagramKind) -> &'static str {
    match kind {
        DiagramKind::Flowchart(_) => "flowchart",
        DiagramKind::Sequence(_) => "sequence",
        DiagramKind::State(_) => "state",
        DiagramKind::Class(_) => "class",
        DiagramKind::Er(_) => "er",
        DiagramKind::Gantt(_) => "gantt",
        DiagramKind::Pie(_) => "pie",
        DiagramKind::Quadrant(_) => "quadrant",
        DiagramKind::ZenUml(_) => "zenuml",
        DiagramKind::Sankey(_) => "sankey",
        DiagramKind::XyChart(_) => "xychart",
        DiagramKind::Block(_) => "block",
        DiagramKind::Mindmap(_) => "mindmap",
        DiagramKind::Journey(_) => "journey",
        DiagramKind::GitGraph(_) => "gitgraph",
        DiagramKind::Timeline(_) => "timeline",
        DiagramKind::Requirement(_) => "requirement",
        DiagramKind::C4(_) => "c4",
    }
}
