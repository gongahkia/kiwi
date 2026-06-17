use kumeyuri_core::{
    ast::{DiagramKind, LabelKind, MindmapAst, MindmapNode, MindmapShape},
    frame::StaticFrameRenderer,
    layout::MindmapLayoutEngine,
    parser::Parser,
    text::{TextOutputBackend, TextOutputConfig},
};

const ALL_SHAPES_ICONS_CLASSES: &str =
    include_str!("../../../tests/fuzz/mindmap-parity/all_shapes_icons_classes.mmd");
const MARKDOWN_LABELS: &str =
    include_str!("../../../tests/fuzz/mindmap-parity/markdown_labels.mmd");
const INDENTATION_EDGES: &str =
    include_str!("../../../tests/fuzz/mindmap-parity/indentation_edges.mmd");
const DEEP_TREE: &str = include_str!("../../../tests/fuzz/mindmap-parity/deep_tree.mmd");

#[test]
fn mindmap_shape_icon_and_class_fixture_preserves_semantics() {
    let ast = parse_mindmap(ALL_SHAPES_ICONS_CLASSES);
    let root = &ast.roots[0];

    assert_eq!(root.shape, MindmapShape::Circle);
    assert_eq!(node(root, "Square").shape, MindmapShape::Square);
    assert_eq!(node(root, "Rounded").shape, MindmapShape::Rounded);
    assert_eq!(node(root, "Circle").shape, MindmapShape::Circle);
    assert_eq!(node(root, "Bang").shape, MindmapShape::Bang);
    assert_eq!(node(root, "Cloud").shape, MindmapShape::Cloud);
    assert_eq!(node(root, "Hexagon").shape, MindmapShape::Hexagon);
    assert_eq!(node(root, "Default").shape, MindmapShape::Default);

    let square = node(root, "Square");
    assert_eq!(
        square.icon.as_ref().map(|icon| icon.value.as_str()),
        Some("fa fa-square")
    );
    assert_eq!(
        square
            .classes
            .iter()
            .map(|class| class.value.as_str())
            .collect::<Vec<_>>(),
        ["urgent", "large"],
    );

    let output = render_text(ALL_SHAPES_ICONS_CLASSES);
    assert!(output.contains("fa fa-square Square"));
}

#[test]
fn mindmap_markdown_labels_preserve_label_kind() {
    let ast = parse_mindmap(MARKDOWN_LABELS);
    let root = &ast.roots[0];

    assert_eq!(root.label.kind, LabelKind::Markdown);
    assert_eq!(root.label.text, "**Root** with *style*");
    assert_eq!(
        node(root, "plain **markdown** child").label.kind,
        LabelKind::Markdown
    );
    assert_eq!(node(root, "Regular label").label.kind, LabelKind::Plain);
}

#[test]
fn mindmap_unclear_indentation_uses_first_smaller_parent() {
    let ast = parse_mindmap(INDENTATION_EDGES);
    let a = node(&ast.roots[0], "A");

    assert_eq!(
        a.children
            .iter()
            .map(|child| child.label.text.as_str())
            .collect::<Vec<_>>(),
        ["B", "C"],
    );
}

#[test]
fn mindmap_deep_tree_layout_tracks_depths() {
    let ast = parse_mindmap(DEEP_TREE);
    let layout = MindmapLayoutEngine::default_values().layout(&ast);

    assert_eq!(
        layout
            .nodes
            .iter()
            .map(|node| (node.label.as_str(), node.depth))
            .collect::<Vec<_>>(),
        [
            ("Root", 0),
            ("L1", 1),
            ("L2", 2),
            ("L3", 3),
            ("L4", 4),
            ("L5", 5),
            ("L6", 6),
        ],
    );
}

fn parse_mindmap(source: &str) -> MindmapAst {
    let diagram = Parser::parse_diagram(source).unwrap();
    let DiagramKind::Mindmap(ast) = diagram.kind else {
        panic!("expected mindmap");
    };
    *ast
}

fn node<'a>(root: &'a MindmapNode, label: &str) -> &'a MindmapNode {
    if root.label.text == label {
        return root;
    }
    root.children
        .iter()
        .find_map(|child| find_node(child, label))
        .unwrap_or_else(|| panic!("missing node {label}"))
}

fn find_node<'a>(root: &'a MindmapNode, label: &str) -> Option<&'a MindmapNode> {
    if root.label.text == label {
        return Some(root);
    }
    root.children
        .iter()
        .find_map(|child| find_node(child, label))
}

fn render_text(source: &str) -> String {
    let diagram = Parser::parse_diagram(source).unwrap();
    let renderer = StaticFrameRenderer::default();
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });

    text.render_frame(&renderer.render_diagram(&diagram))
}
