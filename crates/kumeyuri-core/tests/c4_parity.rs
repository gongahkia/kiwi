use kumeyuri_core::{
    ast::{
        C4Ast, C4BoundaryKind, C4DiagramType, C4ElementKind, C4RelationshipKind, C4Statement,
        DiagramKind,
    },
    parser::{ParseErrorKind, Parser},
};

const CONTEXT_ROOT: &str = include_str!("../../../tests/fuzz/c4-parity/context_root.mmd");
const CONTAINER_ROOT: &str = include_str!("../../../tests/fuzz/c4-parity/container_root.mmd");
const COMPONENT_ROOT: &str = include_str!("../../../tests/fuzz/c4-parity/component_root.mmd");
const DYNAMIC_ROOT: &str = include_str!("../../../tests/fuzz/c4-parity/dynamic_root.mmd");
const DEPLOYMENT_ROOT: &str = include_str!("../../../tests/fuzz/c4-parity/deployment_root.mmd");
const BOUNDARY_NESTING: &str = include_str!("../../../tests/fuzz/c4-parity/boundary_nesting.mmd");
const RELATIONSHIP_VARIANTS: &str =
    include_str!("../../../tests/fuzz/c4-parity/relationship_variants.mmd");
const TAGS_LEGEND_SPRITE_ARGS: &str =
    include_str!("../../../tests/fuzz/c4-parity/tags_legend_sprite_args.mmd");

const UNSUPPORTED_MACROS: &[(&str, &str)] = &[
    (
        "add_element_tag",
        include_str!("../../../tests/fuzz/c4-parity/unsupported_add_element_tag.mmd"),
    ),
    (
        "add_rel_tag",
        include_str!("../../../tests/fuzz/c4-parity/unsupported_add_rel_tag.mmd"),
    ),
    (
        "sprite_macro",
        include_str!("../../../tests/fuzz/c4-parity/unsupported_sprite_macro.mmd"),
    ),
    (
        "shape_macro",
        include_str!("../../../tests/fuzz/c4-parity/unsupported_shape_macro.mmd"),
    ),
];

#[test]
fn c4_root_variants_parse() {
    for (source, expected) in [
        (CONTEXT_ROOT, C4DiagramType::Context),
        (CONTAINER_ROOT, C4DiagramType::Container),
        (COMPONENT_ROOT, C4DiagramType::Component),
        (DYNAMIC_ROOT, C4DiagramType::Dynamic),
        (DEPLOYMENT_ROOT, C4DiagramType::Deployment),
    ] {
        let ast = parse_c4(source);

        assert_eq!(ast.header.diagram_type.value, expected);
        assert!(!ast.elements.is_empty() || !ast.boundaries.is_empty());
    }
}

#[test]
fn c4_boundary_nesting_records_parent_aliases() {
    let ast = parse_c4(BOUNDARY_NESTING);

    assert_eq!(
        boundary(&ast, "enterprise").kind.value,
        C4BoundaryKind::Enterprise
    );
    assert_eq!(
        boundary(&ast, "system")
            .parent
            .as_ref()
            .map(|parent| parent.value.as_str()),
        Some("enterprise"),
    );
    assert_eq!(
        boundary(&ast, "web_layer")
            .parent
            .as_ref()
            .map(|parent| parent.value.as_str()),
        Some("system"),
    );
    let web = ast
        .elements
        .iter()
        .find(|element| element.alias.value == "web")
        .unwrap();
    assert_eq!(web.kind.value, C4ElementKind::Container);
    assert_eq!(
        web.parent.as_ref().map(|parent| parent.value.as_str()),
        Some("web_layer"),
    );
}

#[test]
fn c4_relationship_variants_and_indexes_parse() {
    let ast = parse_c4(RELATIONSHIP_VARIANTS);

    assert_eq!(
        ast.relationships
            .iter()
            .map(|relationship| relationship.kind.value)
            .collect::<Vec<_>>(),
        [
            C4RelationshipKind::Directed,
            C4RelationshipKind::Bidirectional,
            C4RelationshipKind::Up,
            C4RelationshipKind::Down,
            C4RelationshipKind::Left,
            C4RelationshipKind::Right,
            C4RelationshipKind::Back,
            C4RelationshipKind::Indexed,
            C4RelationshipKind::Bidirectional,
        ],
    );
    assert_eq!(
        ast.relationships
            .iter()
            .filter_map(|relationship| relationship.index.as_ref())
            .map(|index| index.value.as_str())
            .collect::<Vec<_>>(),
        ["1", "2"],
    );
}

#[test]
fn c4_tags_legend_and_sprite_args_preserve_supported_semantics() {
    let ast = parse_c4(TAGS_LEGEND_SPRITE_ARGS);
    let layout_calls = ast
        .statements
        .iter()
        .filter_map(|statement| match statement {
            C4Statement::Layout(layout) => Some(layout.name.value.as_str()),
            _ => None,
        })
        .collect::<Vec<_>>();

    assert_eq!(
        layout_calls,
        ["LAYOUT_WITH_LEGEND", "SHOW_LEGEND", "UpdateLayoutConfig"],
    );
    assert_eq!(
        ast.elements[0].description.as_ref().unwrap().text,
        "Uses admin UI"
    );
    assert_eq!(ast.elements[1].technology.as_ref().unwrap().text, "Rust");
    assert_eq!(
        ast.relationships[0].technology.as_ref().unwrap().text,
        "HTTPS",
    );
}

#[test]
fn c4_unsupported_macros_reject_unknown_statement() {
    for (name, source) in UNSUPPORTED_MACROS {
        let error = Parser::parse_diagram(source).unwrap_err();

        assert_eq!(error.kind, ParseErrorKind::UnknownC4Statement, "{name}");
    }
}

fn parse_c4(source: &str) -> Box<C4Ast> {
    let diagram = Parser::parse_diagram(source).unwrap();
    let DiagramKind::C4(ast) = diagram.kind else {
        panic!("expected C4");
    };
    ast
}

fn boundary<'a>(ast: &'a C4Ast, alias: &str) -> &'a kumeyuri_core::ast::C4Boundary {
    ast.boundaries
        .iter()
        .find(|boundary| boundary.alias.value == alias)
        .unwrap()
}
