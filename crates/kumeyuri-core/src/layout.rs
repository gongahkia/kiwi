use crate::ast::{
    Direction, FlowEdge, FlowNode, FlowStatement, FlowSubgraph, FlowchartAst, SequenceAst,
    SequenceMessage, SequenceNote, SequenceParticipant, SequenceStatement,
};
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SequenceLayoutConfig {
    pub lane_spacing: i32,
    pub event_spacing: i32,
    pub participant_width: i32,
    pub participant_height: i32,
    pub top_padding: i32,
}

impl Default for SequenceLayoutConfig {
    fn default() -> Self {
        Self {
            lane_spacing: 12,
            event_spacing: 4,
            participant_width: 9,
            participant_height: 3,
            top_padding: 2,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedSequenceParticipant {
    pub id: String,
    pub label: String,
    pub lane_x: i32,
    pub header: Rect,
    pub order: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedSequenceMessage {
    pub from: String,
    pub to: String,
    pub label: Option<String>,
    pub y: i32,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedSequenceNote {
    pub participants: Vec<String>,
    pub label: String,
    pub rect: Rect,
    pub y: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedSequenceControl {
    pub label: Option<String>,
    pub rect: Rect,
    pub y: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceLayout {
    pub participants: Vec<PositionedSequenceParticipant>,
    pub messages: Vec<PositionedSequenceMessage>,
    pub notes: Vec<PositionedSequenceNote>,
    pub controls: Vec<PositionedSequenceControl>,
    pub size: Size,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct FlowLayoutEngine {
    config: FlowLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct SequenceLayoutEngine {
    config: SequenceLayoutConfig,
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

impl SequenceLayoutEngine {
    #[must_use]
    pub const fn new(config: SequenceLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &SequenceAst) -> SequenceLayout {
        let participants = sequence_participants(ast);
        let positioned_participants = self.position_participants(&participants);
        let mut messages = Vec::new();
        let mut notes = Vec::new();
        let mut controls = Vec::new();
        let mut event_index = 0i32;

        for statement in &ast.statements {
            match statement {
                SequenceStatement::Message(message) => {
                    let y = self.event_y(event_index);
                    event_index += 1;
                    messages.push(self.position_message(message, &positioned_participants, y));
                }
                SequenceStatement::Note(note) => {
                    let y = self.event_y(event_index);
                    event_index += 1;
                    notes.push(self.position_note(note, &positioned_participants, y));
                }
                SequenceStatement::Control(control) => {
                    let y = self.event_y(event_index);
                    event_index += 1;
                    controls.push(PositionedSequenceControl {
                        label: control.label.as_ref().map(|label| label.text.clone()),
                        rect: Rect {
                            origin: Point { x: 0, y: y - 1 },
                            size: Size {
                                width: sequence_width(&positioned_participants, self.config),
                                height: self.config.participant_height,
                            },
                        },
                        y,
                    });
                }
                SequenceStatement::Participant(_)
                | SequenceStatement::ActivationStart(_)
                | SequenceStatement::ActivationEnd(_)
                | SequenceStatement::AutoNumber(_)
                | SequenceStatement::Comment(_)
                | SequenceStatement::Directive(_) => {}
            }
        }

        let mut size = Size {
            width: sequence_width(&positioned_participants, self.config),
            height: self.config.participant_height,
        };
        for rect in positioned_participants
            .iter()
            .map(|participant| participant.header)
            .chain(notes.iter().map(|note| note.rect))
            .chain(controls.iter().map(|control| control.rect))
        {
            size.width = size.width.max(rect.right());
            size.height = size.height.max(rect.bottom());
        }
        for message in &messages {
            for point in &message.points {
                size.width = size.width.max(point.x + 1);
                size.height = size.height.max(point.y + 1);
            }
        }

        SequenceLayout {
            participants: positioned_participants,
            messages,
            notes,
            controls,
            size,
        }
    }

    fn position_participants(
        self,
        participants: &[SequenceParticipantRef],
    ) -> Vec<PositionedSequenceParticipant> {
        participants
            .iter()
            .enumerate()
            .map(|(order, participant)| {
                let lane_x =
                    order as i32 * self.config.lane_spacing + self.config.participant_width / 2;
                PositionedSequenceParticipant {
                    id: participant.id.clone(),
                    label: participant.label.clone(),
                    lane_x,
                    header: Rect {
                        origin: Point {
                            x: lane_x - self.config.participant_width / 2,
                            y: 0,
                        },
                        size: Size {
                            width: self.config.participant_width,
                            height: self.config.participant_height,
                        },
                    },
                    order,
                }
            })
            .collect()
    }

    fn position_message(
        self,
        message: &SequenceMessage,
        participants: &[PositionedSequenceParticipant],
        y: i32,
    ) -> PositionedSequenceMessage {
        let from_x = participant_lane(participants, &message.from.value);
        let to_x = participant_lane(participants, &message.to.value);
        let points = if from_x == to_x {
            vec![
                Point { x: from_x, y },
                Point {
                    x: from_x + self.config.lane_spacing / 2,
                    y,
                },
                Point {
                    x: from_x + self.config.lane_spacing / 2,
                    y: y + self.config.event_spacing / 2,
                },
                Point {
                    x: from_x,
                    y: y + self.config.event_spacing / 2,
                },
            ]
        } else {
            vec![Point { x: from_x, y }, Point { x: to_x, y }]
        };
        PositionedSequenceMessage {
            from: message.from.value.clone(),
            to: message.to.value.clone(),
            label: message.label.as_ref().map(|label| label.text.clone()),
            y,
            points,
        }
    }

    fn position_note(
        self,
        note: &SequenceNote,
        participants: &[PositionedSequenceParticipant],
        y: i32,
    ) -> PositionedSequenceNote {
        let lanes = note
            .participants
            .iter()
            .map(|participant| participant_lane(participants, &participant.value))
            .collect::<Vec<_>>();
        let min_x = lanes.iter().copied().min().unwrap_or(0);
        let max_x = lanes.iter().copied().max().unwrap_or(min_x);
        let width = (max_x - min_x + self.config.participant_width)
            .max(note.label.text.chars().count() as i32 + 2);
        PositionedSequenceNote {
            participants: note
                .participants
                .iter()
                .map(|participant| participant.value.clone())
                .collect(),
            label: note.label.text.clone(),
            rect: Rect {
                origin: Point {
                    x: min_x - self.config.participant_width / 2,
                    y: y - 1,
                },
                size: Size {
                    width,
                    height: self.config.participant_height,
                },
            },
            y,
        }
    }

    fn event_y(self, event_index: i32) -> i32 {
        self.config.participant_height
            + self.config.top_padding
            + event_index * self.config.event_spacing
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SequenceParticipantRef {
    id: String,
    label: String,
}

fn sequence_participants(ast: &SequenceAst) -> Vec<SequenceParticipantRef> {
    let mut participants = Vec::new();
    for participant in &ast.participants {
        ensure_sequence_participant(&mut participants, participant);
    }
    for statement in &ast.statements {
        match statement {
            SequenceStatement::Participant(participant) => {
                ensure_sequence_participant(&mut participants, participant);
            }
            SequenceStatement::Message(message) => {
                ensure_sequence_id(&mut participants, &message.from.value);
                ensure_sequence_id(&mut participants, &message.to.value);
            }
            SequenceStatement::Note(note) => {
                for participant in &note.participants {
                    ensure_sequence_id(&mut participants, &participant.value);
                }
            }
            SequenceStatement::Control(control) => {
                for statement in &control.statements {
                    collect_sequence_statement_participants(&mut participants, statement);
                }
            }
            SequenceStatement::ActivationStart(participant)
            | SequenceStatement::ActivationEnd(participant) => {
                ensure_sequence_id(&mut participants, &participant.value);
            }
            SequenceStatement::AutoNumber(_)
            | SequenceStatement::Comment(_)
            | SequenceStatement::Directive(_) => {}
        }
    }
    participants
}

fn collect_sequence_statement_participants(
    participants: &mut Vec<SequenceParticipantRef>,
    statement: &SequenceStatement,
) {
    match statement {
        SequenceStatement::Participant(participant) => {
            ensure_sequence_participant(participants, participant);
        }
        SequenceStatement::Message(message) => {
            ensure_sequence_id(participants, &message.from.value);
            ensure_sequence_id(participants, &message.to.value);
        }
        SequenceStatement::Note(note) => {
            for participant in &note.participants {
                ensure_sequence_id(participants, &participant.value);
            }
        }
        SequenceStatement::Control(control) => {
            for statement in &control.statements {
                collect_sequence_statement_participants(participants, statement);
            }
        }
        SequenceStatement::ActivationStart(participant)
        | SequenceStatement::ActivationEnd(participant) => {
            ensure_sequence_id(participants, &participant.value);
        }
        SequenceStatement::AutoNumber(_)
        | SequenceStatement::Comment(_)
        | SequenceStatement::Directive(_) => {}
    }
}

fn ensure_sequence_participant(
    participants: &mut Vec<SequenceParticipantRef>,
    participant: &SequenceParticipant,
) {
    let label = participant
        .alias
        .as_ref()
        .map_or_else(|| participant.id.value.clone(), |label| label.text.clone());
    if let Some(existing) = participants
        .iter_mut()
        .find(|value| value.id == participant.id.value)
    {
        existing.label = label;
        return;
    }
    participants.push(SequenceParticipantRef {
        id: participant.id.value.clone(),
        label,
    });
}

fn ensure_sequence_id(participants: &mut Vec<SequenceParticipantRef>, id: &str) {
    if participants.iter().any(|participant| participant.id == id) {
        return;
    }
    participants.push(SequenceParticipantRef {
        id: id.to_owned(),
        label: id.to_owned(),
    });
}

fn participant_lane(participants: &[PositionedSequenceParticipant], id: &str) -> i32 {
    participants
        .iter()
        .find(|participant| participant.id == id)
        .map_or(0, |participant| participant.lane_x)
}

fn sequence_width(
    participants: &[PositionedSequenceParticipant],
    config: SequenceLayoutConfig,
) -> i32 {
    participants
        .last()
        .map_or(config.participant_width, |last| {
            last.header.right().max(config.participant_width)
        })
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
    use super::{FlowLayoutEngine, Point, SequenceLayoutEngine};
    use crate::ast::{ArrowHead, FlowShape, FlowchartAst};
    use crate::ast::{
        Direction, FlowEdge, FlowEdgeLink, FlowEdgeStroke, FlowNode, FlowStatement, FlowSubgraph,
        FlowchartDirective, FlowchartHeader, Label, LabelKind, SequenceArrow, SequenceAst,
        SequenceControlBlock, SequenceControlKind, SequenceHeader, SequenceMessage, SequenceNote,
        SequenceNotePlacement, SequenceParticipant, SequenceParticipantKind, SequenceStatement,
        Span, Spanned,
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

    #[test]
    fn lays_out_sequence_participants_as_lanes() {
        let ast = sequence(vec![
            SequenceStatement::Participant(Box::new(participant("Alice", Some("Alice Doe")))),
            SequenceStatement::Participant(Box::new(participant("Bob", None))),
            SequenceStatement::Message(Box::new(message("Alice", "Bob", "Request"))),
        ]);

        let layout = SequenceLayoutEngine::default().layout(&ast);

        assert_eq!(layout.participants.len(), 2);
        assert_eq!(sequence_participant(&layout, "Alice").label, "Alice Doe");
        assert!(
            sequence_participant(&layout, "Alice").lane_x
                < sequence_participant(&layout, "Bob").lane_x
        );
        assert_eq!(layout.messages.len(), 1);
        assert_eq!(layout.messages[0].points.len(), 2);
        assert_eq!(layout.messages[0].from, "Alice");
        assert_eq!(layout.messages[0].to, "Bob");
    }

    #[test]
    fn adds_implicit_sequence_participants_from_messages() {
        let ast = sequence(vec![SequenceStatement::Message(Box::new(message(
            "Client", "Server", "GET",
        )))]);

        let layout = SequenceLayoutEngine::default().layout(&ast);

        assert_eq!(layout.participants.len(), 2);
        assert_eq!(sequence_participant(&layout, "Client").order, 0);
        assert_eq!(sequence_participant(&layout, "Server").order, 1);
    }

    #[test]
    fn lays_out_sequence_notes_across_participants() {
        let ast = sequence(vec![
            SequenceStatement::Participant(Box::new(participant("Alice", None))),
            SequenceStatement::Participant(Box::new(participant("Bob", None))),
            SequenceStatement::Note(Box::new(SequenceNote {
                placement: SequenceNotePlacement::Over,
                participants: vec![
                    Spanned::new("Alice".to_owned(), Span::new(0, 0)),
                    Spanned::new("Bob".to_owned(), Span::new(0, 0)),
                ],
                label: label("Shared"),
                span: Span::new(0, 0),
            })),
        ]);

        let layout = SequenceLayoutEngine::default().layout(&ast);

        assert_eq!(layout.notes.len(), 1);
        assert_eq!(layout.notes[0].participants, vec!["Alice", "Bob"]);
        assert!(layout.notes[0].rect.size.width >= 21);
    }

    #[test]
    fn lays_out_sequence_self_messages_as_loop_points() {
        let ast = sequence(vec![
            SequenceStatement::Participant(Box::new(participant("Alice", None))),
            SequenceStatement::Message(Box::new(message("Alice", "Alice", "Self"))),
        ]);

        let layout = SequenceLayoutEngine::default().layout(&ast);

        assert_eq!(layout.messages[0].points.len(), 4);
        assert_eq!(
            layout.messages[0].points[0].x,
            layout.messages[0].points[3].x
        );
    }

    #[test]
    fn lays_out_sequence_control_blocks_as_timeline_bands() {
        let ast = sequence(vec![SequenceStatement::Control(Box::new(
            SequenceControlBlock {
                kind: SequenceControlKind::Loop,
                label: Some(label("Retry")),
                statements: Vec::new(),
                span: Span::new(0, 0),
            },
        ))]);

        let layout = SequenceLayoutEngine::default().layout(&ast);

        assert_eq!(layout.controls.len(), 1);
        assert_eq!(layout.controls[0].label.as_deref(), Some("Retry"));
    }

    fn sequence(statements: Vec<SequenceStatement>) -> SequenceAst {
        SequenceAst {
            header: SequenceHeader {
                span: Span::new(0, 15),
            },
            statements,
            participants: Vec::new(),
            boxes: Vec::new(),
            span: Span::new(0, 0),
        }
    }

    fn participant(id: &str, alias: Option<&str>) -> SequenceParticipant {
        SequenceParticipant {
            id: Spanned::new(id.to_owned(), Span::new(0, 0)),
            alias: alias.map(label),
            kind: SequenceParticipantKind::Participant,
            span: Span::new(0, 0),
        }
    }

    fn message(from: &str, to: &str, text: &str) -> SequenceMessage {
        SequenceMessage {
            from: Spanned::new(from.to_owned(), Span::new(0, 0)),
            to: Spanned::new(to.to_owned(), Span::new(0, 0)),
            arrow: SequenceArrow::SolidArrow,
            label: Some(label(text)),
            span: Span::new(0, 0),
        }
    }

    fn label(text: &str) -> Label {
        Label {
            text: text.to_owned(),
            kind: LabelKind::Plain,
            span: Span::new(0, 0),
        }
    }

    fn sequence_participant<'layout>(
        layout: &'layout super::SequenceLayout,
        id: &str,
    ) -> &'layout super::PositionedSequenceParticipant {
        layout
            .participants
            .iter()
            .find(|participant| participant.id == id)
            .unwrap_or_else(|| panic!("missing participant {id}"))
    }
}
