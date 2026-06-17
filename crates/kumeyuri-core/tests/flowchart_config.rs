use kumeyuri_core::parser::{ParseErrorKind, Parser};

const REJECTED_CONFIG_FIXTURES: &[(&str, &str)] = &[
    (
        "frontmatter_layout",
        include_str!("../../../tests/fuzz/flowchart-config/frontmatter_layout.mmd"),
    ),
    (
        "init_layout",
        include_str!("../../../tests/fuzz/flowchart-config/init_layout.mmd"),
    ),
    (
        "init_look",
        include_str!("../../../tests/fuzz/flowchart-config/init_look.mmd"),
    ),
    (
        "init_theme",
        include_str!("../../../tests/fuzz/flowchart-config/init_theme.mmd"),
    ),
    (
        "init_theme_variables",
        include_str!("../../../tests/fuzz/flowchart-config/init_theme_variables.mmd"),
    ),
    (
        "init_curve",
        include_str!("../../../tests/fuzz/flowchart-config/init_curve.mmd"),
    ),
    (
        "init_elk",
        include_str!("../../../tests/fuzz/flowchart-config/init_elk.mmd"),
    ),
];

#[test]
fn flowchart_mermaid_config_fixtures_are_explicitly_rejected() {
    for (name, source) in REJECTED_CONFIG_FIXTURES {
        let error = Parser::parse_diagram(source).unwrap_err();

        assert_eq!(
            error.kind,
            ParseErrorKind::UnsupportedMermaidConfig,
            "{name}"
        );
    }
}

#[test]
fn empty_init_directive_stays_forward_compatible() {
    let diagram = Parser::parse_diagram("%%{ init: {} }%%\ngraph TD\nA --> B").unwrap();

    assert_eq!(diagram.directives.len(), 1);
}
