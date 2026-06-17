use kumeyuri_core::{
    ast::{ClassMemberKind, DiagramKind},
    parser::{ParseErrorKind, Parser},
};

#[derive(Debug, Clone, Copy)]
struct ClassParityFixture {
    name: &'static str,
    source: &'static str,
    expected: ClassParityExpectation,
}

#[derive(Debug, Clone, Copy)]
enum ClassParityExpectation {
    Parses,
    Rejects(ParseErrorKind),
}

const FIXTURES: &[ClassParityFixture] = &[
    ClassParityFixture {
        name: "namespace",
        source: include_str!("../../../tests/fuzz/class-parity/namespace.mmd"),
        expected: ClassParityExpectation::Rejects(ParseErrorKind::UnknownClassStatement),
    },
    ClassParityFixture {
        name: "generic_class",
        source: include_str!("../../../tests/fuzz/class-parity/generic_class.mmd"),
        expected: ClassParityExpectation::Rejects(ParseErrorKind::ExpectedClassName),
    },
    ClassParityFixture {
        name: "generic_members",
        source: include_str!("../../../tests/fuzz/class-parity/generic_members.mmd"),
        expected: ClassParityExpectation::Parses,
    },
    ClassParityFixture {
        name: "nested_annotations",
        source: include_str!("../../../tests/fuzz/class-parity/nested_annotations.mmd"),
        expected: ClassParityExpectation::Parses,
    },
    ClassParityFixture {
        name: "callback",
        source: include_str!("../../../tests/fuzz/class-parity/callback.mmd"),
        expected: ClassParityExpectation::Rejects(ParseErrorKind::UnknownClassStatement),
    },
    ClassParityFixture {
        name: "link",
        source: include_str!("../../../tests/fuzz/class-parity/link.mmd"),
        expected: ClassParityExpectation::Rejects(ParseErrorKind::ExpectedClassName),
    },
    ClassParityFixture {
        name: "css_class_styling",
        source: include_str!("../../../tests/fuzz/class-parity/css_class_styling.mmd"),
        expected: ClassParityExpectation::Rejects(ParseErrorKind::ExpectedClassName),
    },
    ClassParityFixture {
        name: "two_way_relation",
        source: include_str!("../../../tests/fuzz/class-parity/two_way_relation.mmd"),
        expected: ClassParityExpectation::Rejects(ParseErrorKind::ExpectedClassRelationship),
    },
    ClassParityFixture {
        name: "lollipop_interface",
        source: include_str!("../../../tests/fuzz/class-parity/lollipop_interface.mmd"),
        expected: ClassParityExpectation::Rejects(ParseErrorKind::ExpectedClassRelationship),
    },
    ClassParityFixture {
        name: "method_classifiers",
        source: include_str!("../../../tests/fuzz/class-parity/method_classifiers.mmd"),
        expected: ClassParityExpectation::Parses,
    },
    ClassParityFixture {
        name: "field_classifier",
        source: include_str!("../../../tests/fuzz/class-parity/field_classifier.mmd"),
        expected: ClassParityExpectation::Rejects(ParseErrorKind::ExpectedClassMember),
    },
];

#[test]
fn class_parity_fixtures_have_expected_parser_status() {
    for fixture in FIXTURES {
        let parsed = Parser::parse_diagram(fixture.source);

        match fixture.expected {
            ClassParityExpectation::Parses => {
                let diagram = parsed.unwrap_or_else(|error| {
                    panic!(
                        "{} should parse, got {:?} at {}..{}",
                        fixture.name, error.kind, error.span.start, error.span.end,
                    )
                });
                assert!(
                    matches!(diagram.kind, DiagramKind::Class(_)),
                    "{}",
                    fixture.name
                );
            }
            ClassParityExpectation::Rejects(kind) => {
                let error = parsed.unwrap_err();

                assert_eq!(error.kind, kind, "{}", fixture.name);
            }
        }
    }
}

#[test]
fn generic_members_fixture_preserves_generic_type_labels() {
    let ast = parse_class_fixture("generic_members");
    let class = ast
        .classes
        .iter()
        .find(|class| class.id.value == "Square")
        .expect("missing class");

    assert_eq!(class.members[0].name.value, "position");
    assert_eq!(class.members[0].ty.as_ref().unwrap().text, "List~int~");
    assert_eq!(class.members[1].kind, ClassMemberKind::Method);
    assert_eq!(class.members[1].ty.as_ref().unwrap().text, "List~int~");
}

#[test]
fn nested_annotations_fixture_preserves_annotation_text() {
    let ast = parse_class_fixture("nested_annotations");
    let class = ast
        .classes
        .iter()
        .find(|class| class.id.value == "Shape")
        .expect("missing class");

    assert_eq!(class.annotations[0].text, "<<interface>>");
}

#[test]
fn method_classifiers_fixture_preserves_classifier_suffixes_as_type_text() {
    let ast = parse_class_fixture("method_classifiers");
    let class = ast
        .classes
        .iter()
        .find(|class| class.id.value == "Shape")
        .expect("missing class");

    assert_eq!(class.members[0].kind, ClassMemberKind::Method);
    assert_eq!(class.members[0].ty.as_ref().unwrap().text, "*");
    assert_eq!(class.members[1].ty.as_ref().unwrap().text, "String$");
}

fn parse_class_fixture(name: &str) -> Box<kumeyuri_core::ast::ClassAst> {
    let fixture = FIXTURES
        .iter()
        .find(|fixture| fixture.name == name)
        .unwrap_or_else(|| panic!("missing fixture {name}"));
    let diagram = Parser::parse_diagram(fixture.source).unwrap();
    let DiagramKind::Class(ast) = diagram.kind else {
        panic!("expected class diagram");
    };
    ast
}
