use crate::ast::{
    ArrowHead, ClassAst, ClassMember, ClassMemberKind, ClassNode, ClassRelationship,
    ClassRelationshipLine, ClassRelationshipMarker, Direction, ErAst, ErAttribute, ErCardinality,
    ErEntity, FlowEdge, FlowEdgeLink, FlowEdgeStroke, FlowNode, FlowShape, FlowStatement,
    FlowSubgraph, FlowchartAst, FlowchartDirective, FlowchartHeader, GanttAst, GanttTask,
    GanttTaskTag, JourneyAst, Label, LabelKind, MindmapAst, MindmapNode, MindmapShape, PieAst,
    SequenceAst, SequenceMessage, SequenceNote, SequenceParticipant, SequenceStatement, Spanned,
    StateAst, StateNode, StateStatement, StateTransition,
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
            horizontal_spacing: 5,
            vertical_spacing: 5,
            horizontal_padding: 4,
            min_node_width: 5,
            node_height: 5,
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
    pub arrow_start: ArrowHead,
    pub arrow_end: ArrowHead,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedFlowSubgraph {
    pub id: String,
    pub label: String,
    pub rect: Rect,
    pub child_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowLayout {
    pub direction: Direction,
    pub nodes: Vec<PositionedFlowNode>,
    pub edges: Vec<PositionedFlowEdge>,
    pub subgraphs: Vec<PositionedFlowSubgraph>,
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StateLayout {
    pub graph: FlowLayout,
    pub composites: Vec<PositionedStateComposite>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedStateComposite {
    pub id: String,
    pub child_ids: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ClassLayoutConfig {
    pub horizontal_spacing: i32,
    pub vertical_spacing: i32,
    pub horizontal_padding: i32,
    pub min_node_width: i32,
}

impl Default for ClassLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl ClassLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            horizontal_spacing: 12,
            vertical_spacing: 5,
            horizontal_padding: 4,
            min_node_width: 7,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedClassNode {
    pub id: String,
    pub annotations: Vec<String>,
    pub fields: Vec<String>,
    pub methods: Vec<String>,
    pub rect: Rect,
    pub layer: usize,
    pub order: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedClassRelationship {
    pub from: String,
    pub to: String,
    pub line: ClassRelationshipLine,
    pub start_marker: ClassRelationshipMarker,
    pub end_marker: ClassRelationshipMarker,
    pub label: Option<String>,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassLayout {
    pub direction: Direction,
    pub nodes: Vec<PositionedClassNode>,
    pub relationships: Vec<PositionedClassRelationship>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GanttLayoutConfig {
    pub left_width: i32,
    pub day_width: i32,
    pub row_height: i32,
    pub top_padding: i32,
}

impl Default for GanttLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl GanttLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            left_width: 18,
            day_width: 2,
            row_height: 2,
            top_padding: 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedGanttSection {
    pub label: String,
    pub y: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedGanttTask {
    pub id: Option<String>,
    pub title: String,
    pub section: Option<String>,
    pub tags: Vec<GanttTaskTag>,
    pub start: i32,
    pub end: i32,
    pub rect: Rect,
    pub label_origin: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GanttLayout {
    pub title: Option<String>,
    pub sections: Vec<PositionedGanttSection>,
    pub tasks: Vec<PositionedGanttTask>,
    pub min_day: i32,
    pub max_day: i32,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PieLayoutConfig {
    pub radius_x: i32,
    pub radius_y: i32,
    pub top_padding: i32,
    pub legend_gap: i32,
}

impl Default for PieLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl PieLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            radius_x: 12,
            radius_y: 6,
            top_padding: 2,
            legend_gap: 4,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PieCell {
    pub point: Point,
    pub slice_index: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedPieSlice {
    pub label: String,
    pub value_text: String,
    pub value_units: u64,
    pub percent_basis_points: u16,
    pub legend_origin: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PieLayout {
    pub title: Option<String>,
    pub show_data: bool,
    pub center: Point,
    pub slices: Vec<PositionedPieSlice>,
    pub cells: Vec<PieCell>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MindmapLayoutConfig {
    pub horizontal_spacing: i32,
    pub vertical_spacing: i32,
    pub node_padding: i32,
    pub min_node_width: i32,
    pub node_height: i32,
}

impl Default for MindmapLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl MindmapLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            horizontal_spacing: 8,
            vertical_spacing: 4,
            node_padding: 2,
            min_node_width: 9,
            node_height: 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedMindmapNode {
    pub id: usize,
    pub label: String,
    pub shape: MindmapShape,
    pub icon: Option<String>,
    pub classes: Vec<String>,
    pub depth: usize,
    pub rect: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedMindmapEdge {
    pub from: usize,
    pub to: usize,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MindmapLayout {
    pub nodes: Vec<PositionedMindmapNode>,
    pub edges: Vec<PositionedMindmapEdge>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct JourneyLayoutConfig {
    pub label_width: i32,
    pub score_width: i32,
    pub score_label_width: i32,
    pub actor_gap: i32,
    pub row_height: i32,
    pub section_gap: i32,
    pub top_padding: i32,
}

impl Default for JourneyLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl JourneyLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            label_width: 24,
            score_width: 10,
            score_label_width: 4,
            actor_gap: 2,
            row_height: 2,
            section_gap: 1,
            top_padding: 2,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedJourneySection {
    pub label: String,
    pub y: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedJourneyTask {
    pub index: usize,
    pub label: String,
    pub section: Option<String>,
    pub score: u8,
    pub actors: Vec<String>,
    pub label_origin: Point,
    pub bar_rect: Rect,
    pub score_origin: Point,
    pub actors_origin: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JourneyLayout {
    pub title: Option<String>,
    pub sections: Vec<PositionedJourneySection>,
    pub tasks: Vec<PositionedJourneyTask>,
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

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct StateLayoutEngine {
    flow: FlowLayoutEngine,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct ClassLayoutEngine {
    config: ClassLayoutConfig,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ErLayoutEngine {
    config: ClassLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct GanttLayoutEngine {
    config: GanttLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct PieLayoutEngine {
    config: PieLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct MindmapLayoutEngine {
    config: MindmapLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct JourneyLayoutEngine {
    config: JourneyLayoutConfig,
}

impl Default for ErLayoutEngine {
    fn default() -> Self {
        Self::default_values()
    }
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

impl StateLayoutEngine {
    #[must_use]
    pub const fn new(flow: FlowLayoutEngine) -> Self {
        Self { flow }
    }

    #[must_use]
    pub fn layout(&self, ast: &StateAst) -> StateLayout {
        let direction = ast
            .direction
            .map_or(Direction::TopDown, |value| value.value);
        let mut statements = Vec::new();
        let mut composites = Vec::new();

        for state in &ast.states {
            statements.push(FlowStatement::Node(state_to_flow_node(state)));
        }
        for transition in &ast.transitions {
            statements.push(FlowStatement::Edge(Box::new(state_transition_to_edge(
                transition,
            ))));
        }
        for statement in &ast.statements {
            collect_state_statement(statement, &mut statements, &mut composites);
        }

        let flow_ast = FlowchartAst {
            header: FlowchartHeader {
                directive: Spanned::new(FlowchartDirective::Graph, ast.header.span),
                direction: Spanned::new(direction, ast.header.span),
                span: ast.header.span,
            },
            statements,
            nodes: Vec::new(),
            edges: Vec::new(),
            subgraphs: Vec::new(),
            classes: Vec::new(),
            span: ast.span,
        };

        StateLayout {
            graph: self.flow.layout(&flow_ast),
            composites,
        }
    }
}

impl ClassLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: ClassLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: ClassLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &ClassAst) -> ClassLayout {
        let direction = ast
            .direction
            .map_or(Direction::TopDown, |value| value.value);
        let graph = LayoutGraph::from_class_ast(ast);
        let layers = assign_layers(&graph);
        let order = minimise_crossings(&graph, &layers);
        let sizes = graph
            .nodes
            .iter()
            .filter_map(|node| ast.classes.iter().find(|class| class.id.value == node.id))
            .map(|class| class_node_size(class, self.config))
            .collect::<Vec<_>>();
        let placement_config = FlowLayoutConfig {
            horizontal_spacing: self.config.horizontal_spacing,
            vertical_spacing: self.config.vertical_spacing,
            horizontal_padding: self.config.horizontal_padding,
            min_node_width: self.config.min_node_width,
            node_height: 3,
        };
        let mut rects = place_top_down(&sizes, &layers, &order, placement_config);
        transform_rects_for_direction(&mut rects, &layers, direction, placement_config);
        let mut size = layout_size(&rects);

        let nodes = graph
            .nodes
            .iter()
            .enumerate()
            .filter_map(|(index, node)| {
                let class = ast.classes.iter().find(|class| class.id.value == node.id)?;
                Some(PositionedClassNode {
                    id: class.id.value.clone(),
                    annotations: class
                        .annotations
                        .iter()
                        .map(|annotation| annotation.text.clone())
                        .collect(),
                    fields: class_member_lines(class, ClassMemberKind::Field),
                    methods: class_member_lines(class, ClassMemberKind::Method),
                    rect: rects[index],
                    layer: layers[index],
                    order: order[index],
                })
            })
            .collect::<Vec<_>>();
        let relationships = ast
            .relationships
            .iter()
            .filter_map(|relationship| {
                let from = graph.node_index(&relationship.from.value)?;
                let to = graph.node_index(&relationship.to.value)?;
                Some(PositionedClassRelationship {
                    from: relationship.from.value.clone(),
                    to: relationship.to.value.clone(),
                    line: relationship.line,
                    start_marker: relationship.start_marker,
                    end_marker: relationship.end_marker,
                    label: relationship.label.as_ref().map(|label| label.text.clone()),
                    points: route_class_relationship(
                        rects[from],
                        rects[to],
                        direction,
                        closes_existing_path(&graph, to, from, (from, to)),
                    ),
                })
            })
            .collect::<Vec<_>>();
        size = layout_size_with_class_relationships(size, &relationships);

        ClassLayout {
            direction,
            nodes,
            relationships,
            size,
        }
    }
}

impl ErLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: ClassLayoutConfig {
                horizontal_spacing: 18,
                vertical_spacing: 5,
                horizontal_padding: 4,
                min_node_width: 7,
            },
        }
    }

    #[must_use]
    pub const fn new(config: ClassLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &ErAst) -> ClassLayout {
        let direction = Direction::LeftRight;
        let graph = LayoutGraph::from_er_ast(ast);
        let layers = assign_layers(&graph);
        let order = minimise_crossings(&graph, &layers);
        let sizes = graph
            .nodes
            .iter()
            .filter_map(|node| {
                ast.entities
                    .iter()
                    .find(|entity| entity.id.value == node.id)
            })
            .map(|entity| er_entity_size(entity, self.config))
            .collect::<Vec<_>>();
        let placement_config = FlowLayoutConfig {
            horizontal_spacing: self.config.horizontal_spacing,
            vertical_spacing: self.config.vertical_spacing,
            horizontal_padding: self.config.horizontal_padding,
            min_node_width: self.config.min_node_width,
            node_height: 3,
        };
        let mut rects = place_top_down(&sizes, &layers, &order, placement_config);
        transform_rects_for_direction(&mut rects, &layers, direction, placement_config);
        let mut size = layout_size(&rects);

        let nodes = graph
            .nodes
            .iter()
            .enumerate()
            .filter_map(|(index, node)| {
                let entity = ast
                    .entities
                    .iter()
                    .find(|entity| entity.id.value == node.id)?;
                Some(PositionedClassNode {
                    id: entity.id.value.clone(),
                    annotations: Vec::new(),
                    fields: er_attribute_lines(entity),
                    methods: Vec::new(),
                    rect: rects[index],
                    layer: layers[index],
                    order: order[index],
                })
            })
            .collect::<Vec<_>>();
        let relationships = ast
            .relationships
            .iter()
            .filter_map(|relationship| {
                let from = graph.node_index(&relationship.from.value)?;
                let to = graph.node_index(&relationship.to.value)?;
                Some(PositionedClassRelationship {
                    from: relationship.from.value.clone(),
                    to: relationship.to.value.clone(),
                    line: if relationship.identifying {
                        ClassRelationshipLine::Solid
                    } else {
                        ClassRelationshipLine::Dotted
                    },
                    start_marker: er_cardinality_marker(relationship.start_cardinality),
                    end_marker: er_cardinality_marker(relationship.end_cardinality),
                    label: relationship.label.as_ref().map(|label| label.text.clone()),
                    points: route_class_relationship(
                        rects[from],
                        rects[to],
                        direction,
                        closes_existing_path(&graph, to, from, (from, to)),
                    ),
                })
            })
            .collect::<Vec<_>>();
        size = layout_size_with_class_relationships(size, &relationships);

        ClassLayout {
            direction,
            nodes,
            relationships,
            size,
        }
    }
}

impl GanttLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: GanttLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: GanttLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &GanttAst) -> GanttLayout {
        let scheduled = schedule_gantt_tasks(ast);
        let min_day = scheduled.iter().map(|task| task.start).min().unwrap_or(0);
        let max_day = scheduled
            .iter()
            .map(|task| task.end.max(task.start + 1))
            .max()
            .unwrap_or(min_day + 1);
        let mut sections = Vec::new();
        let mut tasks = Vec::new();
        let mut y = self.config.top_padding;
        let mut current_section = None::<String>;

        for task in scheduled {
            if task.section != current_section {
                if let Some(section) = &task.section {
                    sections.push(PositionedGanttSection {
                        label: section.clone(),
                        y,
                    });
                    y += self.config.row_height;
                }
                current_section = task.section.clone();
            }
            let x = self.config.left_width + (task.start - min_day) * self.config.day_width;
            let width = ((task.end - task.start).max(1) * self.config.day_width).max(1);
            tasks.push(PositionedGanttTask {
                id: task.id,
                title: task.title,
                section: task.section,
                tags: task.tags,
                start: task.start,
                end: task.end,
                rect: Rect {
                    origin: Point { x, y },
                    size: Size { width, height: 1 },
                },
                label_origin: Point { x: 0, y },
            });
            y += self.config.row_height;
        }

        let title_width = ast
            .title
            .as_ref()
            .map_or(0, |title| title.text.chars().count() as i32);
        GanttLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            sections,
            tasks,
            min_day,
            max_day,
            size: Size {
                width: (self.config.left_width
                    + (max_day - min_day).max(1) * self.config.day_width
                    + 2)
                .max(title_width),
                height: y.max(self.config.top_padding + 1),
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ScheduledGanttTask {
    id: Option<String>,
    title: String,
    section: Option<String>,
    tags: Vec<GanttTaskTag>,
    start: i32,
    end: i32,
}

fn schedule_gantt_tasks(ast: &GanttAst) -> Vec<ScheduledGanttTask> {
    let mut scheduled = Vec::new();
    let mut previous_end = 0;
    for task in &ast.tasks {
        let (start, end) = resolve_gantt_task(task, previous_end, &scheduled);
        previous_end = end;
        scheduled.push(ScheduledGanttTask {
            id: task.id.as_ref().map(|id| id.value.clone()),
            title: task.title.text.clone(),
            section: task.section.as_ref().map(|section| section.text.clone()),
            tags: task.tags.clone(),
            start,
            end,
        });
    }
    for _ in 0..ast.tasks.len() {
        let mut changed = false;
        for (index, task) in ast.tasks.iter().enumerate() {
            let previous_end = index
                .checked_sub(1)
                .and_then(|previous| scheduled.get(previous))
                .map_or(0, |task| task.end);
            let (start, end) = resolve_gantt_task(task, previous_end, &scheduled);
            if scheduled[index].start != start || scheduled[index].end != end {
                scheduled[index].start = start;
                scheduled[index].end = end;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    scheduled
}

fn resolve_gantt_task(
    task: &GanttTask,
    previous_end: i32,
    scheduled: &[ScheduledGanttTask],
) -> (i32, i32) {
    let metadata = task
        .metadata
        .iter()
        .map(|value| value.value.as_str())
        .collect::<Vec<_>>();
    let (start, end_spec) = match metadata.as_slice() {
        [end] => (previous_end, *end),
        [start, end, ..] => (resolve_gantt_start(start, previous_end, scheduled), *end),
        [] => (previous_end, "1d"),
    };
    let end = resolve_gantt_end(end_spec, start, scheduled);
    let min_span = if is_gantt_milestone(task) { 1 } else { 0 };
    (start, end.max(start + min_span))
}

fn is_gantt_milestone(task: &GanttTask) -> bool {
    task.tags.contains(&GanttTaskTag::Milestone)
}

fn resolve_gantt_start(value: &str, previous_end: i32, scheduled: &[ScheduledGanttTask]) -> i32 {
    if let Some(ids) = value.strip_prefix("after ") {
        return ids
            .split_ascii_whitespace()
            .filter_map(|id| gantt_task_by_id(scheduled, id).map(|task| task.end))
            .max()
            .unwrap_or(previous_end);
    }
    gantt_date_day(value).unwrap_or(previous_end)
}

fn resolve_gantt_end(value: &str, start: i32, scheduled: &[ScheduledGanttTask]) -> i32 {
    if let Some(id) = value.strip_prefix("until ") {
        return gantt_task_by_id(scheduled, id.trim()).map_or(start, |task| task.start);
    }
    if let Some(duration) = gantt_duration_days(value) {
        return start + duration.max(0);
    }
    gantt_date_day(value).unwrap_or(start + 1)
}

fn gantt_task_by_id<'a>(
    scheduled: &'a [ScheduledGanttTask],
    id: &str,
) -> Option<&'a ScheduledGanttTask> {
    scheduled.iter().find(|task| task.id.as_deref() == Some(id))
}

fn gantt_duration_days(value: &str) -> Option<i32> {
    let suffix_start = value
        .find(|ch: char| !(ch.is_ascii_digit() || ch == '.'))
        .unwrap_or(value.len());
    if suffix_start == 0 || suffix_start == value.len() {
        return None;
    }
    let amount = value[..suffix_start].parse::<f32>().ok()?;
    let unit = &value[suffix_start..];
    let days = match unit {
        "ms" | "s" | "m" | "h" => 1.0,
        "d" => amount,
        "w" => amount * 7.0,
        "M" => amount * 30.0,
        "y" => amount * 365.0,
        _ => return None,
    };
    Some(days.ceil().max(0.0) as i32)
}

fn gantt_date_day(value: &str) -> Option<i32> {
    let mut parts = value.split('-');
    let year = parts.next()?.parse::<i32>().ok()?;
    let month = parts.next()?.parse::<i32>().ok()?;
    let day = parts.next()?.parse::<i32>().ok()?;
    (parts.next().is_none() && (1..=12).contains(&month) && (1..=31).contains(&day))
        .then(|| days_from_civil(year, month, day))
}

fn days_from_civil(year: i32, month: i32, day: i32) -> i32 {
    let year = year - i32::from(month <= 2);
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let yoe = year - era * 400;
    let month = month + if month > 2 { -3 } else { 9 };
    let doy = (153 * month + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

impl PieLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: PieLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: PieLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &PieAst) -> PieLayout {
        let total = ast
            .slices
            .iter()
            .map(|slice| slice.value_units.value)
            .sum::<u64>();
        let center = Point {
            x: self.config.radius_x,
            y: self.config.top_padding + self.config.radius_y,
        };
        let legend_x = self.config.radius_x * 2 + self.config.legend_gap;
        let mut slices = Vec::new();
        let mut cumulative = Vec::new();
        let mut running = 0u64;
        for (index, slice) in ast.slices.iter().enumerate() {
            running = running.saturating_add(slice.value_units.value);
            cumulative.push(running);
            slices.push(PositionedPieSlice {
                label: slice.label.text.clone(),
                value_text: slice.value_text.value.clone(),
                value_units: slice.value_units.value,
                percent_basis_points: pie_percent_basis_points(slice.value_units.value, total),
                legend_origin: Point {
                    x: legend_x,
                    y: self.config.top_padding + index as i32,
                },
            });
        }
        let cells = pie_cells(&self.config, center, total, &cumulative);
        let title_width = ast
            .title
            .as_ref()
            .map_or(0, |title| title.text.chars().count() as i32);
        let legend_width = slices
            .iter()
            .map(|slice| pie_legend_width(slice, ast.show_data))
            .max()
            .unwrap_or(0);
        let pie_width = self.config.radius_x * 2 + 1;
        let pie_height = self.config.top_padding + self.config.radius_y * 2 + 1;
        let legend_height = self.config.top_padding + slices.len() as i32;

        PieLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            show_data: ast.show_data,
            center,
            slices,
            cells,
            size: Size {
                width: pie_width.max(legend_x + legend_width).max(title_width),
                height: pie_height.max(legend_height),
            },
        }
    }
}

fn pie_cells(
    config: &PieLayoutConfig,
    center: Point,
    total: u64,
    cumulative: &[u64],
) -> Vec<PieCell> {
    if total == 0 || cumulative.is_empty() {
        return Vec::new();
    }
    let mut cells = Vec::new();
    let start_y = center.y - config.radius_y;
    let end_y = center.y + config.radius_y;
    let start_x = center.x - config.radius_x;
    let end_x = center.x + config.radius_x;
    for y in start_y..=end_y {
        for x in start_x..=end_x {
            let dx = f64::from(x - center.x) / f64::from(config.radius_x);
            let dy = f64::from(y - center.y) / f64::from(config.radius_y);
            if dx.mul_add(dx, dy * dy) > 1.0 {
                continue;
            }
            let mut angle = dx.atan2(-dy);
            if angle < 0.0 {
                angle += std::f64::consts::PI * 2.0;
            }
            let units_at_angle = ((angle / (std::f64::consts::PI * 2.0)) * total as f64) as u64;
            let slice_index = cumulative
                .iter()
                .position(|end| units_at_angle < *end)
                .unwrap_or(cumulative.len() - 1);
            cells.push(PieCell {
                point: Point { x, y },
                slice_index,
            });
        }
    }
    cells
}

fn pie_percent_basis_points(value: u64, total: u64) -> u16 {
    if total == 0 {
        return 0;
    }
    ((value.saturating_mul(10_000).saturating_add(total / 2)) / total) as u16
}

fn pie_legend_width(slice: &PositionedPieSlice, show_data: bool) -> i32 {
    let mut width = 2 + slice.label.chars().count() as i32;
    if show_data {
        width += 2
            + slice.value_text.chars().count() as i32
            + 3
            + pie_percent_label(slice.percent_basis_points)
                .chars()
                .count() as i32;
    }
    width
}

fn pie_percent_label(basis_points: u16) -> String {
    format!("{}.{:02}%", basis_points / 100, basis_points % 100)
}

impl MindmapLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: MindmapLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: MindmapLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &MindmapAst) -> MindmapLayout {
        let mut nodes = Vec::new();
        let mut edges = Vec::new();
        let mut next_y = 0;
        for root in &ast.roots {
            layout_mindmap_node(root, 0, &self.config, &mut next_y, &mut nodes, &mut edges);
            next_y += self.config.vertical_spacing;
        }
        let width = nodes
            .iter()
            .map(|node| node.rect.right())
            .max()
            .unwrap_or(1);
        let height = nodes
            .iter()
            .map(|node| node.rect.bottom())
            .max()
            .unwrap_or(1);
        MindmapLayout {
            nodes,
            edges,
            size: Size { width, height },
        }
    }
}

impl JourneyLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: JourneyLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: JourneyLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &JourneyAst) -> JourneyLayout {
        let mut sections = Vec::new();
        let mut tasks = Vec::new();
        let mut y = self.config.top_padding;
        let mut current_section = None::<String>;
        let bar_x = self.config.label_width;
        let score_x = bar_x + self.config.score_width + 1;
        let actors_x = score_x + self.config.score_label_width + self.config.actor_gap;

        for (index, task) in ast.tasks.iter().enumerate() {
            let section = task.section.as_ref().map(|section| section.text.clone());
            if section != current_section {
                if let Some(label) = &section {
                    sections.push(PositionedJourneySection {
                        label: label.clone(),
                        y,
                    });
                    y += 1 + self.config.section_gap;
                }
                current_section = section.clone();
            }

            tasks.push(PositionedJourneyTask {
                index,
                label: task.label.text.clone(),
                section,
                score: task.score.value,
                actors: task
                    .actors
                    .iter()
                    .map(|actor| actor.value.clone())
                    .collect(),
                label_origin: Point { x: 0, y },
                bar_rect: Rect {
                    origin: Point { x: bar_x, y },
                    size: Size {
                        width: self.config.score_width,
                        height: 1,
                    },
                },
                score_origin: Point { x: score_x, y },
                actors_origin: Point { x: actors_x, y },
            });
            y += self.config.row_height;
        }

        let title_width = ast
            .title
            .as_ref()
            .map_or(0, |title| title.text.chars().count() as i32);
        let section_width = sections
            .iter()
            .map(|section| section.label.chars().count() as i32)
            .max()
            .unwrap_or(0);
        let task_width = tasks
            .iter()
            .map(|task| journey_task_width(task, self.config))
            .max()
            .unwrap_or(0);

        JourneyLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            sections,
            tasks,
            size: Size {
                width: title_width.max(section_width).max(task_width).max(1),
                height: y.max(self.config.top_padding + 1),
            },
        }
    }
}

fn journey_task_width(task: &PositionedJourneyTask, config: JourneyLayoutConfig) -> i32 {
    let actor_width = journey_actor_text(task).chars().count() as i32;
    let label_width = task.label.chars().count() as i32;
    let score_end = task.score_origin.x + config.score_label_width;
    label_width
        .max(score_end)
        .max(task.actors_origin.x + actor_width)
}

fn journey_actor_text(task: &PositionedJourneyTask) -> String {
    task.actors.join(", ")
}

fn layout_mindmap_node(
    node: &MindmapNode,
    depth: usize,
    config: &MindmapLayoutConfig,
    next_y: &mut i32,
    nodes: &mut Vec<PositionedMindmapNode>,
    edges: &mut Vec<PositionedMindmapEdge>,
) -> (usize, i32) {
    let index = nodes.len();
    let width = mindmap_node_width(node, config);
    nodes.push(PositionedMindmapNode {
        id: index,
        label: node.label.text.clone(),
        shape: node.shape,
        icon: node.icon.as_ref().map(|icon| icon.value.clone()),
        classes: node
            .classes
            .iter()
            .map(|class| class.value.clone())
            .collect(),
        depth,
        rect: Rect {
            origin: Point { x: 0, y: 0 },
            size: Size {
                width,
                height: config.node_height,
            },
        },
    });
    let mut child_centers = Vec::new();
    let mut child_indices = Vec::new();
    for child in &node.children {
        let (child_index, child_center) =
            layout_mindmap_node(child, depth + 1, config, next_y, nodes, edges);
        child_indices.push(child_index);
        child_centers.push(child_center);
    }
    let center_y = if child_centers.is_empty() {
        let center = *next_y + config.node_height / 2;
        *next_y += config.node_height + config.vertical_spacing;
        center
    } else {
        child_centers.iter().sum::<i32>() / child_centers.len() as i32
    };
    let x = depth as i32 * (config.min_node_width + config.horizontal_spacing);
    nodes[index].rect = Rect {
        origin: Point {
            x,
            y: center_y - config.node_height / 2,
        },
        size: Size {
            width,
            height: config.node_height,
        },
    };
    for child_index in child_indices {
        edges.push(mindmap_edge(index, child_index, nodes));
    }
    (index, center_y)
}

fn mindmap_node_width(node: &MindmapNode, config: &MindmapLayoutConfig) -> i32 {
    let icon_width = node
        .icon
        .as_ref()
        .map_or(0, |icon| icon.value.chars().count() as i32 + 1);
    (node.label.text.chars().count() as i32 + icon_width + config.node_padding * 2)
        .max(config.min_node_width)
}

fn mindmap_edge(from: usize, to: usize, nodes: &[PositionedMindmapNode]) -> PositionedMindmapEdge {
    let from_rect = nodes[from].rect;
    let to_rect = nodes[to].rect;
    let start = Point {
        x: from_rect.right().saturating_sub(1),
        y: from_rect.center().y,
    };
    let end = Point {
        x: to_rect.origin.x,
        y: to_rect.center().y,
    };
    let mid_x = (start.x + end.x) / 2;
    PositionedMindmapEdge {
        from,
        to,
        points: vec![
            start,
            Point {
                x: mid_x,
                y: start.y,
            },
            Point { x: mid_x, y: end.y },
            end,
        ],
    }
}

fn er_cardinality_marker(cardinality: ErCardinality) -> ClassRelationshipMarker {
    match cardinality {
        ErCardinality::One => ClassRelationshipMarker::One,
        ErCardinality::ZeroOrOne => ClassRelationshipMarker::ZeroOrOne,
        ErCardinality::OneOrMany => ClassRelationshipMarker::Many,
        ErCardinality::ZeroOrMany => ClassRelationshipMarker::ZeroOrMany,
    }
}

fn route_class_relationship(
    from: Rect,
    to: Rect,
    direction: Direction,
    back_edge_below: bool,
) -> Vec<Point> {
    let routed_direction = class_route_direction(from, to, direction);
    let points = route_edge(from, to, routed_direction, back_edge_below);
    match (routed_direction, points.as_slice()) {
        (Direction::TopDown | Direction::BottomTop, [first, last]) if first.x != last.x => {
            let mid_y = (first.y + last.y) / 2;
            vec![
                *first,
                Point {
                    x: first.x,
                    y: mid_y,
                },
                Point {
                    x: last.x,
                    y: mid_y,
                },
                *last,
            ]
        }
        _ => points,
    }
}

fn class_route_direction(from: Rect, to: Rect, preferred: Direction) -> Direction {
    let from_center = from.center();
    let to_center = to.center();
    match preferred {
        Direction::TopDown if from_center.y > to_center.y => Direction::BottomTop,
        Direction::BottomTop if from_center.y < to_center.y => Direction::TopDown,
        Direction::LeftRight if from_center.x > to_center.x => Direction::RightLeft,
        Direction::RightLeft if from_center.x < to_center.x => Direction::LeftRight,
        _ => preferred,
    }
}

fn collect_state_statement(
    statement: &StateStatement,
    flow_statements: &mut Vec<FlowStatement>,
    composites: &mut Vec<PositionedStateComposite>,
) {
    match statement {
        StateStatement::State(state) => {
            flow_statements.push(FlowStatement::Node(state_to_flow_node(state)));
        }
        StateStatement::Transition(transition) => {
            flow_statements.push(FlowStatement::Edge(Box::new(state_transition_to_edge(
                transition,
            ))));
        }
        StateStatement::Composite(state) => {
            let mut child_ids = Vec::new();
            flow_statements.push(FlowStatement::Node(state_to_flow_node(state)));
            collect_state_children(state, flow_statements, composites, &mut child_ids);
            composites.push(PositionedStateComposite {
                id: state.id.value.clone(),
                child_ids,
            });
        }
        StateStatement::Direction(_)
        | StateStatement::ClassDef(_)
        | StateStatement::ClassApply(_)
        | StateStatement::Comment(_)
        | StateStatement::Directive(_) => {}
    }
}

fn collect_state_children(
    state: &StateNode,
    flow_statements: &mut Vec<FlowStatement>,
    composites: &mut Vec<PositionedStateComposite>,
    child_ids: &mut Vec<String>,
) {
    for child in &state.children {
        match child {
            StateStatement::State(child_state) | StateStatement::Composite(child_state) => {
                child_ids.push(child_state.id.value.clone());
            }
            StateStatement::Transition(transition) => {
                child_ids.push(transition.from.value.clone());
                child_ids.push(transition.to.value.clone());
            }
            StateStatement::ClassDef(_)
            | StateStatement::ClassApply(_)
            | StateStatement::Direction(_)
            | StateStatement::Comment(_)
            | StateStatement::Directive(_) => {}
        }
        collect_state_statement(child, flow_statements, composites);
    }
    child_ids.sort();
    child_ids.dedup();
}

fn state_to_flow_node(state: &StateNode) -> FlowNode {
    FlowNode {
        id: state.id.clone(),
        label: Some(state.label.clone().unwrap_or_else(|| Label {
            text: state.id.value.clone(),
            kind: LabelKind::Plain,
            span: state.id.span,
        })),
        shape: Spanned::new(FlowShape::Rectangle, state.span),
        span: state.span,
    }
}

fn state_transition_to_edge(transition: &StateTransition) -> FlowEdge {
    FlowEdge {
        from: state_endpoint_to_node(&transition.from),
        to: state_endpoint_to_node(&transition.to),
        link: Spanned::new(
            FlowEdgeLink {
                stroke: FlowEdgeStroke::Normal,
                arrow_start: ArrowHead::None,
                arrow_end: ArrowHead::Arrow,
                min_length: 1,
            },
            transition.span,
        ),
        label: transition.label.clone(),
        span: transition.span,
    }
}

fn state_endpoint_to_node(id: &Spanned<String>) -> FlowNode {
    FlowNode {
        id: id.clone(),
        label: Some(Label {
            text: id.value.clone(),
            kind: LabelKind::Plain,
            span: id.span,
        }),
        shape: Spanned::new(FlowShape::Rectangle, id.span),
        span: id.span,
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
    subgraphs: Vec<LayoutSubgraph>,
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
    arrow_start: ArrowHead,
    arrow_end: ArrowHead,
    min_length: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct LayoutSubgraph {
    id: String,
    label: String,
    child_ids: Vec<String>,
}

impl LayoutGraph {
    fn from_ast(ast: &FlowchartAst) -> Self {
        let mut graph = Self {
            nodes: Vec::new(),
            edges: Vec::new(),
            subgraphs: Vec::new(),
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

    fn from_class_ast(ast: &ClassAst) -> Self {
        let mut graph = Self {
            nodes: ast
                .classes
                .iter()
                .map(|class| LayoutNode {
                    id: class.id.value.clone(),
                    label: class.id.value.clone(),
                })
                .collect(),
            edges: Vec::new(),
            subgraphs: Vec::new(),
        };
        for relationship in &ast.relationships {
            let (from_id, to_id) = class_layout_edge_ids(relationship);
            let Some(from) = graph.node_index(from_id) else {
                continue;
            };
            let Some(to) = graph.node_index(to_id) else {
                continue;
            };
            graph.edges.push(LayoutGraphEdge {
                from,
                to,
                arrow_start: ArrowHead::None,
                arrow_end: ArrowHead::None,
                min_length: 1,
            });
        }
        graph
    }

    fn from_er_ast(ast: &ErAst) -> Self {
        let mut graph = Self {
            nodes: ast
                .entities
                .iter()
                .map(|entity| LayoutNode {
                    id: entity.id.value.clone(),
                    label: entity.id.value.clone(),
                })
                .collect(),
            edges: Vec::new(),
            subgraphs: Vec::new(),
        };
        for relationship in &ast.relationships {
            let Some(from) = graph.node_index(&relationship.from.value) else {
                continue;
            };
            let Some(to) = graph.node_index(&relationship.to.value) else {
                continue;
            };
            graph.edges.push(LayoutGraphEdge {
                from,
                to,
                arrow_start: ArrowHead::None,
                arrow_end: ArrowHead::None,
                min_length: 1,
            });
        }
        graph
    }

    fn node_index(&self, id: &str) -> Option<usize> {
        self.nodes.iter().position(|node| node.id == id)
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
        let mut child_ids = Vec::new();
        for statement in &subgraph.statements {
            collect_flow_child_ids(statement, &mut child_ids);
        }
        self.subgraphs.push(LayoutSubgraph {
            id: subgraph.id.value.clone(),
            label: subgraph
                .label
                .as_ref()
                .map_or_else(|| subgraph.id.value.clone(), |label| label.text.clone()),
            child_ids,
        });
    }

    fn add_edge(&mut self, edge: &FlowEdge) {
        let from = self.ensure_node(&edge.from);
        let to = self.ensure_node(&edge.to);
        self.edges.push(LayoutGraphEdge {
            from,
            to,
            arrow_start: edge.link.value.arrow_start,
            arrow_end: edge.link.value.arrow_end,
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

fn class_layout_edge_ids(relationship: &ClassRelationship) -> (&str, &str) {
    if matches!(
        relationship.end_marker,
        ClassRelationshipMarker::Inheritance
            | ClassRelationshipMarker::Aggregation
            | ClassRelationshipMarker::Composition
    ) {
        (&relationship.to.value, &relationship.from.value)
    } else {
        (&relationship.from.value, &relationship.to.value)
    }
}

fn collect_flow_child_ids(statement: &FlowStatement, child_ids: &mut Vec<String>) {
    match statement {
        FlowStatement::Node(node) => push_unique_id(child_ids, &node.id.value),
        FlowStatement::Edge(edge) => {
            push_unique_id(child_ids, &edge.from.id.value);
            push_unique_id(child_ids, &edge.to.id.value);
        }
        FlowStatement::Subgraph(subgraph) => {
            for statement in &subgraph.statements {
                collect_flow_child_ids(statement, child_ids);
            }
        }
        FlowStatement::ClassDef(_)
        | FlowStatement::ClassApply(_)
        | FlowStatement::Comment(_)
        | FlowStatement::Directive(_) => {}
    }
}

fn push_unique_id(ids: &mut Vec<String>, id: &str) {
    if !ids.iter().any(|value| value == id) {
        ids.push(id.to_owned());
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
    let mut layers = vec![usize::MAX; graph.nodes.len()];
    for (index, degree) in indegree.iter().copied().enumerate() {
        if degree == 0 {
            layers[index] = 0;
        }
    }
    let mut visited = 0usize;

    while let Some(index) = queue.pop_front() {
        visited += 1;
        for edge in &outgoing[index] {
            layers[edge.to] = layers[edge.to].min(layers[index] + edge.min_length);
            indegree[edge.to] -= 1;
            if indegree[edge.to] == 0 {
                queue.push_back(edge.to);
            }
        }
    }

    if visited != graph.nodes.len() {
        layers = assign_layers_with_cycle_breaks(graph);
    }
    layers
}

fn assign_layers_with_cycle_breaks(graph: &LayoutGraph) -> Vec<usize> {
    #[derive(Clone, Copy, PartialEq, Eq)]
    enum Visit {
        Unseen,
        Active,
        Done,
    }

    fn visit(index: usize, graph: &LayoutGraph, layers: &mut [usize], visits: &mut [Visit]) {
        visits[index] = Visit::Active;
        for edge in graph.edges.iter().filter(|edge| edge.from == index) {
            if visits[edge.to] == Visit::Unseen {
                layers[edge.to] = layers[edge.to].max(layers[index] + edge.min_length);
                visit(edge.to, graph, layers, visits);
            }
        }
        visits[index] = Visit::Done;
    }

    let mut layers = vec![0usize; graph.nodes.len()];
    let mut visits = vec![Visit::Unseen; graph.nodes.len()];
    for index in 0..graph.nodes.len() {
        if visits[index] == Visit::Unseen {
            visit(index, graph, &mut layers, &mut visits);
        }
    }
    layers
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
                .unwrap_or((order[*index], 0, 0))
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
            let max_layer = layers.iter().copied().max().unwrap_or(0);
            let mut layer_widths = vec![0i32; max_layer + 1];
            for (index, layer) in layers.iter().copied().enumerate() {
                layer_widths[layer] = layer_widths[layer].max(rects[index].size.width);
            }
            let mut layer_offsets = vec![0i32; max_layer + 1];
            let mut next_x = 0i32;
            for (layer, width) in layer_widths.iter().copied().enumerate() {
                layer_offsets[layer] = next_x;
                next_x += width + config.horizontal_spacing;
            }
            for (index, rect) in rects.iter_mut().enumerate() {
                let y = rect.origin.x;
                rect.origin = Point {
                    x: layer_offsets[layers[index]],
                    y,
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

    let subgraphs = position_subgraphs(graph, &mut rects);
    size = layout_size(&rects);
    size = layout_size_with_subgraphs(size, &subgraphs);

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
            arrow_start: edge.arrow_start,
            arrow_end: edge.arrow_end,
            points: route_edge(
                rects[edge.from],
                rects[edge.to],
                direction,
                closes_existing_path(graph, edge.to, edge.from, (edge.from, edge.to)),
            ),
        })
        .collect::<Vec<_>>();
    size = layout_size_with_edges(size, &edges);

    FlowLayout {
        direction,
        nodes,
        edges,
        subgraphs,
        size,
    }
}

fn position_subgraphs(graph: &LayoutGraph, rects: &mut [Rect]) -> Vec<PositionedFlowSubgraph> {
    graph
        .subgraphs
        .iter()
        .filter_map(|subgraph| {
            let indexes = subgraph
                .child_ids
                .iter()
                .filter_map(|id| graph.nodes.iter().position(|node| &node.id == id))
                .collect::<Vec<_>>();
            let bounds = bounding_rect(indexes.iter().map(|index| rects[*index]))?;
            for index in indexes {
                rects[index].origin.x += 2;
                rects[index].origin.y += 4;
            }
            Some(PositionedFlowSubgraph {
                id: subgraph.id.clone(),
                label: subgraph.label.clone(),
                rect: Rect {
                    origin: bounds.origin,
                    size: Size {
                        width: bounds.size.width + 4,
                        height: bounds.size.height + 6,
                    },
                },
                child_ids: subgraph.child_ids.clone(),
            })
        })
        .collect()
}

fn bounding_rect(rects: impl IntoIterator<Item = Rect>) -> Option<Rect> {
    let mut rects = rects.into_iter();
    let first = rects.next()?;
    let (mut left, mut top, mut right, mut bottom) = (
        first.origin.x,
        first.origin.y,
        first.right(),
        first.bottom(),
    );
    for rect in rects {
        left = left.min(rect.origin.x);
        top = top.min(rect.origin.y);
        right = right.max(rect.right());
        bottom = bottom.max(rect.bottom());
    }
    Some(Rect {
        origin: Point { x: left, y: top },
        size: Size {
            width: right - left,
            height: bottom - top,
        },
    })
}

fn closes_existing_path(
    graph: &LayoutGraph,
    start: usize,
    goal: usize,
    skip: (usize, usize),
) -> bool {
    let mut stack = vec![start];
    let mut seen = vec![false; graph.nodes.len()];
    while let Some(index) = stack.pop() {
        if index == goal {
            return true;
        }
        if seen[index] {
            continue;
        }
        seen[index] = true;
        for edge in &graph.edges {
            if (edge.from, edge.to) != skip && edge.from == index {
                stack.push(edge.to);
            }
        }
    }
    false
}

fn route_edge(from: Rect, to: Rect, direction: Direction, back_edge_below: bool) -> Vec<Point> {
    let from_center = from.center();
    let to_center = to.center();
    match direction {
        Direction::TopDown => vec![
            Point {
                x: from_center.x,
                y: from.bottom(),
            },
            Point {
                x: to_center.x,
                y: to.origin.y - 1,
            },
        ],
        Direction::BottomTop => vec![
            Point {
                x: from_center.x,
                y: from.origin.y - 1,
            },
            Point {
                x: to_center.x,
                y: to.bottom(),
            },
        ],
        Direction::LeftRight if from == to => horizontal_self_edge(from),
        Direction::LeftRight if from.origin.x == to.origin.x && from_center.y != to_center.y => {
            vertical_same_layer_edge(from, to)
        }
        Direction::LeftRight if to.origin.x < from.origin.x && back_edge_below => {
            let y = from.bottom().max(to.bottom()) + 1;
            vec![
                Point {
                    x: from_center.x,
                    y: from.bottom(),
                },
                Point {
                    x: from_center.x,
                    y,
                },
                Point { x: to_center.x, y },
                Point {
                    x: to_center.x,
                    y: to.bottom(),
                },
            ]
        }
        Direction::LeftRight if to.origin.x < from.origin.x => vec![
            Point {
                x: from.origin.x - 1,
                y: from_center.y,
            },
            Point {
                x: (from.origin.x + to.right()) / 2,
                y: from_center.y,
            },
            Point {
                x: to.right(),
                y: to_center.y,
            },
        ],
        Direction::LeftRight if from_center.y == to_center.y => vec![
            Point {
                x: from.right(),
                y: from_center.y,
            },
            Point {
                x: to.origin.x - 1,
                y: to_center.y,
            },
        ],
        Direction::LeftRight if to_center.y > from_center.y => {
            lower_target_edge(from, to, to.origin.x - 1)
        }
        Direction::LeftRight => upper_target_edge(from, to, from.right()),
        Direction::RightLeft if from == to => horizontal_self_edge(from),
        Direction::RightLeft if from.origin.x == to.origin.x && from_center.y != to_center.y => {
            vertical_same_layer_edge(from, to)
        }
        Direction::RightLeft if to.origin.x > from.origin.x && back_edge_below => {
            let y = from.bottom().max(to.bottom()) + 1;
            vec![
                Point {
                    x: from_center.x,
                    y: from.bottom(),
                },
                Point {
                    x: from_center.x,
                    y,
                },
                Point { x: to_center.x, y },
                Point {
                    x: to_center.x,
                    y: to.bottom(),
                },
            ]
        }
        Direction::RightLeft if to.origin.x > from.origin.x => vec![
            Point {
                x: from.right(),
                y: from_center.y,
            },
            Point {
                x: (from.right() + to.origin.x) / 2,
                y: from_center.y,
            },
            Point {
                x: to.origin.x - 1,
                y: to_center.y,
            },
        ],
        Direction::RightLeft if from_center.y == to_center.y => vec![
            Point {
                x: from.origin.x - 1,
                y: from_center.y,
            },
            Point {
                x: to.right(),
                y: to_center.y,
            },
        ],
        Direction::RightLeft if to_center.y > from_center.y => {
            lower_target_edge(from, to, to.right())
        }
        Direction::RightLeft => upper_target_edge(from, to, from.origin.x - 1),
    }
}

fn vertical_exit_y(from: Rect, to_center: Point) -> i32 {
    if to_center.y >= from.center().y {
        from.bottom()
    } else {
        from.origin.y - 1
    }
}

fn lower_target_edge(from: Rect, to: Rect, target_x: i32) -> Vec<Point> {
    let from_center = from.center();
    let to_center = to.center();
    vec![
        Point {
            x: from_center.x,
            y: vertical_exit_y(from, to_center),
        },
        Point {
            x: from_center.x,
            y: to_center.y,
        },
        Point {
            x: target_x,
            y: to_center.y,
        },
    ]
}

fn upper_target_edge(from: Rect, to: Rect, exit_x: i32) -> Vec<Point> {
    let from_center = from.center();
    let to_center = to.center();
    vec![
        Point {
            x: exit_x,
            y: from_center.y,
        },
        Point {
            x: to_center.x,
            y: from_center.y,
        },
        Point {
            x: to_center.x,
            y: to.bottom(),
        },
    ]
}

fn vertical_same_layer_edge(from: Rect, to: Rect) -> Vec<Point> {
    let from_center = from.center();
    let to_center = to.center();
    if to_center.y >= from_center.y {
        vec![
            Point {
                x: from_center.x,
                y: from.bottom(),
            },
            Point {
                x: to_center.x,
                y: to.origin.y - 1,
            },
        ]
    } else {
        vec![
            Point {
                x: from_center.x,
                y: from.origin.y - 1,
            },
            Point {
                x: to_center.x,
                y: to.bottom(),
            },
        ]
    }
}

fn horizontal_self_edge(rect: Rect) -> Vec<Point> {
    let center = rect.center();
    let loop_x = rect.right() + 2;
    let loop_y = rect.bottom() + 2;
    vec![
        Point {
            x: loop_x,
            y: center.y,
        },
        Point {
            x: loop_x,
            y: loop_y,
        },
        Point {
            x: center.x,
            y: loop_y,
        },
        Point {
            x: center.x,
            y: rect.bottom(),
        },
    ]
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

fn class_node_size(class: &ClassNode, config: ClassLayoutConfig) -> Size {
    let fields = class_member_lines(class, ClassMemberKind::Field);
    let methods = class_member_lines(class, ClassMemberKind::Method);
    let title_height = class.annotations.len() as i32 + 1;
    let field_height = if methods.is_empty() {
        fields.len() as i32
    } else {
        fields.len().max(1) as i32
    };
    let method_height = methods.len() as i32;
    let separators = if fields.is_empty() && methods.is_empty() {
        2
    } else if methods.is_empty() {
        3
    } else {
        4
    };
    let width = std::iter::once(class.id.value.as_str())
        .chain(
            class
                .annotations
                .iter()
                .map(|annotation| annotation.text.as_str()),
        )
        .chain(fields.iter().map(String::as_str))
        .chain(methods.iter().map(String::as_str))
        .map(|line| line.chars().count() as i32 + config.horizontal_padding)
        .max()
        .unwrap_or(config.min_node_width)
        .max(config.min_node_width);
    Size {
        width,
        height: title_height + field_height + method_height + separators,
    }
}

fn class_member_lines(class: &ClassNode, kind: ClassMemberKind) -> Vec<String> {
    class
        .members
        .iter()
        .filter(|member| member.kind == kind)
        .map(class_member_line)
        .collect()
}

fn class_member_line(member: &ClassMember) -> String {
    let mut line = String::new();
    if let Some(visibility) = member.visibility {
        line.push(visibility);
    }
    line.push_str(&member.name.value);
    match (&member.ty, member.kind) {
        (Some(ty), _) => {
            line.push_str(": ");
            line.push_str(&ty.text);
        }
        (None, ClassMemberKind::Method) => line.push_str("()"),
        (None, ClassMemberKind::Field) => {}
    }
    line
}

fn er_entity_size(entity: &ErEntity, config: ClassLayoutConfig) -> Size {
    let attributes = er_attribute_lines(entity);
    let width = std::iter::once(entity.id.value.as_str())
        .chain(attributes.iter().map(String::as_str))
        .map(|line| line.chars().count() as i32 + config.horizontal_padding)
        .max()
        .unwrap_or(config.min_node_width)
        .max(config.min_node_width);
    Size {
        width,
        height: attributes.len() as i32 + 3,
    }
}

fn er_attribute_lines(entity: &ErEntity) -> Vec<String> {
    entity.attributes.iter().map(er_attribute_line).collect()
}

fn er_attribute_line(attribute: &ErAttribute) -> String {
    let mut line = String::new();
    if let Some(key) = &attribute.key {
        line.push_str(&key.value);
        line.push(' ');
    }
    line.push_str(&attribute.ty.value);
    line.push(' ');
    line.push_str(&attribute.name.value);
    line
}

fn transform_rects_for_direction(
    rects: &mut [Rect],
    layers: &[usize],
    direction: Direction,
    config: FlowLayoutConfig,
) {
    let size = layout_size(rects);
    match direction {
        Direction::TopDown => {}
        Direction::BottomTop => {
            for rect in rects {
                rect.origin.y = size.height - rect.bottom();
            }
        }
        Direction::LeftRight | Direction::RightLeft => {
            let max_layer = layers.iter().copied().max().unwrap_or(0);
            let mut layer_widths = vec![0i32; max_layer + 1];
            for (index, layer) in layers.iter().copied().enumerate() {
                layer_widths[layer] = layer_widths[layer].max(rects[index].size.width);
            }
            let mut layer_offsets = vec![0i32; max_layer + 1];
            let mut next_x = 0i32;
            for (layer, width) in layer_widths.iter().copied().enumerate() {
                layer_offsets[layer] = next_x;
                next_x += width + config.horizontal_spacing;
            }
            for (index, rect) in rects.iter_mut().enumerate() {
                let y = rect.origin.x;
                rect.origin = Point {
                    x: layer_offsets[layers[index]],
                    y,
                };
            }
            if direction == Direction::RightLeft {
                let size = layout_size(rects);
                for rect in rects {
                    rect.origin.x = size.width - rect.right();
                }
            }
        }
    }
}

fn layout_size(rects: &[Rect]) -> Size {
    Size {
        width: rects.iter().map(|rect| rect.right()).max().unwrap_or(0),
        height: rects.iter().map(|rect| rect.bottom()).max().unwrap_or(0),
    }
}

fn layout_size_with_edges(size: Size, edges: &[PositionedFlowEdge]) -> Size {
    Size {
        width: edges
            .iter()
            .flat_map(|edge| edge.points.iter().map(|point| point.x + 1))
            .fold(size.width, i32::max),
        height: edges
            .iter()
            .flat_map(|edge| edge.points.iter().map(|point| point.y + 1))
            .fold(size.height, i32::max),
    }
}

fn layout_size_with_class_relationships(
    size: Size,
    relationships: &[PositionedClassRelationship],
) -> Size {
    Size {
        width: relationships
            .iter()
            .flat_map(|relationship| relationship.points.iter().map(|point| point.x + 1))
            .fold(size.width, i32::max),
        height: relationships
            .iter()
            .flat_map(|relationship| relationship.points.iter().map(|point| point.y + 1))
            .fold(size.height, i32::max),
    }
}

fn layout_size_with_subgraphs(size: Size, subgraphs: &[PositionedFlowSubgraph]) -> Size {
    Size {
        width: subgraphs
            .iter()
            .map(|subgraph| subgraph.rect.right())
            .fold(size.width, i32::max),
        height: subgraphs
            .iter()
            .map(|subgraph| subgraph.rect.bottom())
            .fold(size.height, i32::max),
    }
}

#[cfg(test)]
mod tests {
    use super::{FlowLayoutEngine, Point, SequenceLayoutEngine, StateLayoutEngine};
    use crate::ast::{ArrowHead, FlowShape, FlowchartAst};
    use crate::ast::{
        Direction, FlowEdge, FlowEdgeLink, FlowEdgeStroke, FlowNode, FlowStatement, FlowSubgraph,
        FlowchartDirective, FlowchartHeader, Label, LabelKind, SequenceArrow, SequenceAst,
        SequenceControlBlock, SequenceControlKind, SequenceHeader, SequenceMessage, SequenceNote,
        SequenceNotePlacement, SequenceParticipant, SequenceParticipantKind, SequenceStatement,
        Span, Spanned, StateAst, StateDirective, StateHeader, StateNode, StateNodeKind,
        StateStatement, StateTransition,
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
    fn preserves_node_widths_in_left_right_layouts() {
        let ast = flowchart(
            Direction::LeftRight,
            vec![FlowStatement::Edge(Box::new(edge(
                "LongerName1",
                "LongerName2",
            )))],
        );

        let layout = FlowLayoutEngine::default().layout(&ast);

        assert!(node(&layout, "LongerName1").rect.size.width >= 11);
        assert!(node(&layout, "LongerName2").rect.size.width >= 11);
        assert_eq!(node(&layout, "LongerName1").rect.size.height, 5);
    }

    #[test]
    fn routes_left_right_staggered_edges_from_source_side() {
        let ast = flowchart(
            Direction::LeftRight,
            vec![
                FlowStatement::Edge(Box::new(edge("A", "B"))),
                FlowStatement::Edge(Box::new(edge("A", "C"))),
            ],
        );

        let layout = FlowLayoutEngine::default().layout(&ast);
        let source = node(&layout, "A").rect;
        let target = node(&layout, "C").rect;
        let edge = layout.edges.iter().find(|edge| edge.to == "C").unwrap();

        assert_eq!(
            edge.points,
            vec![
                Point {
                    x: source.center().x,
                    y: source.bottom(),
                },
                Point {
                    x: source.center().x,
                    y: target.center().y,
                },
                Point {
                    x: target.origin.x - 1,
                    y: target.center().y,
                },
            ]
        );
    }

    #[test]
    fn keeps_shortcut_targets_on_nearest_layer() {
        let ast = flowchart(
            Direction::LeftRight,
            vec![
                FlowStatement::Edge(Box::new(edge("A", "B"))),
                FlowStatement::Edge(Box::new(edge("B", "C"))),
                FlowStatement::Edge(Box::new(edge("A", "C"))),
            ],
        );

        let layout = FlowLayoutEngine::default().layout(&ast);

        assert_eq!(
            node(&layout, "B").rect.origin.x,
            node(&layout, "C").rect.origin.x
        );
        assert!(node(&layout, "B").rect.origin.y < node(&layout, "C").rect.origin.y);
    }

    #[test]
    fn routes_left_right_back_edges_below_nodes() {
        let ast = flowchart(
            Direction::LeftRight,
            vec![
                FlowStatement::Edge(Box::new(edge("A", "B"))),
                FlowStatement::Edge(Box::new(edge("B", "C"))),
                FlowStatement::Edge(Box::new(edge("C", "A"))),
            ],
        );

        let layout = FlowLayoutEngine::default().layout(&ast);
        let a = node(&layout, "A").rect;
        let b = node(&layout, "B").rect;
        let c = node(&layout, "C").rect;
        let edge = layout.edges.iter().find(|edge| edge.to == "A").unwrap();

        assert!(a.origin.x < b.origin.x);
        assert!(b.origin.x < c.origin.x);
        assert!(edge.points.iter().any(|point| point.y > c.bottom()));
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
        assert_eq!(layout.subgraphs.len(), 1);
        assert_eq!(layout.subgraphs[0].label, "group");
        assert_eq!(layout.subgraphs[0].rect.size.width, 9);
        assert_eq!(layout.subgraphs[0].rect.size.height, 21);
    }

    #[test]
    fn carries_flow_edge_arrowheads() {
        let mut edge = edge("A", "B");
        edge.link.value.arrow_start = ArrowHead::Cross;
        edge.link.value.arrow_end = ArrowHead::Circle;
        let ast = flowchart(
            Direction::TopDown,
            vec![FlowStatement::Edge(Box::new(edge))],
        );

        let layout = FlowLayoutEngine::default().layout(&ast);

        assert_eq!(layout.edges[0].arrow_start, ArrowHead::Cross);
        assert_eq!(layout.edges[0].arrow_end, ArrowHead::Circle);
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

        assert_eq!(center, Point { x: 2, y: 2 });
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

    #[test]
    fn lays_out_state_transitions_with_flow_engine() {
        let ast = state(
            Direction::TopDown,
            vec![StateStatement::Transition(Box::new(state_transition(
                "[*]", "Idle", "boot",
            )))],
        );

        let layout = StateLayoutEngine::default().layout(&ast);

        assert_eq!(layout.graph.nodes.len(), 2);
        assert_eq!(layout.graph.edges.len(), 1);
        assert!(
            flow_node(&layout.graph, "[*]").rect.origin.y
                < flow_node(&layout.graph, "Idle").rect.origin.y
        );
    }

    #[test]
    fn state_layout_uses_requested_direction() {
        let ast = state(
            Direction::LeftRight,
            vec![StateStatement::Transition(Box::new(state_transition(
                "Idle", "Active", "start",
            )))],
        );

        let layout = StateLayoutEngine::default().layout(&ast);

        assert_eq!(layout.graph.direction, Direction::LeftRight);
        assert!(
            flow_node(&layout.graph, "Idle").rect.origin.x
                < flow_node(&layout.graph, "Active").rect.origin.x
        );
    }

    #[test]
    fn state_layout_recurses_composite_children() {
        let composite = StateNode {
            id: Spanned::new("Composite".to_owned(), Span::new(0, 0)),
            label: None,
            kind: StateNodeKind::Default,
            descriptions: Vec::new(),
            note: None,
            children: vec![
                StateStatement::State(Box::new(state_node("A"))),
                StateStatement::Transition(Box::new(state_transition("A", "B", "next"))),
            ],
            span: Span::new(0, 0),
        };
        let ast = state(
            Direction::TopDown,
            vec![StateStatement::Composite(Box::new(composite))],
        );

        let layout = StateLayoutEngine::default().layout(&ast);

        assert!(layout.graph.nodes.iter().any(|node| node.id == "Composite"));
        assert!(layout.graph.nodes.iter().any(|node| node.id == "A"));
        assert!(layout.graph.nodes.iter().any(|node| node.id == "B"));
        assert_eq!(layout.composites[0].id, "Composite");
        assert_eq!(layout.composites[0].child_ids, vec!["A", "B"]);
    }

    fn state(direction: Direction, statements: Vec<StateStatement>) -> StateAst {
        StateAst {
            header: StateHeader {
                directive: StateDirective::StateDiagramV2,
                span: Span::new(0, 15),
            },
            direction: Some(Spanned::new(direction, Span::new(0, 0))),
            statements,
            states: Vec::new(),
            transitions: Vec::new(),
            classes: Vec::new(),
            span: Span::new(0, 0),
        }
    }

    fn state_node(id: &str) -> StateNode {
        StateNode {
            id: Spanned::new(id.to_owned(), Span::new(0, 0)),
            label: None,
            kind: StateNodeKind::Default,
            descriptions: Vec::new(),
            note: None,
            children: Vec::new(),
            span: Span::new(0, 0),
        }
    }

    fn state_transition(from: &str, to: &str, text: &str) -> StateTransition {
        StateTransition {
            from: Spanned::new(from.to_owned(), Span::new(0, 0)),
            to: Spanned::new(to.to_owned(), Span::new(0, 0)),
            label: Some(label(text)),
            span: Span::new(0, 0),
        }
    }

    fn flow_node<'layout>(
        layout: &'layout super::FlowLayout,
        id: &str,
    ) -> &'layout super::PositionedFlowNode {
        layout
            .nodes
            .iter()
            .find(|node| node.id == id)
            .unwrap_or_else(|| panic!("missing flow node {id}"))
    }
}
