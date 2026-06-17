use kumeyuri_core::{
    ast::{DiagramKind, StateNodeKind},
    parser::{ParseErrorKind, Parser},
};

#[derive(Debug, Clone, Copy)]
struct StateParityFixture {
    name: &'static str,
    source: &'static str,
    expected: StateParityExpectation,
}

#[derive(Debug, Clone, Copy)]
enum StateParityExpectation {
    Parses,
    Rejects(ParseErrorKind),
}

const FIXTURES: &[StateParityFixture] = &[
    StateParityFixture {
        name: "entry_exit_descriptions",
        source: include_str!("../../../tests/fuzz/state-parity/entry_exit_descriptions.mmd"),
        expected: StateParityExpectation::Rejects(ParseErrorKind::UnknownStateStatement),
    },
    StateParityFixture {
        name: "concurrent_state",
        source: include_str!("../../../tests/fuzz/state-parity/concurrent_state.mmd"),
        expected: StateParityExpectation::Rejects(ParseErrorKind::UnknownStateStatement),
    },
    StateParityFixture {
        name: "history_state",
        source: include_str!("../../../tests/fuzz/state-parity/history_state.mmd"),
        expected: StateParityExpectation::Rejects(ParseErrorKind::ExpectedStateTransition),
    },
    StateParityFixture {
        name: "deep_history_state",
        source: include_str!("../../../tests/fuzz/state-parity/deep_history_state.mmd"),
        expected: StateParityExpectation::Rejects(ParseErrorKind::ExpectedStateTransition),
    },
    StateParityFixture {
        name: "composite_state_note",
        source: include_str!("../../../tests/fuzz/state-parity/composite_state_note.mmd"),
        expected: StateParityExpectation::Rejects(ParseErrorKind::UnknownStateStatement),
    },
    StateParityFixture {
        name: "choice_fork_join",
        source: include_str!("../../../tests/fuzz/state-parity/choice_fork_join.mmd"),
        expected: StateParityExpectation::Parses,
    },
    StateParityFixture {
        name: "class_styling",
        source: include_str!("../../../tests/fuzz/state-parity/class_styling.mmd"),
        expected: StateParityExpectation::Rejects(ParseErrorKind::UnknownStateStatement),
    },
];

#[test]
fn state_parity_fixtures_have_expected_parser_status() {
    for fixture in FIXTURES {
        let parsed = Parser::parse_diagram(fixture.source);

        match fixture.expected {
            StateParityExpectation::Parses => {
                let diagram = parsed.unwrap_or_else(|error| {
                    panic!(
                        "{} should parse, got {:?} at {}..{}",
                        fixture.name, error.kind, error.span.start, error.span.end,
                    )
                });
                assert!(
                    matches!(diagram.kind, DiagramKind::State(_)),
                    "{}",
                    fixture.name
                );
            }
            StateParityExpectation::Rejects(kind) => {
                let error = parsed.unwrap_err();

                assert_eq!(error.kind, kind, "{}", fixture.name);
            }
        }
    }
}

#[test]
fn choice_fork_join_fixture_preserves_state_kinds() {
    let ast = parse_state_fixture("choice_fork_join");
    let kinds = ["if_state", "fork_state", "join_state"].map(|id| {
        ast.states
            .iter()
            .find(|state| state.id.value == id)
            .unwrap_or_else(|| panic!("missing state {id}"))
            .kind
    });

    assert_eq!(
        kinds,
        [
            StateNodeKind::Choice,
            StateNodeKind::Fork,
            StateNodeKind::Join
        ],
    );
}

fn parse_state_fixture(name: &str) -> Box<kumeyuri_core::ast::StateAst> {
    let fixture = FIXTURES
        .iter()
        .find(|fixture| fixture.name == name)
        .unwrap_or_else(|| panic!("missing fixture {name}"));
    let diagram = Parser::parse_diagram(fixture.source).unwrap();
    let DiagramKind::State(ast) = diagram.kind else {
        panic!("expected state diagram");
    };
    ast
}
