use std::{fs, path::Path};

use kumeyuri_core::{
    ast::{Diagram, DiagramKind, IshikawaNode, MindmapNode, Span, TreeViewNode, TreemapNode},
    parser::Parser,
};
use proptest::prelude::*;

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

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParserSummary {
    kind: &'static str,
    counts: [usize; 4],
}

proptest! {
    #![proptest_config(ProptestConfig {
        cases: 128,
        failure_persistence: None,
        ..ProptestConfig::default()
    })]

    #[test]
    fn supported_root_parsers_keep_counts_and_valid_spans_under_whitespace_fuzz(
        fixture in prop::sample::select(FIXTURES.to_vec()),
        leading_blank_lines in 0usize..=2,
        indent_width in 0usize..=4,
        line_ending in prop::sample::select(vec!["\n", "\r\n"]),
        trailing_blank_line in any::<bool>(),
    ) {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let source = read_fixture(&root, fixture);
        let baseline = parse_summary(&source);
        let fuzzed = fuzz_source(
            &source,
            leading_blank_lines,
            indent_width,
            line_ending,
            trailing_blank_line,
        );
        let actual = parse_summary(&fuzzed);

        prop_assert_eq!(actual, baseline, "{}/{}\n{}", fixture.kind, fixture.name, fuzzed);
    }
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

