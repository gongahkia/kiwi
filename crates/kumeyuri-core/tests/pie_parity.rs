use kumeyuri_core::{
    ast::{DiagramKind, PieLegendPosition},
    frame::StaticFrameRenderer,
    parser::{ParseErrorKind, Parser},
    text::{TextOutputBackend, TextOutputConfig},
};

const LEGEND_ORDER: &str =
    include_str!("../../../tests/fuzz/pie-parity/legend_order_show_data.mmd");
const INIT_CONFIG_THEME: &str =
    include_str!("../../../tests/fuzz/pie-parity/init_config_theme.mmd");
const ZERO_VALUE: &str = include_str!("../../../tests/fuzz/pie-parity/zero_value.mmd");
const NEGATIVE_VALUE: &str = include_str!("../../../tests/fuzz/pie-parity/negative_value.mmd");

#[test]
fn pie_legend_keeps_slice_order_and_show_data_values() {
    let diagram = Parser::parse_diagram(LEGEND_ORDER).unwrap();
    let DiagramKind::Pie(ast) = &diagram.kind else {
        panic!("expected pie");
    };
    let labels = ast
        .slices
        .iter()
        .map(|slice| slice.label.text.as_str())
        .collect::<Vec<_>>();

    assert_eq!(labels, ["First", "Second", "Third"]);

    let output = render_text(&diagram);
    let first = output.find("# First [10]").unwrap();
    let second = output.find("+ Second [20]").unwrap();
    let third = output.find("= Third [30]").unwrap();

    assert!(first < second);
    assert!(second < third);
}

#[test]
fn pie_init_config_reads_supported_pie_fields_and_ignores_theme_fields() {
    let diagram = Parser::parse_diagram(INIT_CONFIG_THEME).unwrap();
    let DiagramKind::Pie(ast) = &diagram.kind else {
        panic!("expected pie");
    };

    assert_eq!(ast.config.text_position_milli, 500);
    assert_eq!(ast.config.legend_position, PieLegendPosition::Bottom);

    let output = render_text(&diagram);
    assert!(output.contains("# Alpha [4]"));
    assert!(output.contains("+ Beta [6]"));
    assert!(output.contains("40%"));
    assert!(output.contains("60%"));
}

#[test]
fn pie_zero_and_negative_values_are_rejected() {
    for source in [ZERO_VALUE, NEGATIVE_VALUE] {
        let error = Parser::parse_diagram(source).unwrap_err();

        assert_eq!(error.kind, ParseErrorKind::ExpectedPieValue);
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
