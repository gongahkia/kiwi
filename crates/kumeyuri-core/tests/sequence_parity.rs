use kumeyuri_core::{
    ast::{DiagramKind, SequenceNotePlacement, SequenceParticipantKind, SequenceStatement},
    parser::{ParseErrorKind, Parser},
};

#[derive(Debug, Clone, Copy)]
struct SequenceParityFixture {
    name: &'static str,
    source: &'static str,
    expected: SequenceParityExpectation,
}

#[derive(Debug, Clone, Copy)]
enum SequenceParityExpectation {
    Parses,
    Rejects(ParseErrorKind),
}

const FIXTURES: &[SequenceParityFixture] = &[
    SequenceParityFixture {
        name: "actor_link",
        source: include_str!("../../../tests/fuzz/sequence-parity/actor_link.mmd"),
        expected: SequenceParityExpectation::Rejects(ParseErrorKind::UnknownSequenceStatement),
    },
    SequenceParityFixture {
        name: "actor_links_json",
        source: include_str!("../../../tests/fuzz/sequence-parity/actor_links_json.mmd"),
        expected: SequenceParityExpectation::Rejects(ParseErrorKind::UnknownSequenceStatement),
    },
    SequenceParityFixture {
        name: "participant_properties",
        source: include_str!("../../../tests/fuzz/sequence-parity/participant_properties.mmd"),
        expected: SequenceParityExpectation::Rejects(ParseErrorKind::ExpectedSequenceParticipant),
    },
    SequenceParityFixture {
        name: "participant_ordering",
        source: include_str!("../../../tests/fuzz/sequence-parity/participant_ordering.mmd"),
        expected: SequenceParityExpectation::Parses,
    },
    SequenceParityFixture {
        name: "multi_line_note",
        source: include_str!("../../../tests/fuzz/sequence-parity/multi_line_note.mmd"),
        expected: SequenceParityExpectation::Parses,
    },
    SequenceParityFixture {
        name: "message_empty_label",
        source: include_str!("../../../tests/fuzz/sequence-parity/message_empty_label.mmd"),
        expected: SequenceParityExpectation::Parses,
    },
    SequenceParityFixture {
        name: "message_without_colon",
        source: include_str!("../../../tests/fuzz/sequence-parity/message_without_colon.mmd"),
        expected: SequenceParityExpectation::Rejects(ParseErrorKind::ExpectedSequenceMessage),
    },
];

#[test]
fn sequence_parity_fixtures_have_expected_parser_status() {
    for fixture in FIXTURES {
        let parsed = Parser::parse_diagram(fixture.source);

        match fixture.expected {
            SequenceParityExpectation::Parses => {
                let diagram = parsed.unwrap_or_else(|error| {
                    panic!(
                        "{} should parse, got {:?} at {}..{}",
                        fixture.name, error.kind, error.span.start, error.span.end,
                    )
                });
                assert!(
                    matches!(diagram.kind, DiagramKind::Sequence(_)),
                    "{}",
                    fixture.name,
                );
            }
            SequenceParityExpectation::Rejects(kind) => {
                let error = parsed.unwrap_err();

                assert_eq!(error.kind, kind, "{}", fixture.name);
            }
        }
    }
}

#[test]
fn participant_ordering_fixture_preserves_declaration_order() {
    let ast = parse_sequence_fixture("participant_ordering");

    assert_eq!(
        ast.participants
            .iter()
            .map(|participant| participant.id.value.as_str())
            .collect::<Vec<_>>(),
        ["Bob", "Alice"],
    );
    assert_eq!(
        ast.participants[0].kind,
        SequenceParticipantKind::Participant
    );
    assert_eq!(
        ast.participants[1].kind,
        SequenceParticipantKind::Participant
    );
}

#[test]
fn multi_line_note_fixture_preserves_html_line_breaks() {
    let ast = parse_sequence_fixture("multi_line_note");
    let note = ast
        .statements
        .iter()
        .find_map(|statement| match statement {
            SequenceStatement::Note(note) => Some(note),
            _ => None,
        })
        .expect("fixture has note");

    assert_eq!(note.placement, SequenceNotePlacement::Over);
    assert_eq!(
        note.label.text,
        "A typical interaction<br/>But now in two lines"
    );
}

#[test]
fn message_empty_label_fixture_preserves_unlabeled_messages() {
    let ast = parse_sequence_fixture("message_empty_label");
    let labels = ast
        .statements
        .iter()
        .filter_map(|statement| match statement {
            SequenceStatement::Message(message) => Some(message.label.as_ref()),
            _ => None,
        })
        .collect::<Vec<_>>();

    assert_eq!(labels, [None, None]);
}

fn parse_sequence_fixture(name: &str) -> Box<kumeyuri_core::ast::SequenceAst> {
    let fixture = FIXTURES
        .iter()
        .find(|fixture| fixture.name == name)
        .unwrap_or_else(|| panic!("missing fixture {name}"));
    let diagram = Parser::parse_diagram(fixture.source).unwrap();
    let DiagramKind::Sequence(ast) = diagram.kind else {
        panic!("expected sequence diagram");
    };
    ast
}