fn fuzz_source(
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

fn parse_summary(source: &str) -> ParserSummary {
    let diagram = Parser::parse_diagram(source).unwrap_or_else(|error| {
        panic!(
            "failed to parse fixture: {:?} at {}..{}\n{source}",
            error.kind, error.span.start, error.span.end,
        )
    });
    assert_root_spans(&diagram, source);
    summary(&diagram)
}

fn assert_root_spans(diagram: &Diagram, source: &str) {
    assert_span(diagram.span, source);
    assert_span(diagram.metadata.span, source);
    for directive in &diagram.directives {
        assert_span(directive.span, source);
    }
    match &diagram.kind {
        DiagramKind::Flowchart(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Sequence(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::State(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Class(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Er(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Gantt(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Pie(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Quadrant(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::ZenUml(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Sankey(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::XyChart(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Block(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Packet(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Kanban(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Architecture(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Radar(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::EventModeling(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Treemap(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Venn(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Ishikawa(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Wardley(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::TreeView(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Mindmap(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Journey(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::GitGraph(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Timeline(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Requirement(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::C4(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Cynefin(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Railroad(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
        }
        DiagramKind::Swimlanes(ast) => {
            assert_span(ast.header.span, source);
            assert_span(ast.span, source);
            assert_span(ast.graph.span, source);
        }
    }
}

fn assert_span(span: Span, source: &str) {
    assert!(
        span.start <= span.end && span.end <= source.len(),
        "invalid span {}..{} for source len {}",
        span.start,
        span.end,
        source.len(),
    );
}

fn summary(diagram: &Diagram) -> ParserSummary {
    match &diagram.kind {
        DiagramKind::Flowchart(ast) => ParserSummary {
            kind: "flowchart",
            counts: [
                ast.statements.len(),
                ast.nodes.len(),
                ast.edges.len(),
                ast.subgraphs.len(),
            ],
        },
        DiagramKind::Sequence(ast) => ParserSummary {
            kind: "sequence",
            counts: [
                ast.statements.len(),
                ast.participants.len(),
                ast.boxes.len(),
                0,
            ],
        },
        DiagramKind::State(ast) => ParserSummary {
            kind: "state",
            counts: [
                ast.statements.len(),
                ast.states.len(),
                ast.transitions.len(),
                ast.classes.len(),
            ],
        },
        DiagramKind::Class(ast) => ParserSummary {
            kind: "class",
            counts: [
                ast.statements.len(),
                ast.classes.len(),
                ast.relationships.len(),
                0,
            ],
        },
        DiagramKind::Er(ast) => ParserSummary {
            kind: "er",
            counts: [
                ast.statements.len(),
                ast.entities.len(),
                ast.relationships.len(),
                0,
            ],
        },
        DiagramKind::Gantt(ast) => ParserSummary {
            kind: "gantt",
            counts: [ast.statements.len(), ast.tasks.len(), 0, 0],
        },
        DiagramKind::Pie(ast) => ParserSummary {
            kind: "pie",
            counts: [
                ast.statements.len(),
                ast.slices.len(),
                usize::from(ast.show_data),
                0,
            ],
        },
        DiagramKind::Quadrant(ast) => ParserSummary {
            kind: "quadrant",
            counts: [
                ast.statements.len(),
                ast.points.len(),
                ast.quadrants.len(),
                ast.classes.len(),
            ],
        },
        DiagramKind::ZenUml(ast) => ParserSummary {
            kind: "zenuml",
            counts: [
                ast.statements.len(),
                ast.participants.len(),
                ast.messages.len(),
                ast.fragments.len(),
            ],
        },
        DiagramKind::Sankey(ast) => ParserSummary {
            kind: "sankey",
            counts: [ast.statements.len(), ast.links.len(), 0, 0],
        },
        DiagramKind::XyChart(ast) => ParserSummary {
            kind: "xychart",
            counts: [
                ast.statements.len(),
                ast.series.len(),
                usize::from(ast.x_axis.is_some()),
                usize::from(ast.y_axis.is_some()),
            ],
        },
        DiagramKind::Block(ast) => ParserSummary {
            kind: "block",
            counts: [
                ast.statements.len(),
                ast.blocks.len(),
                ast.edges.len(),
                ast.classes.len() + ast.styles.len(),
            ],
        },
        DiagramKind::Packet(ast) => ParserSummary {
            kind: "packet",
            counts: [ast.statements.len(), ast.fields.len(), 0, 0],
        },
        DiagramKind::Kanban(ast) => ParserSummary {
            kind: "kanban",
            counts: [
                ast.statements.len(),
                ast.columns.len(),
                ast.columns.iter().map(|column| column.tasks.len()).sum(),
                0,
            ],
        },
        DiagramKind::Architecture(ast) => ParserSummary {
            kind: "architecture",
            counts: [
                ast.statements.len(),
                ast.groups.len() + ast.services.len() + ast.junctions.len(),
                ast.edges.len(),
                ast.alignments.len(),
            ],
        },
        DiagramKind::Radar(ast) => ParserSummary {
            kind: "radar",
            counts: [
                ast.statements.len(),
                ast.axes.len(),
                ast.curves.len(),
                ast.options.len(),
            ],
        },
        DiagramKind::EventModeling(ast) => ParserSummary {
            kind: "event_modeling",
            counts: [
                ast.statements.len(),
                ast.timeframes.len(),
                ast.data_blocks.len(),
                ast.timeframes
                    .iter()
                    .map(|frame| frame.relations.len())
                    .sum(),
            ],
        },
        DiagramKind::Treemap(ast) => ParserSummary {
            kind: "treemap",
            counts: [
                ast.statements.len(),
                ast.roots.len(),
                ast.roots.iter().map(count_treemap_nodes).sum(),
                0,
            ],
        },
        DiagramKind::Venn(ast) => ParserSummary {
            kind: "venn",
            counts: [
                ast.statements.len(),
                ast.sets.len(),
                ast.unions.len(),
                ast.texts.len() + ast.styles.len(),
            ],
        },
        DiagramKind::Ishikawa(ast) => ParserSummary {
            kind: "ishikawa",
            counts: [
                ast.statements.len(),
                ast.causes.len(),
                ast.causes.iter().map(count_ishikawa_nodes).sum(),
                0,
            ],
        },
        DiagramKind::Wardley(ast) => ParserSummary {
            kind: "wardley",
            counts: [
                ast.statements.len(),
                ast.components.len(),
                ast.links.len(),
                ast.evolves.len() + ast.notes.len() + ast.annotations.len() + ast.forces.len(),
            ],
        },
        DiagramKind::TreeView(ast) => ParserSummary {
            kind: "tree_view",
            counts: [
                ast.statements.len(),
                ast.roots.len(),
                ast.roots.iter().map(count_tree_view_nodes).sum(),
                0,
            ],
        },
        DiagramKind::Mindmap(ast) => ParserSummary {
            kind: "mindmap",
            counts: [
                ast.statements.len(),
                ast.roots.len(),
                ast.roots.iter().map(count_mindmap_nodes).sum(),
                0,
            ],
        },
        DiagramKind::Journey(ast) => ParserSummary {
            kind: "journey",
            counts: [ast.statements.len(), ast.tasks.len(), 0, 0],
        },
        DiagramKind::GitGraph(ast) => ParserSummary {
            kind: "gitgraph",
            counts: [
                ast.statements.len(),
                ast.commits.len(),
                ast.branches.len(),
                ast.merges.len() + ast.cherry_picks.len(),
            ],
        },
        DiagramKind::Timeline(ast) => ParserSummary {
            kind: "timeline",
            counts: [
                ast.statements.len(),
                ast.periods.len(),
                ast.periods.iter().map(|period| period.events.len()).sum(),
                0,
            ],
        },
        DiagramKind::Requirement(ast) => ParserSummary {
            kind: "requirement",
            counts: [
                ast.statements.len(),
                ast.requirements.len() + ast.elements.len(),
                ast.relationships.len(),
                ast.classes.len() + ast.styles.len(),
            ],
        },
        DiagramKind::C4(ast) => ParserSummary {
            kind: "c4",
            counts: [
                ast.statements.len(),
                ast.elements.len(),
                ast.relationships.len(),
                ast.boundaries.len(),
            ],
        },
        DiagramKind::Cynefin(ast) => ParserSummary {
            kind: "cynefin",
            counts: [
                ast.statements.len(),
                ast.domains.len(),
                ast.domains.iter().map(|domain| domain.items.len()).sum(),
                ast.transitions.len(),
            ],
        },
        DiagramKind::Railroad(ast) => ParserSummary {
            kind: "railroad",
            counts: [ast.statements.len(), ast.rules.len(), 0, 0],
        },
        DiagramKind::Swimlanes(ast) => ParserSummary {
            kind: "swimlanes",
            counts: [
                ast.graph.statements.len(),
                ast.graph.subgraphs.len(),
                ast.graph.nodes.len(),
                ast.graph.edges.len(),
            ],
        },
    }
}

fn count_treemap_nodes(node: &TreemapNode) -> usize {
    1 + node.children.iter().map(count_treemap_nodes).sum::<usize>()
}

fn count_ishikawa_nodes(node: &IshikawaNode) -> usize {
    1 + node.causes.iter().map(count_ishikawa_nodes).sum::<usize>()
}

fn count_tree_view_nodes(node: &TreeViewNode) -> usize {
    1 + node
        .children
        .iter()
        .map(count_tree_view_nodes)
        .sum::<usize>()
}

fn count_mindmap_nodes(node: &MindmapNode) -> usize {
    1 + node.children.iter().map(count_mindmap_nodes).sum::<usize>()
}
