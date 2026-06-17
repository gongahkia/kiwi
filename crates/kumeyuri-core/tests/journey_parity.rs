use kumeyuri_core::{
    ast::DiagramKind,
    frame::StaticFrameRenderer,
    parser::{ParseErrorKind, Parser},
    text::{TextOutputBackend, TextOutputConfig},
};

const SECTION_ORDER_ACTORS: &str =
    include_str!("../../../tests/fuzz/journey-parity/section_order_actors.mmd");
const INIT_THEME_CONFIG: &str =
    include_str!("../../../tests/fuzz/journey-parity/init_theme_config.mmd");
const ZERO_SCORE: &str = include_str!("../../../tests/fuzz/journey-parity/zero_score.mmd");
const HIGH_SCORE: &str = include_str!("../../../tests/fuzz/journey-parity/high_score.mmd");

#[test]
fn journey_sections_tasks_and_actor_styles_keep_source_order() {
    let diagram = Parser::parse_diagram(SECTION_ORDER_ACTORS).unwrap();
    let DiagramKind::Journey(ast) = &diagram.kind else {
        panic!("expected journey");
    };
    let sections = ast
        .tasks
        .iter()
        .map(|task| task.section.as_ref().unwrap().text.as_str())
        .collect::<Vec<_>>();

    assert_eq!(sections, ["Discover", "Discover", "Decide"]);

    let output = render_text(&diagram);
    let discover = output.find("Discover").unwrap();
    let decide = output.find("Decide").unwrap();
    let buyer = output.find("# Buyer").unwrap();
    let support = output.find("+ Support").unwrap();
    let advisor = output.find("= Advisor").unwrap();

    assert!(discover < decide);
    assert!(buyer < support);
    assert!(support < advisor);
}

#[test]
fn journey_theme_config_fixture_is_accepted() {
    let diagram = Parser::parse_diagram(INIT_THEME_CONFIG).unwrap();
    let DiagramKind::Journey(ast) = &diagram.kind else {
        panic!("expected journey");
    };

    assert_eq!(diagram.directives.len(), 1);
    assert_eq!(ast.tasks.len(), 2);

    let output = render_text(&diagram);
    assert!(output.contains("# User"));
    assert!(output.contains("+ Agent"));
}

#[test]
fn journey_scores_must_be_between_one_and_five() {
    for source in [ZERO_SCORE, HIGH_SCORE] {
        let error = Parser::parse_diagram(source).unwrap_err();

        assert_eq!(error.kind, ParseErrorKind::ExpectedJourneyScore);
    }
}

fn render_text(diagram: &kumeyuri_core::ast::Diagram) -> String {
    let renderer = StaticFrameRenderer::default();
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });

    text.render_frame(&renderer.render_diagram(diagram))
}
