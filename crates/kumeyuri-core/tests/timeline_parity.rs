use kumeyuri_core::{
    ast::{DiagramKind, TimelineStatement},
    parser::Parser,
};

const MULTI_EVENT_ORDER: &str =
    include_str!("../../../tests/fuzz/timeline-parity/multi_event_order.mmd");
const EMPTY_SECTION: &str = include_str!("../../../tests/fuzz/timeline-parity/empty_section.mmd");
const LONG_LABELS_CONFIG: &str =
    include_str!("../../../tests/fuzz/timeline-parity/long_labels_config.mmd");

#[test]
fn timeline_multi_event_periods_keep_source_order() {
    let ast = parse_timeline(MULTI_EVENT_ORDER);

    assert_eq!(ast.periods[0].label.text, "2024 Q1");
    assert_eq!(
        ast.periods[0]
            .events
            .iter()
            .map(|event| event.text.as_str())
            .collect::<Vec<_>>(),
        ["Design", "Prototype", "Validate"],
    );
    assert_eq!(ast.periods[1].label.text, "2024 Q2");
    assert_eq!(ast.periods[2].section.as_ref().unwrap().text, "Beta");
}

#[test]
fn timeline_empty_sections_are_preserved_as_statements() {
    let ast = parse_timeline(EMPTY_SECTION);
    let sections = ast
        .statements
        .iter()
        .filter_map(|statement| match statement {
            TimelineStatement::Section(section) => Some(section.text.as_str()),
            _ => None,
        })
        .collect::<Vec<_>>();

    assert_eq!(sections, ["Planning", "Delivery"]);
    assert_eq!(ast.periods.len(), 1);
    assert_eq!(ast.periods[0].section.as_ref().unwrap().text, "Delivery");
}

#[test]
fn timeline_long_labels_and_theme_config_fixture_parse() {
    let diagram = Parser::parse_diagram(LONG_LABELS_CONFIG).unwrap();
    let DiagramKind::Timeline(ast) = &diagram.kind else {
        panic!("expected timeline");
    };

    assert_eq!(diagram.directives.len(), 1);
    assert_eq!(
        ast.title.as_ref().unwrap().text,
        "A deliberately long timeline title that should remain parseable"
    );
    assert_eq!(
        ast.periods[0].section.as_ref().unwrap().text,
        "A long section name <br> with explicit line break"
    );
    assert_eq!(ast.periods[0].events.len(), 2);
}

fn parse_timeline(source: &str) -> Box<kumeyuri_core::ast::TimelineAst> {
    let diagram = Parser::parse_diagram(source).unwrap();
    let DiagramKind::Timeline(ast) = diagram.kind else {
        panic!("expected timeline");
    };
    ast
}
