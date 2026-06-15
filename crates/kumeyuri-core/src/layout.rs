use crate::ast::{Direction, FlowEdge, FlowNode, FlowStatement, FlowSubgraph, FlowchartAst};
use std::collections::VecDeque;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Layout;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FlowLayoutConfig {
    pub horizontal_spacing: i32,
    pub vertical_spacing: i32,
    pub horizontal_padding: i32,
    pub min_node_width: i32,
    pub node_height: i32,
}

impl Default for FlowLayoutConfig {
    fn default() -> Self {
        Self {
            horizontal_spacing: 4,
            vertical_spacing: 2,
            horizontal_padding: 2,
            min_node_width: 5,
            node_height: 3,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Point {
    pub x: i32,
    pub y: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Size {
    pub width: i32,
    pub height: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rect {
    pub origin: Point,
    pub size: Size,
}

impl Rect {
    #[must_use]
    pub const fn center(self) -> Point {
        Point {
            x: self.origin.x + self.size.width / 2,
            y: self.origin.y + self.size.height / 2,
        }
    }

    #[must_use]
    pub const fn right(self) -> i32 {
        self.origin.x + self.size.width
    }

    #[must_use]
    pub const fn bottom(self) -> i32 {
        self.origin.y + self.size.height
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedFlowNode {
    pub id: String,
    pub label: String,
    pub rect: Rect,
    pub layer: usize,
    pub order: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedFlowEdge {
    pub from: String,
    pub to: String,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowLayout {
    pub direction: Direction,
    pub nodes: Vec<PositionedFlowNode>,
    pub edges: Vec<PositionedFlowEdge>,
    pub size: Size,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct FlowLayoutEngine {
    config: FlowLayoutConfig,
}

impl FlowLayoutEngine {
    #[must_use]
    pub const fn new(config: FlowLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &FlowchartAst) -> FlowLayout {
        let graph = LayoutGraph::from_ast(ast);
        let layers = assign_layers(&graph);
        let order = minimise_crossings(&graph, &layers);
        place_graph(
            &graph,
            &layers,
            &order,
            ast.header.direction.value,
            self.config,
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct LayoutGraph {
    nodes: Vec<LayoutNode>,
    edges: Vec<LayoutGraphEdge>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct LayoutNode {
    id: String,
    label: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct LayoutGraphEdge {
    from: usize,
    to: usize,
    min_length: usize,
}

impl LayoutGraph {
    fn from_ast(ast: &FlowchartAst) -> Self {
        let mut graph = Self {
            nodes: Vec::new(),
            edges: Vec::new(),
        };
        for node in &ast.nodes {
            graph.ensure_node(node);
        }
        for edge in &ast.edges {
            graph.add_edge(edge);
        }
        for statement in &ast.statements {
            graph.add_statement(statement);
        }
        graph
    }

    fn add_statement(&mut self, statement: &FlowStatement) {
        match statement {
            FlowStatement::Node(node) => {
                self.ensure_node(node);
            }
            FlowStatement::Edge(edge) => self.add_edge(edge),
            FlowStatement::Subgraph(subgraph) => self.add_subgraph(subgraph),
            FlowStatement::ClassDef(_)
            | FlowStatement::ClassApply(_)
            | FlowStatement::Comment(_)
            | FlowStatement::Directive(_) => {}
        }
    }

    fn add_subgraph(&mut self, subgraph: &FlowSubgraph) {
        for statement in &subgraph.statements {
            self.add_statement(statement);
        }
    }

    fn add_edge(&mut self, edge: &FlowEdge) {
        let from = self.ensure_node(&edge.from);
        let to = self.ensure_node(&edge.to);
        self.edges.push(LayoutGraphEdge {
            from,
            to,
            min_length: usize::from(edge.link.value.min_length.max(1)),
        });
    }

    fn ensure_node(&mut self, node: &FlowNode) -> usize {
        if let Some(index) = self
            .nodes
            .iter()
            .position(|value| value.id == node.id.value)
        {
            if self.nodes[index].label == self.nodes[index].id
                && let Some(label) = &node.label
            {
                self.nodes[index].label = label.text.clone();
            }
            return index;
        }
        let label = node
            .label
            .as_ref()
            .map_or_else(|| node.id.value.clone(), |label| label.text.clone());
        self.nodes.push(LayoutNode {
            id: node.id.value.clone(),
            label,
        });
        self.nodes.len() - 1
    }
}

fn assign_layers(graph: &LayoutGraph) -> Vec<usize> {
    let mut indegree = vec![0usize; graph.nodes.len()];
    let mut outgoing = vec![Vec::new(); graph.nodes.len()];
    for edge in &graph.edges {
        indegree[edge.to] += 1;
        outgoing[edge.from].push(edge);
    }

    let mut queue = indegree
        .iter()
        .enumerate()
        .filter_map(|(index, degree)| (*degree == 0).then_some(index))
        .collect::<VecDeque<_>>();
    let mut layers = vec![0usize; graph.nodes.len()];
    let mut visited = 0usize;

    while let Some(index) = queue.pop_front() {
        visited += 1;
        for edge in &outgoing[index] {
            layers[edge.to] = layers[edge.to].max(layers[index] + edge.min_length);
            indegree[edge.to] -= 1;
            if indegree[edge.to] == 0 {
                queue.push_back(edge.to);
            }
        }
    }

    if visited != graph.nodes.len() {
        place_cyclic_remainder(graph, &mut layers);
    }
    layers
}

fn place_cyclic_remainder(graph: &LayoutGraph, layers: &mut [usize]) {
    for _ in 0..graph.nodes.len() {
        let mut changed = false;
        for edge in &graph.edges {
            let target = layers[edge.from] + edge.min_length;
            if target > layers[edge.to] && target <= graph.nodes.len() {
                layers[edge.to] = target;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
}

fn minimise_crossings(graph: &LayoutGraph, layers: &[usize]) -> Vec<usize> {
    let mut order = initial_order(layers);
    for _ in 0..4 {
        sweep(graph, layers, &mut order, true);
        sweep(graph, layers, &mut order, false);
    }
    order
}

fn initial_order(layers: &[usize]) -> Vec<usize> {
    let mut next = vec![0usize; layers.iter().copied().max().unwrap_or(0) + 1];
    let mut order = vec![0usize; layers.len()];
    for (index, layer) in layers.iter().copied().enumerate() {
        order[index] = next[layer];
        next[layer] += 1;
    }
    order
}

fn sweep(graph: &LayoutGraph, layers: &[usize], order: &mut [usize], forward: bool) {
    let max_layer = layers.iter().copied().max().unwrap_or(0);
    let mut layer_range = (0..=max_layer).collect::<Vec<_>>();
    if !forward {
        layer_range.reverse();
    }

    for layer in layer_range {
        let mut nodes = layers
            .iter()
            .enumerate()
            .filter_map(|(index, value)| (*value == layer).then_some(index))
            .collect::<Vec<_>>();
        nodes.sort_by_key(|index| {
            barycenter(graph, layers, order, *index, forward)
                .map(|(sum, count)| (sum / count, sum % count, 0usize))
                .unwrap_or((order[*index], 0, 1))
        });
        for (next_order, index) in nodes.into_iter().enumerate() {
            order[index] = next_order;
        }
    }
}

fn barycenter(
    graph: &LayoutGraph,
    layers: &[usize],
    order: &[usize],
    index: usize,
    forward: bool,
) -> Option<(usize, usize)> {
    let adjacent = graph
        .edges
        .iter()
        .filter_map(|edge| {
            if forward && edge.to == index && layers[edge.from] < layers[index] {
                Some(edge.from)
            } else if !forward && edge.from == index && layers[edge.to] > layers[index] {
                Some(edge.to)
            } else {
                None
            }
        })
        .collect::<Vec<_>>();
    (!adjacent.is_empty()).then(|| {
        (
            adjacent.iter().map(|index| order[*index]).sum(),
            adjacent.len(),
        )
    })
}

fn place_graph(
    graph: &LayoutGraph,
    layers: &[usize],
    order: &[usize],
    direction: Direction,
    config: FlowLayoutConfig,
) -> FlowLayout {
    let sizes = graph
        .nodes
        .iter()
        .map(|node| node_size(&node.label, config))
        .collect::<Vec<_>>();
    let mut rects = place_top_down(&sizes, layers, order, config);
    let mut size = layout_size(&rects);

    match direction {
        Direction::TopDown => {}
        Direction::BottomTop => {
            for rect in &mut rects {
                rect.origin.y = size.height - rect.bottom();
            }
        }
        Direction::LeftRight | Direction::RightLeft => {
            for rect in &mut rects {
                rect.origin = Point {
                    x: rect.origin.y,
                    y: rect.origin.x,
                };
                rect.size = Size {
                    width: rect.size.height,
                    height: rect.size.width,
                };
            }
            size = layout_size(&rects);
            if direction == Direction::RightLeft {
                for rect in &mut rects {
                    rect.origin.x = size.width - rect.right();
                }
            }
        }
    }

    let nodes = graph
        .nodes
        .iter()
        .enumerate()
        .map(|(index, node)| PositionedFlowNode {
            id: node.id.clone(),
            label: node.label.clone(),
            rect: rects[index],
            layer: layers[index],
            order: order[index],
        })
        .collect::<Vec<_>>();
    let edges = graph
        .edges
        .iter()
        .map(|edge| PositionedFlowEdge {
            from: graph.nodes[edge.from].id.clone(),
            to: graph.nodes[edge.to].id.clone(),
            points: vec![rects[edge.from].center(), rects[edge.to].center()],
        })
        .collect();

    FlowLayout {
        direction,
        nodes,
        edges,
        size,
    }
}

fn place_top_down(
    sizes: &[Size],
    layers: &[usize],
    order: &[usize],
    config: FlowLayoutConfig,
) -> Vec<Rect> {
    let max_layer = layers.iter().copied().max().unwrap_or(0);
    let mut layer_heights = vec![0i32; max_layer + 1];
    for (index, layer) in layers.iter().copied().enumerate() {
        layer_heights[layer] = layer_heights[layer].max(sizes[index].height);
    }

    let mut layer_y = vec![0i32; max_layer + 1];
    for layer in 1..=max_layer {
        layer_y[layer] = layer_y[layer - 1] + layer_heights[layer - 1] + config.vertical_spacing;
    }

    let mut rects = vec![
        Rect {
            origin: Point { x: 0, y: 0 },
            size: Size {
                width: 0,
                height: 0,
            },
        };
        sizes.len()
    ];
    for (layer, y) in layer_y.iter().copied().enumerate().take(max_layer + 1) {
        let mut indexes = layers
            .iter()
            .enumerate()
            .filter_map(|(index, value)| (*value == layer).then_some(index))
            .collect::<Vec<_>>();
        indexes.sort_by_key(|index| (order[*index], *index));

        let mut x = 0i32;
        for index in indexes {
            rects[index] = Rect {
                origin: Point { x, y },
                size: sizes[index],
            };
            x += sizes[index].width + config.horizontal_spacing;
        }
    }
    rects
}

fn node_size(label: &str, config: FlowLayoutConfig) -> Size {
    Size {
        width: config
            .min_node_width
            .max(label.chars().count() as i32 + config.horizontal_padding),
        height: config.node_height,
    }
}

fn layout_size(rects: &[Rect]) -> Size {
    Size {
        width: rects.iter().map(|rect| rect.right()).max().unwrap_or(0),
        height: rects.iter().map(|rect| rect.bottom()).max().unwrap_or(0),
    }
}

#[cfg(test)]
mod tests {
    use super::{FlowLayoutEngine, Point};
    use crate::ast::{ArrowHead, FlowShape, FlowchartAst};
    use crate::ast::{
        Direction, FlowEdge, FlowEdgeLink, FlowEdgeStroke, FlowNode, FlowStatement, FlowSubgraph,
        FlowchartDirective, FlowchartHeader, Label, LabelKind, Span, Spanned,
    };

    #[test]
    fn lays_out_top_down_flowchart_layers() {
        let ast = flowchart(
            Direction::TopDown,
            vec![
                FlowStatement::Edge(Box::new(edge("A", "B"))),
                FlowStatement::Edge(Box::new(edge("A", "C"))),
                FlowStatement::Edge(Box::new(edge("B", "D"))),
            ],
        );

        let layout = FlowLayoutEngine::default().layout(&ast);

        assert_eq!(layout.edges.len(), 3);
        assert!(node(&layout, "A").rect.origin.y < node(&layout, "B").rect.origin.y);
        assert_eq!(node(&layout, "B").layer, 1);
        assert_eq!(node(&layout, "C").layer, 1);
        assert_eq!(node(&layout, "D").layer, 2);
        assert_ne!(
            node(&layout, "B").rect.origin.x,
            node(&layout, "C").rect.origin.x
        );
    }

    #[test]
    fn lays_out_left_right_flowchart_layers() {
        let ast = flowchart(
            Direction::LeftRight,
            vec![
                FlowStatement::Edge(Box::new(edge("A", "B"))),
                FlowStatement::Edge(Box::new(edge("B", "C"))),
            ],
        );

        let layout = FlowLayoutEngine::default().layout(&ast);

        assert!(node(&layout, "A").rect.origin.x < node(&layout, "B").rect.origin.x);
        assert!(node(&layout, "B").rect.origin.x < node(&layout, "C").rect.origin.x);
    }

    #[test]
    fn reverses_bottom_top_and_right_left_coordinates() {
        let bottom_top = FlowLayoutEngine::default().layout(&flowchart(
            Direction::BottomTop,
            vec![FlowStatement::Edge(Box::new(edge("A", "B")))],
        ));
        let right_left = FlowLayoutEngine::default().layout(&flowchart(
            Direction::RightLeft,
            vec![FlowStatement::Edge(Box::new(edge("A", "B")))],
        ));

        assert!(node(&bottom_top, "A").rect.origin.y > node(&bottom_top, "B").rect.origin.y);
        assert!(node(&right_left, "A").rect.origin.x > node(&right_left, "B").rect.origin.x);
    }

    #[test]
    fn collects_nodes_and_edges_inside_subgraphs() {
        let subgraph = FlowSubgraph {
            id: Spanned::new("group".to_owned(), Span::new(0, 0)),
            label: None,
            direction: None,
            statements: vec![FlowStatement::Edge(Box::new(edge("A", "B")))],
            span: Span::new(0, 0),
        };
        let ast = flowchart(Direction::TopDown, vec![FlowStatement::Subgraph(subgraph)]);

        let layout = FlowLayoutEngine::default().layout(&ast);

        assert_eq!(layout.nodes.len(), 2);
        assert_eq!(layout.edges.len(), 1);
        assert_eq!(layout.edges[0].points.len(), 2);
    }

    fn flowchart(direction: Direction, statements: Vec<FlowStatement>) -> FlowchartAst {
        FlowchartAst {
            header: FlowchartHeader {
                directive: Spanned::new(FlowchartDirective::Graph, Span::new(0, 5)),
                direction: Spanned::new(direction, Span::new(6, 8)),
                span: Span::new(0, 8),
            },
            statements,
            nodes: Vec::new(),
            edges: Vec::new(),
            subgraphs: Vec::new(),
            classes: Vec::new(),
            span: Span::new(0, 0),
        }
    }

    fn edge(from: &str, to: &str) -> FlowEdge {
        FlowEdge {
            from: simple_node(from),
            to: simple_node(to),
            link: Spanned::new(
                FlowEdgeLink {
                    stroke: FlowEdgeStroke::Normal,
                    arrow_start: ArrowHead::None,
                    arrow_end: ArrowHead::Arrow,
                    min_length: 1,
                },
                Span::new(0, 0),
            ),
            label: None,
            span: Span::new(0, 0),
        }
    }

    fn simple_node(id: &str) -> FlowNode {
        FlowNode {
            id: Spanned::new(id.to_owned(), Span::new(0, 0)),
            label: Some(Label {
                text: id.to_owned(),
                kind: LabelKind::Plain,
                span: Span::new(0, 0),
            }),
            shape: Spanned::new(FlowShape::Rectangle, Span::new(0, 0)),
            span: Span::new(0, 0),
        }
    }

    fn node<'layout>(
        layout: &'layout super::FlowLayout,
        id: &str,
    ) -> &'layout super::PositionedFlowNode {
        layout
            .nodes
            .iter()
            .find(|node| node.id == id)
            .unwrap_or_else(|| panic!("missing node {id}"))
    }

    #[test]
    fn rect_center_uses_integer_midpoint() {
        let center = node(
            &FlowLayoutEngine::default().layout(&flowchart(
                Direction::TopDown,
                vec![FlowStatement::Node(simple_node("A"))],
            )),
            "A",
        )
        .rect
        .center();

        assert_eq!(center, Point { x: 2, y: 1 });
    }
}
