use kumeyuri_core::{
    ast::{
        DiagramKind, RequirementAst, RequirementKind, RequirementRelationshipKind, RequirementRisk,
        RequirementStatement, RequirementVerifyMethod,
    },
    parser::{ParseErrorKind, Parser},
};

const ALL_KINDS_RELATIONSHIPS: &str =
    include_str!("../../../tests/fuzz/requirement-parity/all_kinds_relationships.mmd");
const STYLES_CLASSES: &str =
    include_str!("../../../tests/fuzz/requirement-parity/styles_classes.mmd");
const INVALID_VERIFY_METHOD: &str =
    include_str!("../../../tests/fuzz/requirement-parity/invalid_verify_method.mmd");
const INVALID_FIELD: &str =
    include_str!("../../../tests/fuzz/requirement-parity/invalid_field.mmd");
const INVALID_ELEMENT_FIELD: &str =
    include_str!("../../../tests/fuzz/requirement-parity/invalid_element_field.mmd");
const INVALID_RELATIONSHIP: &str =
    include_str!("../../../tests/fuzz/requirement-parity/invalid_relationship.mmd");

#[test]
fn requirement_all_kinds_risks_methods_and_relationships_parse() {
    let ast = parse_requirement(ALL_KINDS_RELATIONSHIPS);

    assert_eq!(
        ast.requirements
            .iter()
            .map(|node| node.kind.value)
            .collect::<Vec<_>>(),
        [
            RequirementKind::Requirement,
            RequirementKind::Functional,
            RequirementKind::Interface,
            RequirementKind::Performance,
            RequirementKind::Physical,
            RequirementKind::DesignConstraint,
        ],
    );
    assert_eq!(
        ast.requirements
            .iter()
            .map(|node| node.risk.unwrap().value)
            .collect::<Vec<_>>(),
        [
            RequirementRisk::Low,
            RequirementRisk::Medium,
            RequirementRisk::High,
            RequirementRisk::Medium,
            RequirementRisk::Low,
            RequirementRisk::High,
        ],
    );
    assert_eq!(
        ast.requirements
            .iter()
            .map(|node| node.verify_method.unwrap().value)
            .collect::<Vec<_>>(),
        [
            RequirementVerifyMethod::Analysis,
            RequirementVerifyMethod::Inspection,
            RequirementVerifyMethod::Test,
            RequirementVerifyMethod::Demonstration,
            RequirementVerifyMethod::Analysis,
            RequirementVerifyMethod::Inspection,
        ],
    );
    assert_eq!(
        ast.relationships
            .iter()
            .map(|relationship| relationship.kind.value)
            .collect::<Vec<_>>(),
        [
            RequirementRelationshipKind::Contains,
            RequirementRelationshipKind::Copies,
            RequirementRelationshipKind::Derives,
            RequirementRelationshipKind::Refines,
            RequirementRelationshipKind::Verifies,
            RequirementRelationshipKind::Satisfies,
            RequirementRelationshipKind::Traces,
        ],
    );
    assert_eq!(ast.elements.len(), 2);
    assert_eq!(ast.elements[0].ty.as_ref().unwrap().text, "word doc");
    assert_eq!(
        ast.elements[1].doc_ref.as_ref().unwrap().text,
        "github.com/tests"
    );
}

#[test]
fn requirement_styles_and_classes_are_preserved_semantically() {
    let ast = parse_requirement(STYLES_CLASSES);
    let requirement = &ast.requirements[0];
    let element = &ast.elements[0];
    let class_applies = ast
        .statements
        .iter()
        .filter(|statement| matches!(statement, RequirementStatement::ClassApply(_)))
        .count();

    assert_eq!(
        requirement
            .classes
            .iter()
            .map(|class| class.value.as_str())
            .collect::<Vec<_>>(),
        ["urgent", "large"],
    );
    assert_eq!(
        element
            .classes
            .iter()
            .map(|class| class.value.as_str())
            .collect::<Vec<_>>(),
        ["external"],
    );
    assert_eq!(ast.classes.len(), 1);
    assert_eq!(ast.styles.len(), 1);
    assert_eq!(class_applies, 2);
}

#[test]
fn requirement_invalid_fixtures_reject_specific_errors() {
    for (source, kind) in [
        (
            INVALID_VERIFY_METHOD,
            ParseErrorKind::ExpectedRequirementVerifyMethod,
        ),
        (INVALID_FIELD, ParseErrorKind::ExpectedRequirementField),
        (
            INVALID_ELEMENT_FIELD,
            ParseErrorKind::ExpectedRequirementField,
        ),
        (
            INVALID_RELATIONSHIP,
            ParseErrorKind::ExpectedRequirementRelationship,
        ),
    ] {
        let error = Parser::parse_diagram(source).unwrap_err();

        assert_eq!(error.kind, kind);
    }
}

fn parse_requirement(source: &str) -> RequirementAst {
    let diagram = Parser::parse_diagram(source).unwrap();
    let DiagramKind::Requirement(ast) = diagram.kind else {
        panic!("expected requirement");
    };
    *ast
}
