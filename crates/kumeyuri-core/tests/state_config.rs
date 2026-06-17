use kumeyuri_core::parser::{ParseErrorKind, Parser};

const REJECTED_CONFIG_FIXTURES: &[(&str, &str)] = &[
    (
        "frontmatter_layout",
        include_str!("../../../tests/fuzz/state-config/frontmatter_layout.mmd"),
    ),
    (
        "init_layout",
        include_str!("../../../tests/fuzz/state-config/init_layout.mmd"),
    ),
    (
        "init_look",
        include_str!("../../../tests/fuzz/state-config/init_look.mmd"),
    ),
];

#[test]
fn state_mermaid_layout_and_look_config_fixtures_are_explicitly_rejected() {
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
fn empty_state_init_directive_stays_forward_compatible() {
    let diagram = Parser::parse_diagram("%%{ init: {} }%%\nstateDiagram-v2\n[*] --> A").unwrap();

    assert_eq!(diagram.directives.len(), 1);
}
