use kumeyuri_core::{
    ast::{DiagramKind, ErCardinality},
    parser::{ParseErrorKind, Parser},
};

#[derive(Debug, Clone, Copy)]
struct ErParityFixture {
    name: &'static str,
    source: &'static str,
    expected: ErParityExpectation,
}

#[derive(Debug, Clone, Copy)]
enum ErParityExpectation {
    Parses,
    Rejects(ParseErrorKind),
}

const FIXTURES: &[ErParityFixture] = &[
    ErParityFixture {
        name: "quoted_entity",
        source: include_str!("../../../tests/fuzz/er-parity/quoted_entity.mmd"),
        expected: ErParityExpectation::Rejects(ParseErrorKind::ExpectedErRelationship),
    },
    ErParityFixture {
        name: "quoted_relationship_label",
        source: include_str!("../../../tests/fuzz/er-parity/quoted_relationship_label.mmd"),
        expected: ErParityExpectation::Parses,
    },
    ErParityFixture {
        name: "comments",
        source: include_str!("../../../tests/fuzz/er-parity/comments.mmd"),
        expected: ErParityExpectation::Parses,
    },
    ErParityFixture {
        name: "entity_aliases",
        source: include_str!("../../../tests/fuzz/er-parity/entity_aliases.mmd"),
        expected: ErParityExpectation::Rejects(ParseErrorKind::UnknownErStatement),
    },
    ErParityFixture {
        name: "attribute_comments",
        source: include_str!("../../../tests/fuzz/er-parity/attribute_comments.mmd"),
        expected: ErParityExpectation::Parses,
    },
    ErParityFixture {
        name: "attribute_markers",
        source: include_str!("../../../tests/fuzz/er-parity/attribute_markers.mmd"),
        expected: ErParityExpectation::Parses,
    },
    ErParityFixture {
        name: "cardinality_variants",
        source: include_str!("../../../tests/fuzz/er-parity/cardinality_variants.mmd"),
        expected: ErParityExpectation::Parses,
    },
];

#[test]
fn er_parity_fixtures_have_expected_parser_status() {
    for fixture in FIXTURES {
        let parsed = Parser::parse_diagram(fixture.source);

        match fixture.expected {
            ErParityExpectation::Parses => {
                let diagram = parsed.unwrap_or_else(|error| {
                    panic!(
                        "{} should parse, got {:?} at {}..{}",
                        fixture.name, error.kind, error.span.start, error.span.end,
                    )
                });
                assert!(
                    matches!(diagram.kind, DiagramKind::Er(_)),
                    "{}",
                    fixture.name
                );
            }
            ErParityExpectation::Rejects(kind) => {
                let error = parsed.unwrap_err();

                assert_eq!(error.kind, kind, "{}", fixture.name);
            }
        }
    }
}

#[test]
fn quoted_relationship_label_fixture_strips_quotes() {
    let ast = parse_er_fixture("quoted_relationship_label");

    assert_eq!(ast.relationships[0].label.as_ref().unwrap().text, "driver");
}

#[test]
fn attribute_comment_fixture_keeps_key_and_ignores_comment_gap() {
    let ast = parse_er_fixture("attribute_comments");
    let person = ast
        .entities
        .iter()
        .find(|entity| entity.id.value == "PERSON")
        .expect("missing entity");

    assert_eq!(person.attributes[0].name.value, "driversLicense");
    assert_eq!(person.attributes[0].key.as_ref().unwrap().value, "PK");
}

#[test]
fn attribute_markers_fixture_preserves_type_and_key_tokens() {
    let ast = parse_er_fixture("attribute_markers");
    let car = ast
        .entities
        .iter()
        .find(|entity| entity.id.value == "CAR")
        .expect("missing entity");

    assert_eq!(car.attributes[0].ty.value, "string[]");
    assert_eq!(car.attributes[1].ty.value, "string?");
    assert_eq!(car.attributes[2].name.value, "*id");
    assert_eq!(car.attributes[3].key.as_ref().unwrap().value, "PK,");
}

#[test]
fn cardinality_variants_fixture_preserves_each_marker_kind() {
    let ast = parse_er_fixture("cardinality_variants");
    let pairs = ast
        .relationships
        .iter()
        .map(|relationship| {
            (
                relationship.start_cardinality,
                relationship.end_cardinality,
                relationship.identifying,
            )
        })
        .collect::<Vec<_>>();

    assert_eq!(
        pairs,
        [
            (ErCardinality::One, ErCardinality::One, true),
            (ErCardinality::ZeroOrOne, ErCardinality::ZeroOrOne, true,),
            (ErCardinality::OneOrMany, ErCardinality::OneOrMany, true,),
            (ErCardinality::ZeroOrMany, ErCardinality::ZeroOrMany, true,),
            (ErCardinality::ZeroOrMany, ErCardinality::OneOrMany, false),
        ],
    );
}

fn parse_er_fixture(name: &str) -> Box<kumeyuri_core::ast::ErAst> {
    let fixture = FIXTURES
        .iter()
        .find(|fixture| fixture.name == name)
        .unwrap_or_else(|| panic!("missing fixture {name}"));
    let diagram = Parser::parse_diagram(fixture.source).unwrap();
    let DiagramKind::Er(ast) = diagram.kind else {
        panic!("expected ER diagram");
    };
    ast
}
