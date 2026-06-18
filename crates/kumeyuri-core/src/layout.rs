use crate::ast::{
    ArchitectureAlignAxis, ArchitectureAst, ArchitectureEdge, ArchitectureGroup,
    ArchitectureJunction, ArchitectureService, ArchitectureSide, ArrowHead, BlockDiagramAst,
    BlockShape, BlockStatement, C4Ast, C4Boundary, C4BoundaryKind, C4CallArg, C4Element,
    C4ElementKind, C4Relationship, C4RelationshipKind, C4Statement, ClassAst, ClassMember,
    ClassMemberKind, ClassNode, ClassRelationship, ClassRelationshipLine, ClassRelationshipMarker,
    Direction, ErAst, ErAttribute, ErCardinality, ErEntity, EventModelingAst,
    EventModelingDataBlock, EventModelingEntityType, EventModelingFrameKind, FlowEdge,
    FlowEdgeLink, FlowEdgeStroke, FlowNode, FlowShape, FlowStatement, FlowSubgraph, FlowchartAst,
    FlowchartDirective, FlowchartHeader, GanttAst, GanttStatement, GanttTask, GanttTaskTag,
    GitGraphAst, GitGraphCommit, GitGraphCommitKind, GitGraphOrientation, GitGraphStatement,
    IshikawaAst, IshikawaNode, JourneyAst, KanbanAst, KanbanColumn, KanbanMetadata, Label,
    LabelKind, MindmapAst, MindmapNode, MindmapShape, PacketAst, PieAst, PieLegendPosition,
    QuadrantAst, RadarAst, RadarCurve, RadarOptionKind, RequirementAst, RequirementElement,
    RequirementKind, RequirementNode, RequirementRelationshipKind, RequirementRisk,
    RequirementVerifyMethod, SankeyAst, SequenceActivation, SequenceAst, SequenceAutoNumber,
    SequenceBox, SequenceControlKind, SequenceMessage, SequenceNote, SequenceParticipant,
    SequenceStatement, Spanned, StateAst, StateNode, StateStatement, StateTransition, TimelineAst,
    TreeViewAst, TreeViewNode, TreemapAst, TreemapNode, VennAst, VennSet, VennStyle, VennText,
    VennUnion, WardleyAst, WardleyComponentKind, WardleyDecorator, WardleyForceKind,
    WardleyLinkKind, XyChartAst, XyChartAxisScale, XyChartSeriesKind, ZenUmlAst,
    ZenUmlFragmentKind, ZenUmlMessageKind, ZenUmlStatement,
};
use std::collections::{HashMap, HashSet, VecDeque};

pub mod optimise {
    use std::cmp::Ordering;

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct LayeredEdge {
        pub from: usize,
        pub to: usize,
    }

    impl LayeredEdge {
        #[must_use]
        pub const fn new(from: usize, to: usize) -> Self {
            Self { from, to }
        }
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct CrossingMinimisationConfig {
        pub sweeps: usize,
    }

    impl Default for CrossingMinimisationConfig {
        fn default() -> Self {
            Self::default_values()
        }
    }

    impl CrossingMinimisationConfig {
        #[must_use]
        pub const fn default_values() -> Self {
            Self { sweeps: 4 }
        }
    }

    #[must_use]
    pub fn minimise_crossings(layers: &[usize], edges: &[LayeredEdge]) -> Vec<usize> {
        minimise_crossings_with_config(layers, edges, CrossingMinimisationConfig::default_values())
    }

    #[must_use]
    pub fn minimise_crossings_with_config(
        layers: &[usize],
        edges: &[LayeredEdge],
        config: CrossingMinimisationConfig,
    ) -> Vec<usize> {
        validate_edges(layers, edges);
        let mut order = initial_order(layers);
        for _ in 0..config.sweeps {
            sweep(edges, layers, &mut order, true);
            sweep(edges, layers, &mut order, false);
        }
        order
    }

    #[must_use]
    pub fn count_crossings(layers: &[usize], order: &[usize], edges: &[LayeredEdge]) -> usize {
        assert_eq!(layers.len(), order.len(), "order length must match layers");
        validate_edges(layers, edges);
        let mut count = 0usize;
        for left_index in 0..edges.len() {
            let Some(left) = normalised_edge(layers, edges[left_index]) else {
                continue;
            };
            for right_edge in edges.iter().skip(left_index + 1) {
                let Some(right) = normalised_edge(layers, *right_edge) else {
                    continue;
                };
                if left.from_layer != right.from_layer || left.to_layer != right.to_layer {
                    continue;
                }
                if left.from == right.from || left.to == right.to {
                    continue;
                }
                let left_from_order = order[left.from];
                let right_from_order = order[right.from];
                let left_to_order = order[left.to];
                let right_to_order = order[right.to];
                if (left_from_order < right_from_order && left_to_order > right_to_order)
                    || (left_from_order > right_from_order && left_to_order < right_to_order)
                {
                    count += 1;
                }
            }
        }
        count
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    struct NormalisedEdge {
        from: usize,
        to: usize,
        from_layer: usize,
        to_layer: usize,
    }

    fn validate_edges(layers: &[usize], edges: &[LayeredEdge]) {
        for edge in edges {
            assert!(edge.from < layers.len(), "edge source index out of range");
            assert!(edge.to < layers.len(), "edge target index out of range");
        }
    }

    fn normalised_edge(layers: &[usize], edge: LayeredEdge) -> Option<NormalisedEdge> {
        let from_layer = layers[edge.from];
        let to_layer = layers[edge.to];
        match from_layer.cmp(&to_layer) {
            Ordering::Less => Some(NormalisedEdge {
                from: edge.from,
                to: edge.to,
                from_layer,
                to_layer,
            }),
            Ordering::Greater => Some(NormalisedEdge {
                from: edge.to,
                to: edge.from,
                from_layer: to_layer,
                to_layer: from_layer,
            }),
            Ordering::Equal => None,
        }
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

    fn sweep(edges: &[LayeredEdge], layers: &[usize], order: &mut [usize], forward: bool) {
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
            nodes.sort_by_key(|index| order[*index]);
            nodes.sort_by(|left, right| {
                compare_positions(
                    barycenter(edges, layers, order, *left, forward).unwrap_or((order[*left], 1)),
                    barycenter(edges, layers, order, *right, forward).unwrap_or((order[*right], 1)),
                )
                .then_with(|| order[*left].cmp(&order[*right]))
            });
            for (next_order, index) in nodes.into_iter().enumerate() {
                order[index] = next_order;
            }
        }
    }

    fn compare_positions(left: (usize, usize), right: (usize, usize)) -> Ordering {
        ((left.0 as u128) * (right.1 as u128)).cmp(&((right.0 as u128) * (left.1 as u128)))
    }

    fn barycenter(
        edges: &[LayeredEdge],
        layers: &[usize],
        order: &[usize],
        index: usize,
        forward: bool,
    ) -> Option<(usize, usize)> {
        let mut sum = 0usize;
        let mut count = 0usize;
        for edge in edges {
            if forward && edge.to == index && layers[edge.from] < layers[index] {
                sum += order[edge.from];
                count += 1;
            } else if !forward && edge.from == index && layers[edge.to] > layers[index] {
                sum += order[edge.to];
                count += 1;
            }
        }
        (count > 0).then_some((sum, count))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Layout;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FlowLayoutConfig {
    pub horizontal_spacing: i32,
    pub vertical_spacing: i32,
    pub horizontal_padding: i32,
    pub min_node_width: i32,
    pub node_height: i32,
    pub max_label_width: Option<i32>,
}

impl Default for FlowLayoutConfig {
    fn default() -> Self {
        Self {
            horizontal_spacing: 5,
            vertical_spacing: 5,
            horizontal_padding: 4,
            min_node_width: 5,
            node_height: 5,
            max_label_width: None,
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
    pub shape: FlowShape,
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
    pub number: Option<String>,
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
    pub kind: SequenceControlKind,
    pub label: Option<String>,
    pub rect: Rect,
    pub y: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedSequenceBox {
    pub label: Option<String>,
    pub participants: Vec<String>,
    pub rect: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedSequenceActivation {
    pub participant: String,
    pub rect: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedSequenceDestroy {
    pub participant: String,
    pub point: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceLayout {
    pub participants: Vec<PositionedSequenceParticipant>,
    pub boxes: Vec<PositionedSequenceBox>,
    pub messages: Vec<PositionedSequenceMessage>,
    pub notes: Vec<PositionedSequenceNote>,
    pub controls: Vec<PositionedSequenceControl>,
    pub activations: Vec<PositionedSequenceActivation>,
    pub destroys: Vec<PositionedSequenceDestroy>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ZenUmlLayoutConfig {
    pub lane_spacing: i32,
    pub participant_width: i32,
    pub participant_height: i32,
    pub event_spacing: i32,
    pub top_padding: i32,
}

impl Default for ZenUmlLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl ZenUmlLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            lane_spacing: 14,
            participant_width: 11,
            participant_height: 4,
            event_spacing: 3,
            top_padding: 2,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedZenUmlParticipant {
    pub id: String,
    pub label: String,
    pub annotator: Option<String>,
    pub lane_x: i32,
    pub header: Rect,
    pub order: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedZenUmlMessage {
    pub from: Option<String>,
    pub to: String,
    pub label: String,
    pub kind: ZenUmlMessageKind,
    pub depth: u16,
    pub y: i32,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedZenUmlFragment {
    pub label: String,
    pub depth: u16,
    pub y: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZenUmlLayout {
    pub title: Option<String>,
    pub participants: Vec<PositionedZenUmlParticipant>,
    pub messages: Vec<PositionedZenUmlMessage>,
    pub fragments: Vec<PositionedZenUmlFragment>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SankeyLayoutConfig {
    pub horizontal_spacing: i32,
    pub vertical_spacing: i32,
    pub horizontal_padding: i32,
    pub min_node_width: i32,
    pub node_height: i32,
}

impl Default for SankeyLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl SankeyLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            horizontal_spacing: 16,
            vertical_spacing: 4,
            horizontal_padding: 2,
            min_node_width: 9,
            node_height: 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedSankeyNode {
    pub id: String,
    pub label: String,
    pub rect: Rect,
    pub layer: usize,
    pub order: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedSankeyLink {
    pub source: String,
    pub target: String,
    pub value_text: String,
    pub value_units: u64,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SankeyLayout {
    pub nodes: Vec<PositionedSankeyNode>,
    pub links: Vec<PositionedSankeyLink>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct XyChartLayoutConfig {
    pub plot_width: i32,
    pub plot_height: i32,
    pub left_margin: i32,
    pub top_padding: i32,
}

impl Default for XyChartLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl XyChartLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            plot_width: 60,
            plot_height: 18,
            left_margin: 10,
            top_padding: 1,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedXyChartSeries {
    pub kind: XyChartSeriesKind,
    pub points: Vec<Point>,
    pub value_texts: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XyChartLayout {
    pub title: Option<String>,
    pub x_title: Option<String>,
    pub y_title: Option<String>,
    pub x_labels: Vec<String>,
    pub y_min_label: String,
    pub y_max_label: String,
    pub plot: Rect,
    pub series: Vec<PositionedXyChartSeries>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BlockLayoutConfig {
    pub horizontal_spacing: i32,
    pub vertical_spacing: i32,
    pub horizontal_padding: i32,
    pub min_node_width: i32,
    pub node_height: i32,
    pub container_padding: i32,
    pub default_columns: u16,
}

impl Default for BlockLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl BlockLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            horizontal_spacing: 4,
            vertical_spacing: 2,
            horizontal_padding: 2,
            min_node_width: 7,
            node_height: 3,
            container_padding: 2,
            default_columns: 16,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedBlockNode {
    pub id: String,
    pub label: String,
    pub shape: BlockShape,
    pub rect: Rect,
    pub row: usize,
    pub column: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedBlockContainer {
    pub id: Option<String>,
    pub label: String,
    pub rect: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedBlockEdge {
    pub from: String,
    pub to: String,
    pub label: Option<String>,
    pub arrow_start: ArrowHead,
    pub arrow_end: ArrowHead,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockLayout {
    pub nodes: Vec<PositionedBlockNode>,
    pub containers: Vec<PositionedBlockContainer>,
    pub edges: Vec<PositionedBlockEdge>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PacketLayoutConfig {
    pub bits_per_row: u32,
    pub bit_width: i32,
    pub row_height: i32,
    pub row_spacing: i32,
    pub title_spacing: i32,
}

impl Default for PacketLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl PacketLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            bits_per_row: 32,
            bit_width: 5,
            row_height: 3,
            row_spacing: 2,
            title_spacing: 2,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedPacketField {
    pub label: String,
    pub range_label: String,
    pub start_bit: u32,
    pub end_bit: u32,
    pub row: u32,
    pub rect: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedPacketRow {
    pub row: u32,
    pub first_bit: u32,
    pub last_bit: u32,
    pub label_y: i32,
    pub rect_y: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PacketLayout {
    pub title: Option<String>,
    pub rows: Vec<PositionedPacketRow>,
    pub fields: Vec<PositionedPacketField>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KanbanLayoutConfig {
    pub column_spacing: i32,
    pub card_spacing: i32,
    pub horizontal_padding: i32,
    pub column_min_width: i32,
    pub header_height: i32,
    pub card_base_height: i32,
}

impl Default for KanbanLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl KanbanLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            column_spacing: 4,
            card_spacing: 1,
            horizontal_padding: 2,
            column_min_width: 18,
            header_height: 3,
            card_base_height: 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedKanbanColumn {
    pub id: Option<String>,
    pub title: String,
    pub rect: Rect,
    pub header: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedKanbanTask {
    pub column_index: usize,
    pub id: Option<String>,
    pub label: String,
    pub metadata: Vec<(String, String)>,
    pub rect: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KanbanLayout {
    pub columns: Vec<PositionedKanbanColumn>,
    pub tasks: Vec<PositionedKanbanTask>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ArchitectureLayoutConfig {
    pub node_min_width: i32,
    pub node_height: i32,
    pub junction_height: i32,
    pub group_min_width: i32,
    pub group_title_height: i32,
    pub group_padding: i32,
    pub item_spacing: i32,
    pub group_spacing: i32,
}

impl Default for ArchitectureLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl ArchitectureLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            node_min_width: 16,
            node_height: 5,
            junction_height: 3,
            group_min_width: 22,
            group_title_height: 3,
            group_padding: 2,
            item_spacing: 2,
            group_spacing: 5,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArchitectureNodeKind {
    Service,
    Junction,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedArchitectureGroup {
    pub id: String,
    pub label: String,
    pub icon: Option<String>,
    pub parent: Option<String>,
    pub rect: Rect,
    pub header: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedArchitectureNode {
    pub id: String,
    pub label: String,
    pub icon: Option<String>,
    pub parent: Option<String>,
    pub kind: ArchitectureNodeKind,
    pub rect: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedArchitectureEdge {
    pub from: String,
    pub to: String,
    pub from_side: ArchitectureSide,
    pub to_side: ArchitectureSide,
    pub from_group: bool,
    pub to_group: bool,
    pub arrow_start: bool,
    pub arrow_end: bool,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedArchitectureAlignment {
    pub axis: ArchitectureAlignAxis,
    pub members: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArchitectureLayout {
    pub groups: Vec<PositionedArchitectureGroup>,
    pub nodes: Vec<PositionedArchitectureNode>,
    pub edges: Vec<PositionedArchitectureEdge>,
    pub alignments: Vec<PositionedArchitectureAlignment>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RadarLayoutConfig {
    pub radius: i32,
    pub title_spacing: i32,
    pub legend_spacing: i32,
}

impl Default for RadarLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl RadarLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            radius: 8,
            title_spacing: 2,
            legend_spacing: 4,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedRadarAxis {
    pub id: String,
    pub label: String,
    pub end: Point,
    pub label_origin: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedRadarPoint {
    pub axis_id: String,
    pub value: String,
    pub point: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedRadarCurve {
    pub id: String,
    pub label: String,
    pub marker: char,
    pub points: Vec<PositionedRadarPoint>,
    pub legend_origin: Option<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RadarLayout {
    pub title: Option<String>,
    pub axes: Vec<PositionedRadarAxis>,
    pub curves: Vec<PositionedRadarCurve>,
    pub rings: Vec<Vec<Point>>,
    pub center: Point,
    pub show_legend: bool,
    pub min_value: String,
    pub max_value: String,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EventModelingLayoutConfig {
    pub column_spacing: i32,
    pub lane_spacing: i32,
    pub node_width: i32,
    pub node_height: i32,
    pub lane_label_width: i32,
    pub top_padding: i32,
}

impl Default for EventModelingLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl EventModelingLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            column_spacing: 6,
            lane_spacing: 2,
            node_width: 18,
            node_height: 5,
            lane_label_width: 20,
            top_padding: 1,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedEventModelingLane {
    pub id: String,
    pub title: String,
    pub y: i32,
    pub height: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedEventModelingFrame {
    pub number: String,
    pub entity: String,
    pub entity_type: EventModelingEntityType,
    pub frame_kind: EventModelingFrameKind,
    pub data_ref: Option<String>,
    pub data_summary: Option<String>,
    pub rect: Rect,
    pub lane_index: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedEventModelingRelation {
    pub from_index: usize,
    pub to_index: usize,
    pub points: Vec<Point>,
    pub explicit: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedEventModelingDataBlock {
    pub id: String,
    pub ty: Option<String>,
    pub summary: String,
    pub origin: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventModelingLayout {
    pub lanes: Vec<PositionedEventModelingLane>,
    pub frames: Vec<PositionedEventModelingFrame>,
    pub relations: Vec<PositionedEventModelingRelation>,
    pub data_blocks: Vec<PositionedEventModelingDataBlock>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TreemapLayoutConfig {
    pub width: i32,
    pub height: i32,
    pub padding: i32,
}

impl Default for TreemapLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl TreemapLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            width: 78,
            height: 22,
            padding: 1,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedTreemapNode {
    pub label: String,
    pub value: Option<String>,
    pub aggregate_value: String,
    pub classes: Vec<String>,
    pub rect: Rect,
    pub depth: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreemapLayout {
    pub nodes: Vec<PositionedTreemapNode>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VennLayoutConfig {
    pub width: i32,
    pub height: i32,
    pub radius_x: i32,
    pub radius_y: i32,
    pub title_spacing: i32,
}

impl Default for VennLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl VennLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            width: 74,
            height: 22,
            radius_x: 14,
            radius_y: 6,
            title_spacing: 2,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedVennSet {
    pub id: String,
    pub label: String,
    pub size: Option<String>,
    pub center: Point,
    pub radius_x: i32,
    pub radius_y: i32,
    pub texts: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedVennUnion {
    pub members: Vec<String>,
    pub label: Option<String>,
    pub size: Option<String>,
    pub point: Point,
    pub texts: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedVennStyle {
    pub targets: Vec<String>,
    pub declarations: Vec<String>,
    pub origin: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VennLayout {
    pub title: Option<String>,
    pub sets: Vec<PositionedVennSet>,
    pub unions: Vec<PositionedVennUnion>,
    pub styles: Vec<PositionedVennStyle>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct IshikawaLayoutConfig {
    pub width: i32,
    pub spine_y: i32,
    pub root_offset: i32,
    pub row_spacing: i32,
    pub child_indent: i32,
    pub node_padding: i32,
    pub min_node_width: i32,
    pub node_height: i32,
}

impl Default for IshikawaLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl IshikawaLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            width: 118,
            spine_y: 14,
            root_offset: 4,
            row_spacing: 4,
            child_indent: 7,
            node_padding: 2,
            min_node_width: 8,
            node_height: 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedIshikawaNode {
    pub label: String,
    pub rect: Rect,
    pub depth: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PositionedIshikawaEdge {
    pub from: Point,
    pub to: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IshikawaLayout {
    pub event: String,
    pub event_rect: Rect,
    pub spine_start: Point,
    pub spine_end: Point,
    pub nodes: Vec<PositionedIshikawaNode>,
    pub edges: Vec<PositionedIshikawaEdge>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WardleyLayoutConfig {
    pub width: i32,
    pub height: i32,
    pub margin_left: i32,
    pub margin_top: i32,
    pub plot_width: i32,
    pub plot_height: i32,
}

impl Default for WardleyLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl WardleyLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            width: 96,
            height: 31,
            margin_left: 5,
            margin_top: 3,
            plot_width: 78,
            plot_height: 21,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedWardleyComponent {
    pub name: String,
    pub kind: WardleyComponentKind,
    pub point: Point,
    pub label_origin: Point,
    pub decorators: Vec<WardleyDecorator>,
    pub pipeline: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedWardleyLink {
    pub from: Point,
    pub to: Point,
    pub kind: WardleyLinkKind,
    pub label: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedWardleyEvolve {
    pub from: Point,
    pub to: Point,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedWardleyText {
    pub text: String,
    pub point: Point,
    pub kind: WardleyTextKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WardleyTextKind {
    Note,
    Annotation,
    Accelerator,
    Deaccelerator,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyLayout {
    pub title: Option<String>,
    pub plot: Rect,
    pub components: Vec<PositionedWardleyComponent>,
    pub links: Vec<PositionedWardleyLink>,
    pub evolves: Vec<PositionedWardleyEvolve>,
    pub texts: Vec<PositionedWardleyText>,
    pub stages: Vec<String>,
    pub annotations_origin: Option<Point>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TreeViewLayoutConfig {
    pub padding_x: i32,
    pub padding_y: i32,
}

impl Default for TreeViewLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl TreeViewLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            padding_x: 1,
            padding_y: 1,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedTreeViewNode {
    pub prefix: String,
    pub label: String,
    pub directory: bool,
    pub icon: String,
    pub classes: Vec<String>,
    pub description: Option<String>,
    pub depth: usize,
    pub point: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreeViewLayout {
    pub nodes: Vec<PositionedTreeViewNode>,
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
    pub start_cardinality: Option<String>,
    pub end_cardinality: Option<String>,
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
pub struct RequirementLayoutConfig {
    pub horizontal_spacing: i32,
    pub vertical_spacing: i32,
    pub horizontal_padding: i32,
    pub min_node_width: i32,
}

impl Default for RequirementLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl RequirementLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            horizontal_spacing: 14,
            vertical_spacing: 5,
            horizontal_padding: 4,
            min_node_width: 18,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PositionedRequirementNodeKind {
    Requirement,
    Element,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedRequirementNode {
    pub id: String,
    pub kind: PositionedRequirementNodeKind,
    pub type_label: String,
    pub name: String,
    pub rows: Vec<String>,
    pub classes: Vec<String>,
    pub rect: Rect,
    pub layer: usize,
    pub order: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedRequirementRelationship {
    pub from: String,
    pub to: String,
    pub kind: RequirementRelationshipKind,
    pub label: String,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequirementLayout {
    pub direction: Direction,
    pub nodes: Vec<PositionedRequirementNode>,
    pub relationships: Vec<PositionedRequirementRelationship>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct C4LayoutConfig {
    pub horizontal_spacing: i32,
    pub vertical_spacing: i32,
    pub horizontal_padding: i32,
    pub boundary_padding_x: i32,
    pub boundary_padding_y: i32,
    pub boundary_header_height: i32,
    pub min_node_width: i32,
    pub shape_in_row: usize,
    pub boundary_in_row: usize,
    pub direction: Direction,
}

impl Default for C4LayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl C4LayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            horizontal_spacing: 8,
            vertical_spacing: 4,
            horizontal_padding: 3,
            boundary_padding_x: 2,
            boundary_padding_y: 1,
            boundary_header_height: 4,
            min_node_width: 18,
            shape_in_row: 4,
            boundary_in_row: 2,
            direction: Direction::TopDown,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedC4Element {
    pub id: String,
    pub label: String,
    pub kind_label: String,
    pub technology: Option<String>,
    pub description: Option<String>,
    pub style_rows: Vec<String>,
    pub parent: Option<String>,
    pub external: bool,
    pub rect: Rect,
    pub layer: usize,
    pub order: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedC4Boundary {
    pub id: String,
    pub label: String,
    pub kind_label: String,
    pub ty: Option<String>,
    pub header_height: i32,
    pub style_rows: Vec<String>,
    pub parent: Option<String>,
    pub rect: Rect,
    pub depth: usize,
    pub order: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedC4Relationship {
    pub from: String,
    pub to: String,
    pub kind: C4RelationshipKind,
    pub label: String,
    pub technology: Option<String>,
    pub style_rows: Vec<String>,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct C4Layout {
    pub title: Option<String>,
    pub elements: Vec<PositionedC4Element>,
    pub boundaries: Vec<PositionedC4Boundary>,
    pub relationships: Vec<PositionedC4Relationship>,
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
pub struct PositionedGanttTick {
    pub day: i32,
    pub x: i32,
    pub label: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GanttLayout {
    pub title: Option<String>,
    pub sections: Vec<PositionedGanttSection>,
    pub tasks: Vec<PositionedGanttTask>,
    pub ticks: Vec<PositionedGanttTick>,
    pub excluded_days: Vec<i32>,
    pub today_x: Option<i32>,
    pub day_width: i32,
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
    pub label_origin: Point,
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
pub struct QuadrantLayoutConfig {
    pub plot_width: i32,
    pub plot_height: i32,
    pub left_margin: i32,
    pub top_padding: i32,
    pub label_gap: i32,
}

impl Default for QuadrantLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl QuadrantLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            plot_width: 61,
            plot_height: 19,
            left_margin: 14,
            top_padding: 1,
            label_gap: 1,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedQuadrantPoint {
    pub label: String,
    pub x_value: u16,
    pub y_value: u16,
    pub point: Point,
    pub label_origin: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedQuadrantSection {
    pub index: u8,
    pub label: String,
    pub origin: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QuadrantLayout {
    pub title: Option<String>,
    pub x_start: String,
    pub x_end: String,
    pub y_start: String,
    pub y_end: String,
    pub plot: Rect,
    pub quadrants: Vec<PositionedQuadrantSection>,
    pub points: Vec<PositionedQuadrantPoint>,
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
    pub actor_style_indices: Vec<usize>,
    pub label_origin: Point,
    pub bar_rect: Rect,
    pub score_origin: Point,
    pub actors_origin: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JourneyLayout {
    pub title: Option<String>,
    pub sections: Vec<PositionedJourneySection>,
    pub actors: Vec<String>,
    pub tasks: Vec<PositionedJourneyTask>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GitGraphLayoutConfig {
    pub label_width: i32,
    pub commit_spacing: i32,
    pub branch_spacing: i32,
    pub top_padding: i32,
    pub left_padding: i32,
}

impl Default for GitGraphLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl GitGraphLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            label_width: 12,
            commit_spacing: 12,
            branch_spacing: 8,
            top_padding: 2,
            left_padding: 2,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedGitGraphBranch {
    pub name: String,
    pub lane: usize,
    pub label_origin: Point,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedGitGraphCommit {
    pub index: usize,
    pub id: String,
    pub tag: Option<String>,
    pub branch: String,
    pub kind: GitGraphCommitKind,
    pub point: Point,
    pub label_origin: Point,
    pub tag_origin: Option<Point>,
    pub is_merge: bool,
    pub is_cherry_pick: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedGitGraphEdge {
    pub from: usize,
    pub to: usize,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitGraphLayout {
    pub orientation: GitGraphOrientation,
    pub branches: Vec<PositionedGitGraphBranch>,
    pub commits: Vec<PositionedGitGraphCommit>,
    pub edges: Vec<PositionedGitGraphEdge>,
    pub size: Size,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TimelineLayoutConfig {
    pub period_spacing: i32,
    pub section_gap: i32,
    pub top_padding: i32,
    pub left_padding: i32,
}

impl Default for TimelineLayoutConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl TimelineLayoutConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            period_spacing: 20,
            section_gap: 3,
            top_padding: 3,
            left_padding: 2,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedTimelineSection {
    pub label: Option<String>,
    pub y: i32,
    pub axis_start: Point,
    pub axis_end: Point,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PositionedTimelinePeriod {
    pub index: usize,
    pub label: String,
    pub section: Option<String>,
    pub events: Vec<String>,
    pub point: Point,
    pub label_origin: Point,
    pub event_origins: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimelineLayout {
    pub title: Option<String>,
    pub sections: Vec<PositionedTimelineSection>,
    pub periods: Vec<PositionedTimelinePeriod>,
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
pub struct ZenUmlLayoutEngine {
    config: ZenUmlLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct SankeyLayoutEngine {
    config: SankeyLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct XyChartLayoutEngine {
    config: XyChartLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct BlockLayoutEngine {
    config: BlockLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct PacketLayoutEngine {
    config: PacketLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct KanbanLayoutEngine {
    config: KanbanLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct ArchitectureLayoutEngine {
    config: ArchitectureLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct RadarLayoutEngine {
    config: RadarLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct EventModelingLayoutEngine {
    config: EventModelingLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct TreemapLayoutEngine {
    config: TreemapLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct VennLayoutEngine {
    config: VennLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct IshikawaLayoutEngine {
    config: IshikawaLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct WardleyLayoutEngine {
    config: WardleyLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct TreeViewLayoutEngine {
    config: TreeViewLayoutConfig,
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
pub struct QuadrantLayoutEngine {
    config: QuadrantLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct MindmapLayoutEngine {
    config: MindmapLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct JourneyLayoutEngine {
    config: JourneyLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct GitGraphLayoutEngine {
    config: GitGraphLayoutConfig,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct TimelineLayoutEngine {
    config: TimelineLayoutConfig,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RequirementLayoutEngine {
    config: RequirementLayoutConfig,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct C4LayoutEngine {
    config: C4LayoutConfig,
}

impl Default for ErLayoutEngine {
    fn default() -> Self {
        Self::default_values()
    }
}

impl Default for RequirementLayoutEngine {
    fn default() -> Self {
        Self::default_values()
    }
}

impl Default for C4LayoutEngine {
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
        let mut activations = Vec::new();
        let mut active_participants = Vec::<(String, i32)>::new();
        let mut destroys = Vec::new();
        let mut pending_destroys = Vec::<String>::new();
        let mut auto_number = None::<SequenceNumberCounter>;
        let mut event_index = 0i32;

        for statement in &ast.statements {
            match statement {
                SequenceStatement::Message(message) => {
                    let y = self.event_y(event_index);
                    event_index += 1;
                    let number = auto_number.as_mut().map(SequenceNumberCounter::next_label);
                    messages.push(self.position_message(
                        message,
                        &positioned_participants,
                        y,
                        number,
                    ));
                    apply_message_activation(
                        message,
                        y,
                        &mut active_participants,
                        &mut activations,
                        &positioned_participants,
                    );
                    flush_pending_destroys(
                        message,
                        y,
                        &mut pending_destroys,
                        &positioned_participants,
                        &mut destroys,
                    );
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
                        kind: control.kind,
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
                SequenceStatement::ActivationStart(participant) => {
                    active_participants
                        .push((participant.value.clone(), self.event_y(event_index)));
                }
                SequenceStatement::ActivationEnd(participant) => {
                    close_sequence_activation(
                        &participant.value,
                        self.event_y(event_index),
                        &mut active_participants,
                        &mut activations,
                        &positioned_participants,
                    );
                }
                SequenceStatement::Destroy(destroy) => {
                    pending_destroys.push(destroy.participant.value.clone());
                }
                SequenceStatement::AutoNumber(next) => {
                    auto_number = Some(SequenceNumberCounter::new(next));
                }
                SequenceStatement::Participant(_)
                | SequenceStatement::Create(_)
                | SequenceStatement::Box(_)
                | SequenceStatement::Comment(_)
                | SequenceStatement::Directive(_) => {}
            }
        }
        let fallback_activation_end = self
            .event_y(event_index)
            .max(self.config.participant_height + self.config.top_padding);
        while let Some((participant, start_y)) = active_participants.pop() {
            push_sequence_activation(
                participant,
                start_y,
                fallback_activation_end,
                &positioned_participants,
                &mut activations,
            );
        }
        for participant in pending_destroys {
            destroys.push(position_destroy_marker(
                &participant,
                fallback_activation_end,
                &positioned_participants,
            ));
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
            if let Some(width) = sequence_message_text_width(message)
                && let (Some(first), Some(last)) = (
                    message.points.first().copied(),
                    message.points.last().copied(),
                )
            {
                let x = first.x.min(last.x) + 1;
                size.width = size.width.max(x + width as i32);
            }
        }
        for activation in &activations {
            size.width = size.width.max(activation.rect.right());
            size.height = size.height.max(activation.rect.bottom());
        }
        for destroy in &destroys {
            size.width = size.width.max(destroy.point.x + 1);
            size.height = size.height.max(destroy.point.y + 1);
        }
        let boxes = position_sequence_boxes(&ast.boxes, &positioned_participants, size);
        for sequence_box in &boxes {
            size.width = size.width.max(sequence_box.rect.right());
            size.height = size.height.max(sequence_box.rect.bottom());
        }

        SequenceLayout {
            participants: positioned_participants,
            boxes,
            messages,
            notes,
            controls,
            activations,
            destroys,
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
        number: Option<String>,
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
            number,
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

struct SequenceNumberCounter {
    current: i64,
    step: i64,
}

impl SequenceNumberCounter {
    fn new(auto_number: &SequenceAutoNumber) -> Self {
        Self {
            current: sequence_number_hundredths(auto_number.start.as_ref(), 100),
            step: sequence_number_hundredths(auto_number.step.as_ref(), 100),
        }
    }

    fn next_label(&mut self) -> String {
        let label = format_sequence_number(self.current);
        self.current += self.step;
        label
    }
}

fn sequence_number_hundredths(value: Option<&Spanned<String>>, default: i64) -> i64 {
    let Some(value) = value else {
        return default;
    };
    let Some((integer, fraction)) = value.value.split_once('.') else {
        return value.value.parse::<i64>().unwrap_or(default) * 100;
    };
    let integer = integer.parse::<i64>().unwrap_or(default / 100) * 100;
    let fraction = match fraction.len() {
        1 => fraction.parse::<i64>().unwrap_or(0) * 10,
        2 => fraction.parse::<i64>().unwrap_or(0),
        _ => 0,
    };
    integer + fraction
}

fn format_sequence_number(value: i64) -> String {
    let integer = value / 100;
    let fraction = value.rem_euclid(100);
    if fraction == 0 {
        integer.to_string()
    } else if fraction % 10 == 0 {
        format!("{integer}.{}", fraction / 10)
    } else {
        format!("{integer}.{fraction:02}")
    }
}

fn apply_message_activation(
    message: &SequenceMessage,
    y: i32,
    active_participants: &mut Vec<(String, i32)>,
    activations: &mut Vec<PositionedSequenceActivation>,
    participants: &[PositionedSequenceParticipant],
) {
    let Some(activation) = message.activation else {
        return;
    };
    match activation.value {
        SequenceActivation::Start => active_participants.push((message.to.value.clone(), y)),
        SequenceActivation::End => close_sequence_activation(
            &message.from.value,
            y + 1,
            active_participants,
            activations,
            participants,
        ),
    }
}

fn close_sequence_activation(
    participant: &str,
    end_y: i32,
    active_participants: &mut Vec<(String, i32)>,
    activations: &mut Vec<PositionedSequenceActivation>,
    participants: &[PositionedSequenceParticipant],
) {
    let Some(index) = active_participants
        .iter()
        .rposition(|(active, _)| active == participant)
    else {
        return;
    };
    let (participant, start_y) = active_participants.remove(index);
    push_sequence_activation(participant, start_y, end_y, participants, activations);
}

fn push_sequence_activation(
    participant: String,
    start_y: i32,
    end_y: i32,
    participants: &[PositionedSequenceParticipant],
    activations: &mut Vec<PositionedSequenceActivation>,
) {
    let lane_x = participant_lane(participants, &participant);
    let top = start_y.min(end_y);
    let height = (end_y.max(start_y + 3) - top).max(3);
    activations.push(PositionedSequenceActivation {
        participant,
        rect: Rect {
            origin: Point {
                x: (lane_x - 1).max(0),
                y: top,
            },
            size: Size { width: 3, height },
        },
    });
}

fn flush_pending_destroys(
    message: &SequenceMessage,
    y: i32,
    pending_destroys: &mut Vec<String>,
    participants: &[PositionedSequenceParticipant],
    destroys: &mut Vec<PositionedSequenceDestroy>,
) {
    let mut retained = Vec::new();
    for participant in pending_destroys.drain(..) {
        if participant == message.from.value || participant == message.to.value {
            destroys.push(position_destroy_marker(&participant, y + 1, participants));
        } else {
            retained.push(participant);
        }
    }
    *pending_destroys = retained;
}

fn position_destroy_marker(
    participant: &str,
    y: i32,
    participants: &[PositionedSequenceParticipant],
) -> PositionedSequenceDestroy {
    PositionedSequenceDestroy {
        participant: participant.to_owned(),
        point: Point {
            x: participant_lane(participants, participant),
            y,
        },
    }
}

fn position_sequence_boxes(
    boxes: &[SequenceBox],
    participants: &[PositionedSequenceParticipant],
    size: Size,
) -> Vec<PositionedSequenceBox> {
    boxes
        .iter()
        .filter_map(|sequence_box| position_sequence_box(sequence_box, participants, size))
        .collect()
}

fn position_sequence_box(
    sequence_box: &SequenceBox,
    participants: &[PositionedSequenceParticipant],
    size: Size,
) -> Option<PositionedSequenceBox> {
    let box_participants = sequence_box
        .participants
        .iter()
        .filter_map(|box_participant| {
            participants
                .iter()
                .find(|participant| participant.id == box_participant.value)
        })
        .collect::<Vec<_>>();
    let min_x = box_participants
        .iter()
        .map(|participant| participant.header.origin.x)
        .min()?
        .saturating_sub(1)
        .max(0);
    let max_x = box_participants
        .iter()
        .map(|participant| participant.header.right())
        .max()?
        + 1;
    let label_width = sequence_box
        .label
        .as_ref()
        .map_or(0, |label| label.text.chars().count() as i32 + 2);
    let width = (max_x - min_x).max(label_width);
    let top = box_participants
        .iter()
        .map(|participant| participant.header.bottom())
        .max()
        .unwrap_or(0);
    Some(PositionedSequenceBox {
        label: sequence_box.label.as_ref().map(|label| label.text.clone()),
        participants: sequence_box
            .participants
            .iter()
            .map(|participant| participant.value.clone())
            .collect(),
        rect: Rect {
            origin: Point { x: min_x, y: top },
            size: Size {
                width,
                height: (size.height - top).max(1),
            },
        },
    })
}

fn sequence_message_text_width(message: &PositionedSequenceMessage) -> Option<usize> {
    message.number.as_ref()?;
    let number_width = message
        .number
        .as_ref()
        .map(|number| number.chars().count() + 2);
    let label_width = message.label.as_ref().map(|label| label.chars().count());
    match (number_width, label_width) {
        (Some(number), Some(label)) => Some(number + label),
        (Some(number), None) => Some(number),
        (None, Some(label)) => Some(label),
        (None, None) => None,
    }
}

impl ZenUmlLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: ZenUmlLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: ZenUmlLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &ZenUmlAst) -> ZenUmlLayout {
        let title_height = i32::from(ast.title.is_some()) * 2;
        let participants = self.position_participants(ast, title_height);
        let mut messages = Vec::new();
        let mut fragments = Vec::new();
        let mut event_index = 0i32;

        for statement in &ast.statements {
            match statement {
                ZenUmlStatement::Message(message) => {
                    messages.push(self.position_message(
                        message,
                        &participants,
                        event_index,
                        title_height,
                    ));
                    event_index += 1;
                }
                ZenUmlStatement::Fragment(fragment) => {
                    fragments.push(PositionedZenUmlFragment {
                        label: zenuml_fragment_label(fragment.kind.value, &fragment.label),
                        depth: fragment.depth,
                        y: self.event_y(event_index, title_height),
                    });
                    event_index += 1;
                }
                ZenUmlStatement::Title(_)
                | ZenUmlStatement::Participant(_)
                | ZenUmlStatement::BlockEnd(_)
                | ZenUmlStatement::Comment(_)
                | ZenUmlStatement::Directive(_) => {}
            }
        }

        let mut size = Size {
            width: zenuml_width(&participants, self.config),
            height: title_height + self.config.participant_height + self.config.top_padding,
        };
        if let Some(title) = &ast.title {
            size.width = size.width.max(label_width(&title.text));
        }
        for participant in &participants {
            size.width = size.width.max(participant.header.right());
            size.height = size.height.max(participant.header.bottom());
        }
        for message in &messages {
            for point in &message.points {
                size.width = size.width.max(point.x + 1);
                size.height = size.height.max(point.y + 1);
            }
            let x = message
                .points
                .first()
                .zip(message.points.last())
                .map_or(0, |(first, last)| first.x.min(last.x) + 1);
            size.width = size
                .width
                .max(x + i32::from(message.depth) * 2 + label_width(&message.label) + 2);
        }
        for fragment in &fragments {
            size.width = size
                .width
                .max(i32::from(fragment.depth) * 2 + label_width(&fragment.label) + 2);
            size.height = size.height.max(fragment.y + 1);
        }
        size.height = size
            .height
            .max(self.event_y(event_index, title_height) + self.config.top_padding);

        ZenUmlLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            participants,
            messages,
            fragments,
            size,
        }
    }

    fn position_participants(
        &self,
        ast: &ZenUmlAst,
        title_height: i32,
    ) -> Vec<PositionedZenUmlParticipant> {
        let labels = ast
            .participants
            .iter()
            .map(|participant| {
                let label = participant
                    .label
                    .as_ref()
                    .map_or_else(|| participant.id.value.clone(), |label| label.text.clone());
                let width = self
                    .config
                    .participant_width
                    .max(label_width(&label) + 2)
                    .max(
                        participant
                            .annotator
                            .as_ref()
                            .map_or(0, |annotator| label_width(&annotator.value) + 3),
                    );
                (label, width)
            })
            .collect::<Vec<_>>();
        let max_width = labels
            .iter()
            .map(|(_, width)| *width)
            .max()
            .unwrap_or(self.config.participant_width);
        let lane_spacing = self.config.lane_spacing.max(max_width + 4);
        ast.participants
            .iter()
            .zip(labels)
            .enumerate()
            .map(|(order, (participant, (label, width)))| {
                let lane_x = order as i32 * lane_spacing + max_width / 2;
                PositionedZenUmlParticipant {
                    id: participant.id.value.clone(),
                    label,
                    annotator: participant
                        .annotator
                        .as_ref()
                        .map(|annotator| annotator.value.clone()),
                    lane_x,
                    header: Rect {
                        origin: Point {
                            x: lane_x - width / 2,
                            y: title_height,
                        },
                        size: Size {
                            width,
                            height: self.config.participant_height,
                        },
                    },
                    order,
                }
            })
            .collect()
    }

    fn position_message(
        &self,
        message: &crate::ast::ZenUmlMessage,
        participants: &[PositionedZenUmlParticipant],
        event_index: i32,
        title_height: i32,
    ) -> PositionedZenUmlMessage {
        let to_x = if message.to.value == "return" {
            participants
                .first()
                .map_or(0, |participant| participant.lane_x)
        } else {
            zenuml_participant_lane(participants, &message.to.value)
        };
        let from_x = message.from.as_ref().map_or(to_x, |from| {
            zenuml_participant_lane(participants, &from.value)
        });
        let y = self.event_y(event_index, title_height);
        let points = if from_x == to_x {
            vec![
                Point { x: from_x, y },
                Point {
                    x: from_x + self.config.lane_spacing / 2,
                    y,
                },
                Point {
                    x: from_x + self.config.lane_spacing / 2,
                    y: y + 1,
                },
                Point {
                    x: from_x,
                    y: y + 1,
                },
            ]
        } else {
            vec![Point { x: from_x, y }, Point { x: to_x, y }]
        };
        PositionedZenUmlMessage {
            from: message.from.as_ref().map(|from| from.value.clone()),
            to: message.to.value.clone(),
            label: zenuml_message_label(message),
            kind: message.kind.value,
            depth: message.depth,
            y,
            points,
        }
    }

    const fn event_y(&self, index: i32, title_height: i32) -> i32 {
        title_height
            + self.config.participant_height
            + self.config.top_padding
            + index * self.config.event_spacing
    }
}

fn zenuml_width(participants: &[PositionedZenUmlParticipant], config: ZenUmlLayoutConfig) -> i32 {
    participants
        .iter()
        .map(|participant| participant.header.right())
        .max()
        .unwrap_or(config.participant_width)
}

fn zenuml_participant_lane(participants: &[PositionedZenUmlParticipant], id: &str) -> i32 {
    participants
        .iter()
        .find(|participant| participant.id == id)
        .map_or(0, |participant| participant.lane_x)
}

fn zenuml_message_label(message: &crate::ast::ZenUmlMessage) -> String {
    if let Some(label) = &message.label {
        return label.text.clone();
    }
    match message.kind.value {
        ZenUmlMessageKind::Create => format!("new {}", message.to.value),
        ZenUmlMessageKind::Reply => "return".to_owned(),
        ZenUmlMessageKind::Sync | ZenUmlMessageKind::Async => String::new(),
    }
}

fn zenuml_fragment_label(kind: ZenUmlFragmentKind, label: &Option<Label>) -> String {
    let prefix = match kind {
        ZenUmlFragmentKind::Loop => "loop",
        ZenUmlFragmentKind::Alt => "alt",
        ZenUmlFragmentKind::Opt => "opt",
        ZenUmlFragmentKind::Parallel => "par",
        ZenUmlFragmentKind::Try => "try",
        ZenUmlFragmentKind::Catch => "catch",
        ZenUmlFragmentKind::Finally => "finally",
        ZenUmlFragmentKind::Block => "block",
    };
    label.as_ref().map_or_else(
        || prefix.to_owned(),
        |label| format!("{prefix} {}", label.text),
    )
}

impl SankeyLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: SankeyLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: SankeyLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &SankeyAst) -> SankeyLayout {
        let ids = sankey_node_ids(ast);
        let layers = sankey_layers(ast, &ids);
        let mut layer_orders = HashMap::<usize, usize>::new();
        let widths = ids
            .iter()
            .map(|id| {
                self.config
                    .min_node_width
                    .max(label_width(id) + self.config.horizontal_padding * 2)
            })
            .collect::<Vec<_>>();
        let layer_widths = sankey_layer_widths(&layers, &widths);
        let layer_offsets = sankey_layer_offsets(&layer_widths, self.config.horizontal_spacing);
        let nodes = ids
            .iter()
            .enumerate()
            .map(|(index, id)| {
                let layer = layers[index];
                let order = *layer_orders
                    .entry(layer)
                    .and_modify(|order| *order += 1)
                    .or_insert(0);
                PositionedSankeyNode {
                    id: id.clone(),
                    label: id.clone(),
                    rect: Rect {
                        origin: Point {
                            x: layer_offsets[layer],
                            y: order as i32
                                * (self.config.node_height + self.config.vertical_spacing),
                        },
                        size: Size {
                            width: widths[index],
                            height: self.config.node_height,
                        },
                    },
                    layer,
                    order,
                }
            })
            .collect::<Vec<_>>();
        let links = ast
            .links
            .iter()
            .map(|link| {
                let source = &link.source.text;
                let target = &link.target.text;
                let source_rect = sankey_node_rect(&nodes, source);
                let target_rect = sankey_node_rect(&nodes, target);
                let start = Point {
                    x: source_rect.right().saturating_sub(1),
                    y: source_rect.center().y,
                };
                let end = Point {
                    x: target_rect.origin.x,
                    y: target_rect.center().y,
                };
                let mid_x = (start.x + end.x) / 2;
                PositionedSankeyLink {
                    source: source.clone(),
                    target: target.clone(),
                    value_text: link.value_text.value.clone(),
                    value_units: link.value_units.value,
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
            })
            .collect::<Vec<_>>();
        let mut size = Size {
            width: self.config.min_node_width,
            height: self.config.node_height,
        };
        for node in &nodes {
            size.width = size.width.max(node.rect.right());
            size.height = size.height.max(node.rect.bottom());
        }
        for link in &links {
            for point in &link.points {
                size.width = size.width.max(point.x + 1);
                size.height = size.height.max(point.y + 1);
            }
            if let Some(label_point) = sankey_link_label_point(link) {
                size.width = size
                    .width
                    .max(label_point.x + label_width(&link.value_text) + 1);
                size.height = size.height.max(label_point.y + 1);
            }
        }
        SankeyLayout { nodes, links, size }
    }
}

fn sankey_node_ids(ast: &SankeyAst) -> Vec<String> {
    let mut ids = Vec::<String>::new();
    for link in &ast.links {
        if !ids.iter().any(|id| id == &link.source.text) {
            ids.push(link.source.text.clone());
        }
        if !ids.iter().any(|id| id == &link.target.text) {
            ids.push(link.target.text.clone());
        }
    }
    ids
}

fn sankey_layers(ast: &SankeyAst, ids: &[String]) -> Vec<usize> {
    let index = ids
        .iter()
        .enumerate()
        .map(|(index, id)| (id.as_str(), index))
        .collect::<HashMap<_, _>>();
    let mut layers = vec![0usize; ids.len()];
    for _ in 0..ids.len() {
        let mut changed = false;
        for link in &ast.links {
            let (Some(&source), Some(&target)) = (
                index.get(link.source.text.as_str()),
                index.get(link.target.text.as_str()),
            ) else {
                continue;
            };
            let candidate = layers[source]
                .saturating_add(1)
                .min(ids.len().saturating_sub(1));
            if layers[target] < candidate {
                layers[target] = candidate;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    layers
}

fn sankey_layer_widths(layers: &[usize], widths: &[i32]) -> Vec<i32> {
    let layer_count = layers.iter().max().map_or(1, |layer| layer + 1);
    let mut layer_widths = vec![0i32; layer_count];
    for (layer, width) in layers.iter().zip(widths) {
        layer_widths[*layer] = layer_widths[*layer].max(*width);
    }
    layer_widths
}

fn sankey_layer_offsets(layer_widths: &[i32], spacing: i32) -> Vec<i32> {
    let mut offsets = Vec::with_capacity(layer_widths.len());
    let mut x = 0i32;
    for width in layer_widths {
        offsets.push(x);
        x += *width + spacing;
    }
    offsets
}

fn sankey_node_rect(nodes: &[PositionedSankeyNode], id: &str) -> Rect {
    nodes.iter().find(|node| node.id == id).map_or(
        Rect {
            origin: Point { x: 0, y: 0 },
            size: Size {
                width: 1,
                height: 1,
            },
        },
        |node| node.rect,
    )
}

fn sankey_link_label_point(link: &PositionedSankeyLink) -> Option<Point> {
    let first = link.points.first()?;
    let last = link.points.last()?;
    Some(Point {
        x: (first.x + last.x) / 2 + 1,
        y: (first.y + last.y) / 2,
    })
}

impl XyChartLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: XyChartLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: XyChartLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &XyChartAst) -> XyChartLayout {
        let title = ast.title.as_ref().map(|title| title.text.clone());
        let x_title = ast
            .x_axis
            .as_ref()
            .and_then(|axis| axis.title.as_ref().map(|title| title.text.clone()));
        let y_title = ast
            .y_axis
            .as_ref()
            .and_then(|axis| axis.title.as_ref().map(|title| title.text.clone()));
        let x_labels = xy_chart_x_labels(ast);
        let (y_min, y_max) = xy_chart_y_range(ast);
        let y_min_label = xy_chart_label_value(y_min);
        let y_max_label = xy_chart_label_value(y_max);
        let left_margin = self
            .config
            .left_margin
            .max(label_width(&y_min_label).max(label_width(&y_max_label)) + 2);
        let plot = Rect {
            origin: Point {
                x: left_margin,
                y: i32::from(title.is_some()) * 2 + self.config.top_padding,
            },
            size: Size {
                width: self.config.plot_width.max(5),
                height: self.config.plot_height.max(5),
            },
        };
        let max_len = ast
            .series
            .iter()
            .map(|series| series.values.len())
            .max()
            .unwrap_or(0);
        let series = ast
            .series
            .iter()
            .map(|series| PositionedXyChartSeries {
                kind: series.kind.value,
                points: series
                    .values
                    .iter()
                    .enumerate()
                    .map(|(index, value)| {
                        xy_chart_point(plot, index, max_len, value.value, y_min, y_max)
                    })
                    .collect(),
                value_texts: series
                    .value_texts
                    .iter()
                    .map(|value| value.value.clone())
                    .collect(),
            })
            .collect::<Vec<_>>();
        let mut size = Size {
            width: plot.right(),
            height: plot.bottom() + 3,
        };
        if let Some(title) = &title {
            size.width = size.width.max(label_width(title));
        }
        if let Some(x_title) = &x_title {
            size.width = size.width.max(plot.origin.x + label_width(x_title));
        }
        if let Some(y_title) = &y_title {
            size.width = size.width.max(label_width(y_title));
        }
        for (index, label) in x_labels.iter().enumerate() {
            let x = xy_chart_x(plot, index, x_labels.len());
            size.width = size.width.max(x + label_width(label));
        }

        XyChartLayout {
            title,
            x_title,
            y_title,
            x_labels,
            y_min_label,
            y_max_label,
            plot,
            series,
            size,
        }
    }
}

fn xy_chart_x_labels(ast: &XyChartAst) -> Vec<String> {
    if let Some(XyChartAxisScale::Categories(labels)) =
        ast.x_axis.as_ref().and_then(|axis| axis.scale.as_ref())
    {
        return labels.iter().map(|label| label.text.clone()).collect();
    }
    let len = ast
        .series
        .iter()
        .map(|series| series.values.len())
        .max()
        .unwrap_or(0);
    (1..=len).map(|value| value.to_string()).collect()
}

fn xy_chart_y_range(ast: &XyChartAst) -> (i64, i64) {
    if let Some(XyChartAxisScale::Range { min, max }) =
        ast.y_axis.as_ref().and_then(|axis| axis.scale.as_ref())
    {
        return (min.value, max.value);
    }
    let mut values = ast
        .series
        .iter()
        .flat_map(|series| series.values.iter().map(|value| value.value));
    let Some(first) = values.next() else {
        return (0, 100);
    };
    let (mut min, mut max) = (first, first);
    for value in values {
        min = min.min(value);
        max = max.max(value);
    }
    if min == max {
        (min.min(0), max.saturating_add(100))
    } else {
        (min.min(0), max)
    }
}

fn xy_chart_label_value(value: i64) -> String {
    if value % 100 == 0 {
        (value / 100).to_string()
    } else {
        format!("{:.2}", value as f64 / 100.0)
    }
}

fn xy_chart_point(
    plot: Rect,
    index: usize,
    len: usize,
    value: i64,
    y_min: i64,
    y_max: i64,
) -> Point {
    Point {
        x: xy_chart_x(plot, index, len),
        y: xy_chart_y(plot, value, y_min, y_max),
    }
}

fn xy_chart_x(plot: Rect, index: usize, len: usize) -> i32 {
    let inner_width = (plot.size.width - 3).max(1);
    if len <= 1 {
        return plot.origin.x + 1 + inner_width / 2;
    }
    plot.origin.x + 1 + index as i32 * inner_width / (len as i32 - 1)
}

fn xy_chart_y(plot: Rect, value: i64, y_min: i64, y_max: i64) -> i32 {
    let inner_height = i64::from((plot.size.height - 3).max(1));
    let range = (y_max - y_min).max(1);
    let offset = (y_max - value).clamp(0, range) * inner_height / range;
    plot.origin.y + 1 + offset as i32
}

impl BlockLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: BlockLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: BlockLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &BlockDiagramAst) -> BlockLayout {
        let lookup = ast
            .blocks
            .iter()
            .map(|node| (node.id.value.as_str(), node))
            .collect::<HashMap<_, _>>();
        let mut layout = BlockLayout {
            nodes: Vec::new(),
            containers: Vec::new(),
            edges: Vec::new(),
            size: Size {
                width: self.config.min_node_width,
                height: self.config.node_height,
            },
        };
        let columns = ast
            .header
            .columns
            .map_or(self.config.default_columns, |columns| columns.value);
        let size = self.layout_statements(
            &ast.statements,
            &lookup,
            columns,
            Point { x: 0, y: 0 },
            &mut layout,
        );
        layout.size = size;
        layout.edges = self.layout_block_edges(ast, &layout.nodes);
        for edge in &layout.edges {
            for point in &edge.points {
                layout.size.width = layout.size.width.max(point.x + 1);
                layout.size.height = layout.size.height.max(point.y + 1);
            }
            if let Some(label) = &edge.label
                && let Some(point) = block_edge_label_point(edge)
            {
                layout.size.width = layout.size.width.max(point.x + label_width(label));
                layout.size.height = layout.size.height.max(point.y + 1);
            }
        }
        layout
    }

    fn layout_statements(
        &self,
        statements: &[BlockStatement],
        lookup: &HashMap<&str, &crate::ast::BlockNode>,
        initial_columns: u16,
        origin: Point,
        layout: &mut BlockLayout,
    ) -> Size {
        let unit_width = self.block_unit_width(statements, lookup);
        let mut columns = initial_columns.max(1);
        let mut column = 0u16;
        let mut row = 0usize;
        let mut x = origin.x;
        let mut y = origin.y;
        let mut row_height = self.config.node_height;
        let mut size = Size {
            width: 0,
            height: 0,
        };
        for statement in statements {
            match statement {
                BlockStatement::Columns(next) => {
                    columns = next.value.max(1);
                    column = 0;
                    x = origin.x;
                    if size.height > 0 {
                        y += row_height + self.config.vertical_spacing;
                        row += 1;
                        row_height = self.config.node_height;
                    }
                }
                BlockStatement::Node(node) => {
                    let node = lookup
                        .get(node.id.value.as_str())
                        .copied()
                        .unwrap_or(node.as_ref());
                    let span = node.width.value.max(1).min(columns);
                    if column > 0 && column.saturating_add(span) > columns {
                        y += row_height + self.config.vertical_spacing;
                        row += 1;
                        column = 0;
                        x = origin.x;
                        row_height = self.config.node_height;
                    }
                    let rect = Rect {
                        origin: Point { x, y },
                        size: Size {
                            width: block_span_width(
                                unit_width,
                                self.config.horizontal_spacing,
                                span,
                            )
                            .max(self.config.min_node_width),
                            height: self.config.node_height,
                        },
                    };
                    layout.nodes.push(PositionedBlockNode {
                        id: node.id.value.clone(),
                        label: block_node_label(node),
                        shape: node.shape.value.clone(),
                        rect,
                        row,
                        column: column as usize,
                    });
                    size.width = size.width.max(rect.right());
                    size.height = size.height.max(rect.bottom());
                    column += span;
                    x += rect.size.width + self.config.horizontal_spacing;
                    row_height = row_height.max(rect.size.height);
                }
                BlockStatement::Space(space) => {
                    let span = space.width.value.max(1).min(columns);
                    if column > 0 && column.saturating_add(span) > columns {
                        y += row_height + self.config.vertical_spacing;
                        row += 1;
                        column = 0;
                        x = origin.x;
                        row_height = self.config.node_height;
                    }
                    let width = block_span_width(unit_width, self.config.horizontal_spacing, span);
                    size.width = size.width.max(x + width);
                    size.height = size.height.max(y + self.config.node_height);
                    column += span;
                    x += width + self.config.horizontal_spacing;
                }
                BlockStatement::Container(container) => {
                    let span = container.width.value.max(1).min(columns);
                    if column > 0 && column.saturating_add(span) > columns {
                        y += row_height + self.config.vertical_spacing;
                        row += 1;
                        column = 0;
                        x = origin.x;
                        row_height = self.config.node_height;
                    }
                    let child_origin = Point {
                        x: x + self.config.container_padding,
                        y: y + self.config.container_padding,
                    };
                    let child_size = self.layout_statements(
                        &container.statements,
                        lookup,
                        container
                            .columns
                            .map_or(columns, |columns| columns.value.max(1)),
                        child_origin,
                        layout,
                    );
                    let min_width =
                        block_span_width(unit_width, self.config.horizontal_spacing, span);
                    let label = container
                        .id
                        .as_ref()
                        .map_or_else(String::new, |id| id.value.clone());
                    let child_width = child_size.width.saturating_sub(x);
                    let child_height = child_size.height.saturating_sub(y);
                    let rect = Rect {
                        origin: Point { x, y },
                        size: Size {
                            width: min_width
                                .max(child_width + self.config.container_padding)
                                .max(label_width(&label) + 2),
                            height: (child_height + self.config.container_padding)
                                .max(self.config.node_height),
                        },
                    };
                    layout.containers.push(PositionedBlockContainer {
                        id: container.id.as_ref().map(|id| id.value.clone()),
                        label,
                        rect,
                    });
                    size.width = size.width.max(rect.right());
                    size.height = size.height.max(rect.bottom());
                    column += span;
                    x += rect.size.width + self.config.horizontal_spacing;
                    row_height = row_height.max(rect.size.height);
                }
                BlockStatement::Edge(_)
                | BlockStatement::ClassDef(_)
                | BlockStatement::ClassApply(_)
                | BlockStatement::Style(_)
                | BlockStatement::Comment(_)
                | BlockStatement::Directive(_) => {}
            }
        }
        size
    }

    fn block_unit_width(
        &self,
        statements: &[BlockStatement],
        lookup: &HashMap<&str, &crate::ast::BlockNode>,
    ) -> i32 {
        let mut width = self.config.min_node_width;
        for statement in statements {
            match statement {
                BlockStatement::Node(node) => {
                    let node = lookup
                        .get(node.id.value.as_str())
                        .copied()
                        .unwrap_or(node.as_ref());
                    width = width.max(
                        label_width(&block_node_label(node)) + self.config.horizontal_padding * 2,
                    );
                }
                BlockStatement::Container(container) => {
                    width = width.max(self.block_unit_width(&container.statements, lookup));
                }
                BlockStatement::Columns(_)
                | BlockStatement::Space(_)
                | BlockStatement::Edge(_)
                | BlockStatement::ClassDef(_)
                | BlockStatement::ClassApply(_)
                | BlockStatement::Style(_)
                | BlockStatement::Comment(_)
                | BlockStatement::Directive(_) => {}
            }
        }
        width
    }

    fn layout_block_edges(
        &self,
        ast: &BlockDiagramAst,
        nodes: &[PositionedBlockNode],
    ) -> Vec<PositionedBlockEdge> {
        ast.edges
            .iter()
            .filter_map(|edge| {
                let from = block_node_rect(nodes, &edge.from.value)?;
                let to = block_node_rect(nodes, &edge.to.value)?;
                let (start, end) = block_edge_endpoints(from, to);
                let points = if start.y == end.y {
                    vec![start, end]
                } else {
                    let mid_x = (start.x + end.x) / 2;
                    vec![
                        start,
                        Point {
                            x: mid_x,
                            y: start.y,
                        },
                        Point { x: mid_x, y: end.y },
                        end,
                    ]
                };
                Some(PositionedBlockEdge {
                    from: edge.from.value.clone(),
                    to: edge.to.value.clone(),
                    label: edge.label.as_ref().map(|label| label.text.clone()),
                    arrow_start: edge.link.value.arrow_start,
                    arrow_end: edge.link.value.arrow_end,
                    points,
                })
            })
            .collect()
    }
}

fn block_span_width(unit_width: i32, spacing: i32, span: u16) -> i32 {
    let span = i32::from(span.max(1));
    unit_width * span + spacing * (span - 1)
}

fn block_node_label(node: &crate::ast::BlockNode) -> String {
    node.label
        .as_ref()
        .map_or_else(|| node.id.value.clone(), |label| label.text.clone())
}

fn block_node_rect(nodes: &[PositionedBlockNode], id: &str) -> Option<Rect> {
    nodes
        .iter()
        .find(|node| node.id == id)
        .map(|node| node.rect)
}

fn block_edge_endpoints(from: Rect, to: Rect) -> (Point, Point) {
    if from.center().x <= to.center().x {
        (
            Point {
                x: from.right().saturating_sub(1),
                y: from.center().y,
            },
            Point {
                x: to.origin.x,
                y: to.center().y,
            },
        )
    } else {
        (
            Point {
                x: from.origin.x,
                y: from.center().y,
            },
            Point {
                x: to.right().saturating_sub(1),
                y: to.center().y,
            },
        )
    }
}

fn block_edge_label_point(edge: &PositionedBlockEdge) -> Option<Point> {
    let first = edge.points.first()?;
    let last = edge.points.last()?;
    Some(Point {
        x: (first.x + last.x) / 2 + 1,
        y: (first.y + last.y) / 2,
    })
}

impl PacketLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: PacketLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: PacketLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &PacketAst) -> PacketLayout {
        let title = ast.title.as_ref().map(|title| title.text.clone());
        let row_offset = if title.is_some() {
            self.config.title_spacing
        } else {
            0
        };
        let max_row = ast
            .fields
            .iter()
            .map(|field| field.range.end.value / self.config.bits_per_row.max(1))
            .max()
            .unwrap_or(0);
        let rows = (0..=max_row)
            .map(|row| {
                let first_bit = row * self.config.bits_per_row.max(1);
                let last_bit = first_bit + self.config.bits_per_row.max(1) - 1;
                let label_y = row_offset
                    + row as i32 * (self.config.row_height + self.config.row_spacing + 1);
                PositionedPacketRow {
                    row,
                    first_bit,
                    last_bit,
                    label_y,
                    rect_y: label_y + 1,
                }
            })
            .collect::<Vec<_>>();
        let mut fields = Vec::new();
        for field in &ast.fields {
            let mut start = field.range.start.value;
            while start <= field.range.end.value {
                let row = start / self.config.bits_per_row.max(1);
                let row_last =
                    row * self.config.bits_per_row.max(1) + self.config.bits_per_row.max(1) - 1;
                let end = field.range.end.value.min(row_last);
                let bit_count = end - start + 1;
                fields.push(PositionedPacketField {
                    label: field.label.text.clone(),
                    range_label: packet_range_label(field.range.start.value, field.range.end.value),
                    start_bit: start,
                    end_bit: end,
                    row,
                    rect: Rect {
                        origin: Point {
                            x: ((start % self.config.bits_per_row.max(1)) as i32)
                                * self.config.bit_width,
                            y: row_offset
                                + row as i32
                                    * (self.config.row_height + self.config.row_spacing + 1)
                                + 1,
                        },
                        size: Size {
                            width: (bit_count as i32 * self.config.bit_width).max(3),
                            height: self.config.row_height,
                        },
                    },
                });
                if end == u32::MAX {
                    break;
                }
                start = end + 1;
            }
        }
        let mut size = Size {
            width: self.config.bits_per_row.max(1) as i32 * self.config.bit_width + 1,
            height: rows.last().map_or(self.config.row_height, |row| {
                row.rect_y + self.config.row_height
            }),
        };
        if let Some(title) = &title {
            size.width = size.width.max(label_width(title));
        }
        for field in &fields {
            size.width = size.width.max(field.rect.right());
            size.height = size.height.max(field.rect.bottom());
        }
        PacketLayout {
            title,
            rows,
            fields,
            size,
        }
    }
}

fn packet_range_label(start: u32, end: u32) -> String {
    if start == end {
        start.to_string()
    } else {
        format!("{start}-{end}")
    }
}

impl KanbanLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: KanbanLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: KanbanLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &KanbanAst) -> KanbanLayout {
        let mut columns = Vec::new();
        let mut tasks = Vec::new();
        let mut x = 0i32;
        let mut size = Size {
            width: self.config.column_min_width,
            height: self.config.header_height,
        };
        for (column_index, column) in ast.columns.iter().enumerate() {
            let column_width = self.kanban_column_width(column);
            let mut y = self.config.header_height + self.config.card_spacing;
            for task in &column.tasks {
                let metadata = task
                    .metadata
                    .iter()
                    .map(kanban_metadata_pair)
                    .collect::<Vec<_>>();
                let card_height = self.config.card_base_height + metadata.len() as i32;
                let rect = Rect {
                    origin: Point {
                        x: x + self.config.horizontal_padding,
                        y,
                    },
                    size: Size {
                        width: column_width - self.config.horizontal_padding * 2,
                        height: card_height,
                    },
                };
                tasks.push(PositionedKanbanTask {
                    column_index,
                    id: task.id.as_ref().map(|id| id.value.clone()),
                    label: task.label.text.clone(),
                    metadata,
                    rect,
                });
                y += card_height + self.config.card_spacing;
            }
            let column_height = y.max(self.config.header_height + self.config.card_spacing);
            let rect = Rect {
                origin: Point { x, y: 0 },
                size: Size {
                    width: column_width,
                    height: column_height,
                },
            };
            columns.push(PositionedKanbanColumn {
                id: column.id.as_ref().map(|id| id.value.clone()),
                title: column.title.text.clone(),
                header: Rect {
                    origin: rect.origin,
                    size: Size {
                        width: rect.size.width,
                        height: self.config.header_height,
                    },
                },
                rect,
            });
            size.width = size.width.max(rect.right());
            size.height = size.height.max(rect.bottom());
            x += column_width + self.config.column_spacing;
        }
        KanbanLayout {
            columns,
            tasks,
            size,
        }
    }

    fn kanban_column_width(&self, column: &KanbanColumn) -> i32 {
        let mut width = self
            .config
            .column_min_width
            .max(label_width(&column.title.text) + self.config.horizontal_padding * 2);
        for task in &column.tasks {
            width = width.max(label_width(&task.label.text) + self.config.horizontal_padding * 4);
            for metadata in &task.metadata {
                let (key, value) = kanban_metadata_pair(metadata);
                width = width.max(
                    label_width(&format!("{key}: {value}")) + self.config.horizontal_padding * 4,
                );
            }
        }
        width
    }
}

fn kanban_metadata_pair(metadata: &KanbanMetadata) -> (String, String) {
    (metadata.key.value.clone(), metadata.value.text.clone())
}

impl ArchitectureLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: ArchitectureLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: ArchitectureLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &ArchitectureAst) -> ArchitectureLayout {
        let context = ArchitectureLayoutContext::new(ast);
        let mut groups = Vec::new();
        let mut nodes = Vec::new();
        let mut size = Size {
            width: self.config.node_min_width,
            height: self.config.node_height,
        };
        let mut x = 0i32;
        for item in context.top_level_items() {
            let item_size = self.measure_item(&context, item);
            self.place_item(&context, item, Point { x, y: 0 }, &mut groups, &mut nodes);
            size.width = size.width.max(x + item_size.width);
            size.height = size.height.max(item_size.height);
            x += item_size.width + self.config.group_spacing;
        }
        let mut lookup = HashMap::new();
        for group in &groups {
            lookup.insert(group.id.clone(), group.rect);
        }
        for node in &nodes {
            lookup.insert(node.id.clone(), node.rect);
        }
        let edges = ast
            .edges
            .iter()
            .map(|edge| self.position_edge(edge, &lookup))
            .collect::<Vec<_>>();
        for edge in &edges {
            for point in &edge.points {
                size.width = size.width.max(point.x + 1);
                size.height = size.height.max(point.y + 1);
            }
        }
        let alignments = ast
            .alignments
            .iter()
            .map(|alignment| PositionedArchitectureAlignment {
                axis: alignment.axis.value,
                members: alignment
                    .members
                    .iter()
                    .map(|member| member.value.clone())
                    .collect(),
            })
            .collect();
        ArchitectureLayout {
            groups,
            nodes,
            edges,
            alignments,
            size,
        }
    }

    fn measure_item(
        &self,
        context: &ArchitectureLayoutContext<'_>,
        item: ArchitectureLayoutItem<'_>,
    ) -> Size {
        match item {
            ArchitectureLayoutItem::Group(group) => self.measure_group(context, group),
            ArchitectureLayoutItem::Service(service) => self.measure_service(service),
            ArchitectureLayoutItem::Junction(junction) => self.measure_junction(junction),
        }
    }

    fn measure_group(
        &self,
        context: &ArchitectureLayoutContext<'_>,
        group: &ArchitectureGroup,
    ) -> Size {
        let mut width = self
            .config
            .group_min_width
            .max(label_width(&architecture_group_label(group)) + self.config.group_padding * 2);
        if let Some(icon) = &group.icon {
            width = width.max(
                label_width(&architecture_icon_label(&icon.text)) + self.config.group_padding * 2,
            );
        }
        let mut height = self.config.group_title_height + self.config.group_padding;
        let children = context.child_items(&group.id.value);
        if children.is_empty() {
            height += self.config.group_padding;
        } else {
            for (index, child) in children.iter().enumerate() {
                let size = self.measure_item(context, *child);
                width = width.max(size.width + self.config.group_padding * 2);
                height += size.height;
                if index + 1 < children.len() {
                    height += self.config.item_spacing;
                }
            }
            height += self.config.group_padding;
        }
        Size { width, height }
    }

    fn measure_service(&self, service: &ArchitectureService) -> Size {
        let mut width = self
            .config
            .node_min_width
            .max(label_width(&architecture_service_label(service)) + 4);
        if let Some(icon) = &service.icon {
            width = width.max(label_width(&architecture_icon_label(&icon.text)) + 4);
        }
        Size {
            width,
            height: self.config.node_height,
        }
    }

    fn measure_junction(&self, junction: &ArchitectureJunction) -> Size {
        Size {
            width: self
                .config
                .node_min_width
                .max(label_width(&junction.id.value) + 6),
            height: self.config.junction_height,
        }
    }

    fn place_item(
        &self,
        context: &ArchitectureLayoutContext<'_>,
        item: ArchitectureLayoutItem<'_>,
        origin: Point,
        groups: &mut Vec<PositionedArchitectureGroup>,
        nodes: &mut Vec<PositionedArchitectureNode>,
    ) {
        match item {
            ArchitectureLayoutItem::Group(group) => {
                let size = self.measure_group(context, group);
                let rect = Rect { origin, size };
                groups.push(PositionedArchitectureGroup {
                    id: group.id.value.clone(),
                    label: architecture_group_label(group),
                    icon: group
                        .icon
                        .as_ref()
                        .map(|icon| architecture_icon_label(&icon.text)),
                    parent: group.parent.as_ref().map(|parent| parent.value.clone()),
                    header: Rect {
                        origin,
                        size: Size {
                            width: size.width,
                            height: self.config.group_title_height,
                        },
                    },
                    rect,
                });
                let mut y = origin.y + self.config.group_title_height + self.config.group_padding;
                for child in context.child_items(&group.id.value) {
                    let child_size = self.measure_item(context, child);
                    self.place_item(
                        context,
                        child,
                        Point {
                            x: origin.x + self.config.group_padding,
                            y,
                        },
                        groups,
                        nodes,
                    );
                    y += child_size.height + self.config.item_spacing;
                }
            }
            ArchitectureLayoutItem::Service(service) => {
                nodes.push(PositionedArchitectureNode {
                    id: service.id.value.clone(),
                    label: architecture_service_label(service),
                    icon: service
                        .icon
                        .as_ref()
                        .map(|icon| architecture_icon_label(&icon.text)),
                    parent: service.parent.as_ref().map(|parent| parent.value.clone()),
                    kind: ArchitectureNodeKind::Service,
                    rect: Rect {
                        origin,
                        size: self.measure_service(service),
                    },
                });
            }
            ArchitectureLayoutItem::Junction(junction) => {
                nodes.push(PositionedArchitectureNode {
                    id: junction.id.value.clone(),
                    label: junction.id.value.clone(),
                    icon: None,
                    parent: junction.parent.as_ref().map(|parent| parent.value.clone()),
                    kind: ArchitectureNodeKind::Junction,
                    rect: Rect {
                        origin,
                        size: self.measure_junction(junction),
                    },
                });
            }
        }
    }

    fn position_edge(
        &self,
        edge: &ArchitectureEdge,
        lookup: &HashMap<String, Rect>,
    ) -> PositionedArchitectureEdge {
        let from_rect = lookup.get(&edge.from.id.value).copied().unwrap_or(Rect {
            origin: Point { x: 0, y: 0 },
            size: Size {
                width: self.config.node_min_width,
                height: self.config.node_height,
            },
        });
        let to_rect = lookup.get(&edge.to.id.value).copied().unwrap_or(from_rect);
        let from = architecture_side_point(from_rect, edge.from.side.value);
        let to = architecture_side_point(to_rect, edge.to.side.value);
        let mid_x = (from.x + to.x) / 2;
        let points = if from.x == to.x || from.y == to.y {
            vec![from, to]
        } else {
            vec![
                from,
                Point {
                    x: mid_x,
                    y: from.y,
                },
                Point { x: mid_x, y: to.y },
                to,
            ]
        };
        PositionedArchitectureEdge {
            from: edge.from.id.value.clone(),
            to: edge.to.id.value.clone(),
            from_side: edge.from.side.value,
            to_side: edge.to.side.value,
            from_group: edge.from.group,
            to_group: edge.to.group,
            arrow_start: edge.arrow_start,
            arrow_end: edge.arrow_end,
            points,
        }
    }
}

#[derive(Debug, Clone, Copy)]
enum ArchitectureLayoutItem<'a> {
    Group(&'a ArchitectureGroup),
    Service(&'a ArchitectureService),
    Junction(&'a ArchitectureJunction),
}

struct ArchitectureLayoutContext<'a> {
    groups: &'a [ArchitectureGroup],
    services: &'a [ArchitectureService],
    junctions: &'a [ArchitectureJunction],
    group_ids: HashSet<&'a str>,
}

impl<'a> ArchitectureLayoutContext<'a> {
    fn new(ast: &'a ArchitectureAst) -> Self {
        Self {
            groups: &ast.groups,
            services: &ast.services,
            junctions: &ast.junctions,
            group_ids: ast
                .groups
                .iter()
                .map(|group| group.id.value.as_str())
                .collect(),
        }
    }

    fn top_level_items(&self) -> Vec<ArchitectureLayoutItem<'a>> {
        let mut items = Vec::new();
        for group in self.groups {
            if group
                .parent
                .as_ref()
                .is_none_or(|parent| !self.group_ids.contains(parent.value.as_str()))
            {
                items.push(ArchitectureLayoutItem::Group(group));
            }
        }
        for service in self.services {
            if service
                .parent
                .as_ref()
                .is_none_or(|parent| !self.group_ids.contains(parent.value.as_str()))
            {
                items.push(ArchitectureLayoutItem::Service(service));
            }
        }
        for junction in self.junctions {
            if junction
                .parent
                .as_ref()
                .is_none_or(|parent| !self.group_ids.contains(parent.value.as_str()))
            {
                items.push(ArchitectureLayoutItem::Junction(junction));
            }
        }
        items
    }

    fn child_items(&self, group_id: &str) -> Vec<ArchitectureLayoutItem<'a>> {
        let mut items = Vec::new();
        for group in self.groups {
            if group
                .parent
                .as_ref()
                .is_some_and(|parent| parent.value == group_id)
            {
                items.push(ArchitectureLayoutItem::Group(group));
            }
        }
        for service in self.services {
            if service
                .parent
                .as_ref()
                .is_some_and(|parent| parent.value == group_id)
            {
                items.push(ArchitectureLayoutItem::Service(service));
            }
        }
        for junction in self.junctions {
            if junction
                .parent
                .as_ref()
                .is_some_and(|parent| parent.value == group_id)
            {
                items.push(ArchitectureLayoutItem::Junction(junction));
            }
        }
        items
    }
}

fn architecture_group_label(group: &ArchitectureGroup) -> String {
    group
        .title
        .as_ref()
        .map_or_else(|| group.id.value.clone(), |title| title.text.clone())
}

fn architecture_service_label(service: &ArchitectureService) -> String {
    service
        .title
        .as_ref()
        .map_or_else(|| service.id.value.clone(), |title| title.text.clone())
}

fn architecture_icon_label(icon: &str) -> String {
    format!("({icon})")
}

fn architecture_side_point(rect: Rect, side: ArchitectureSide) -> Point {
    match side {
        ArchitectureSide::Top => Point {
            x: rect.center().x,
            y: rect.origin.y,
        },
        ArchitectureSide::Bottom => Point {
            x: rect.center().x,
            y: rect.bottom(),
        },
        ArchitectureSide::Left => Point {
            x: rect.origin.x,
            y: rect.center().y,
        },
        ArchitectureSide::Right => Point {
            x: rect.right(),
            y: rect.center().y,
        },
    }
}

impl RadarLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: RadarLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: RadarLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &RadarAst) -> RadarLayout {
        let axis_labels = ast
            .axes
            .iter()
            .map(|axis| {
                axis.label
                    .as_ref()
                    .map_or_else(|| axis.id.value.clone(), |label| label.text.clone())
            })
            .collect::<Vec<_>>();
        let label_pad = axis_labels
            .iter()
            .map(|label| label_width(label))
            .max()
            .unwrap_or(0)
            .max(4);
        let title_offset = ast.title.as_ref().map_or(0, |_| self.config.title_spacing);
        let center = Point {
            x: label_pad + self.config.radius + 2,
            y: title_offset + self.config.radius + 1,
        };
        let (min, max) = radar_scale(ast);
        let axes = ast
            .axes
            .iter()
            .enumerate()
            .map(|(index, axis)| {
                let angle = radar_angle(index, ast.axes.len());
                let end = radar_point(center, angle, self.config.radius);
                let label = axis
                    .label
                    .as_ref()
                    .map_or_else(|| axis.id.value.clone(), |label| label.text.clone());
                let label_origin = radar_label_origin(center, end, &label);
                PositionedRadarAxis {
                    id: axis.id.value.clone(),
                    label,
                    end,
                    label_origin,
                }
            })
            .collect::<Vec<_>>();
        let axis_index = ast
            .axes
            .iter()
            .enumerate()
            .map(|(index, axis)| (axis.id.value.as_str(), index))
            .collect::<HashMap<_, _>>();
        let show_legend = radar_show_legend(ast);
        let legend_x = center.x + self.config.radius + label_pad + self.config.legend_spacing;
        let legend_y = title_offset;
        let curves = ast
            .curves
            .iter()
            .enumerate()
            .map(|(curve_index, curve)| {
                let marker = radar_curve_marker(curve_index);
                let label = curve
                    .label
                    .as_ref()
                    .map_or_else(|| curve.id.value.clone(), |label| label.text.clone());
                let points = radar_curve_points(
                    curve,
                    &axis_index,
                    ast.axes.len(),
                    center,
                    min,
                    max,
                    self.config.radius,
                );
                PositionedRadarCurve {
                    id: curve.id.value.clone(),
                    label,
                    marker,
                    points,
                    legend_origin: show_legend.then_some(Point {
                        x: legend_x,
                        y: legend_y + curve_index as i32,
                    }),
                }
            })
            .collect::<Vec<_>>();
        let rings = radar_rings(center, ast.axes.len(), self.config.radius, radar_ticks(ast));
        let mut size = Size {
            width: center.x + self.config.radius + label_pad + 1,
            height: center.y + self.config.radius + 1,
        };
        if let Some(title) = &ast.title {
            size.width = size.width.max(label_width(&title.text) + 1);
        }
        for axis in &axes {
            size.width = size
                .width
                .max(axis.label_origin.x + label_width(&axis.label) + 1);
            size.height = size.height.max(axis.label_origin.y + 1);
        }
        if show_legend {
            for curve in &curves {
                if let Some(origin) = curve.legend_origin {
                    size.width = size
                        .width
                        .max(origin.x + label_width(&radar_legend_label(curve)) + 1);
                    size.height = size.height.max(origin.y + 1);
                }
            }
        }
        RadarLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            axes,
            curves,
            rings,
            center,
            show_legend,
            min_value: radar_number_label(min),
            max_value: radar_number_label(max),
            size,
        }
    }
}

fn radar_scale(ast: &RadarAst) -> (f64, f64) {
    let mut min = radar_option_number(ast, RadarOptionKind::Min).unwrap_or(0.0);
    let mut max = radar_option_number(ast, RadarOptionKind::Max).unwrap_or_else(|| {
        ast.curves
            .iter()
            .flat_map(|curve| &curve.values)
            .filter_map(|value| value.value.value.parse::<f64>().ok())
            .fold(0.0_f64, f64::max)
    });
    if max <= min {
        max = min + 1.0;
    }
    if !min.is_finite() {
        min = 0.0;
    }
    if !max.is_finite() {
        max = 1.0;
    }
    (min, max)
}

fn radar_option_number(ast: &RadarAst, kind: RadarOptionKind) -> Option<f64> {
    ast.options
        .iter()
        .rev()
        .find(|option| option.kind.value == kind)
        .and_then(|option| option.value.value.parse::<f64>().ok())
}

fn radar_show_legend(ast: &RadarAst) -> bool {
    ast.options
        .iter()
        .rev()
        .find(|option| option.kind.value == RadarOptionKind::ShowLegend)
        .is_none_or(|option| option.value.value == "true")
}

fn radar_ticks(ast: &RadarAst) -> usize {
    ast.options
        .iter()
        .rev()
        .find(|option| option.kind.value == RadarOptionKind::Ticks)
        .and_then(|option| option.value.value.parse::<usize>().ok())
        .filter(|ticks| *ticks > 0)
        .unwrap_or(5)
}

fn radar_curve_points(
    curve: &RadarCurve,
    axis_index: &HashMap<&str, usize>,
    axis_count: usize,
    center: Point,
    min: f64,
    max: f64,
    radius: i32,
) -> Vec<PositionedRadarPoint> {
    curve
        .values
        .iter()
        .enumerate()
        .filter_map(|(value_index, value)| {
            let axis_position = value
                .axis
                .as_ref()
                .and_then(|axis| axis_index.get(axis.value.as_str()).copied())
                .unwrap_or(value_index);
            (axis_position < axis_count).then(|| {
                let raw = value.value.value.parse::<f64>().unwrap_or(min);
                let scaled = ((raw - min) / (max - min)).clamp(0.0, 1.0);
                let point = radar_point(
                    center,
                    radar_angle(axis_position, axis_count),
                    (scaled * f64::from(radius)).round() as i32,
                );
                PositionedRadarPoint {
                    axis_id: value
                        .axis
                        .as_ref()
                        .map_or_else(|| axis_position.to_string(), |axis| axis.value.clone()),
                    value: value.value.value.clone(),
                    point,
                }
            })
        })
        .collect()
}

fn radar_rings(center: Point, axis_count: usize, radius: i32, ticks: usize) -> Vec<Vec<Point>> {
    if axis_count == 0 {
        return Vec::new();
    }
    (1..=ticks)
        .map(|tick| {
            let ring_radius = ((tick as f64 / ticks as f64) * f64::from(radius)).round() as i32;
            (0..axis_count)
                .map(|index| radar_point(center, radar_angle(index, axis_count), ring_radius))
                .collect()
        })
        .collect()
}

fn radar_angle(index: usize, count: usize) -> f64 {
    if count == 0 {
        return 0.0;
    }
    -std::f64::consts::FRAC_PI_2 + std::f64::consts::TAU * (index as f64 / count as f64)
}

fn radar_point(center: Point, angle: f64, radius: i32) -> Point {
    Point {
        x: center.x + (angle.cos() * f64::from(radius)).round() as i32,
        y: center.y + (angle.sin() * f64::from(radius)).round() as i32,
    }
}

fn radar_label_origin(center: Point, end: Point, label: &str) -> Point {
    let width = label_width(label);
    let x = if end.x < center.x {
        end.x - width - 1
    } else if end.x > center.x {
        end.x + 1
    } else {
        end.x - width / 2
    };
    let y = if end.y < center.y {
        end.y.saturating_sub(1)
    } else if end.y > center.y {
        end.y + 1
    } else {
        end.y
    };
    Point {
        x: x.max(0),
        y: y.max(0),
    }
}

fn radar_curve_marker(index: usize) -> char {
    const MARKERS: &[u8] = b"123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    MARKERS.get(index).copied().map(char::from).unwrap_or('*')
}

fn radar_legend_label(curve: &PositionedRadarCurve) -> String {
    let values = curve
        .points
        .iter()
        .map(|point| point.value.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    format!("{} {}: {}", curve.marker, curve.label, values)
}

fn radar_number_label(value: f64) -> String {
    let rounded = value.round();
    if (value - rounded).abs() < f64::EPSILON {
        format!("{rounded:.0}")
    } else {
        value.to_string()
    }
}

impl EventModelingLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: EventModelingLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: EventModelingLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &EventModelingAst) -> EventModelingLayout {
        let mut lane_ids = Vec::<String>::new();
        let mut lane_titles = Vec::<String>::new();
        let mut lane_index_by_id = HashMap::<String, usize>::new();
        let mut frames = Vec::<PositionedEventModelingFrame>::new();
        for (index, frame) in ast.timeframes.iter().enumerate() {
            let lane = event_modeling_lane_id(&frame.entity.value, frame.entity_type.value);
            let lane_index = if let Some(index) = lane_index_by_id.get(&lane.id) {
                *index
            } else {
                let index = lane_ids.len();
                lane_index_by_id.insert(lane.id.clone(), index);
                lane_ids.push(lane.id.clone());
                lane_titles.push(lane.title.clone());
                index
            };
            let x = self.config.lane_label_width
                + 2
                + index as i32 * (self.config.node_width + self.config.column_spacing);
            let y = self.config.top_padding
                + lane_index as i32 * (self.config.node_height + self.config.lane_spacing);
            frames.push(PositionedEventModelingFrame {
                number: frame.number.value.clone(),
                entity: frame.entity.value.clone(),
                entity_type: frame.entity_type.value,
                frame_kind: frame.kind.value,
                data_ref: frame
                    .data_ref
                    .as_ref()
                    .map(|data_ref| data_ref.value.clone()),
                data_summary: frame
                    .data
                    .as_ref()
                    .map(|data| event_modeling_data_summary(&data.body.text)),
                rect: Rect {
                    origin: Point { x, y },
                    size: Size {
                        width: self.config.node_width,
                        height: self.config.node_height,
                    },
                },
                lane_index,
            });
        }
        let lane_height = self.config.node_height;
        let lanes = lane_ids
            .iter()
            .enumerate()
            .map(|(index, id)| PositionedEventModelingLane {
                id: id.clone(),
                title: lane_titles[index].clone(),
                y: self.config.top_padding
                    + index as i32 * (self.config.node_height + self.config.lane_spacing),
                height: lane_height,
            })
            .collect::<Vec<_>>();
        let frame_index = ast
            .timeframes
            .iter()
            .enumerate()
            .map(|(index, frame)| (frame.number.value.as_str(), index))
            .collect::<HashMap<_, _>>();
        let mut relations = Vec::new();
        for index in 1..frames.len() {
            if ast.timeframes[index - 1].kind.value == EventModelingFrameKind::TimeFrame
                && ast.timeframes[index].kind.value == EventModelingFrameKind::TimeFrame
            {
                relations.push(event_modeling_relation(index - 1, index, &frames, false));
            }
        }
        for (from_index, frame) in ast.timeframes.iter().enumerate() {
            for relation in &frame.relations {
                if let Some(to_index) = frame_index.get(relation.value.as_str()).copied() {
                    relations.push(event_modeling_relation(from_index, to_index, &frames, true));
                }
            }
        }
        let data_y = self.config.top_padding
            + lanes.len() as i32 * (self.config.node_height + self.config.lane_spacing)
            + 1;
        let data_blocks = ast
            .data_blocks
            .iter()
            .enumerate()
            .map(|(index, block)| event_modeling_data_block(block, data_y + index as i32))
            .collect::<Vec<_>>();
        let mut size = Size {
            width: self.config.lane_label_width + 4,
            height: data_y.max(1),
        };
        for lane in &lanes {
            size.width = size
                .width
                .max(self.config.lane_label_width.max(label_width(&lane.title)) + 4);
            size.height = size.height.max(lane.y + lane.height + 1);
        }
        for frame in &frames {
            size.width = size.width.max(frame.rect.right() + 2);
            size.height = size.height.max(frame.rect.bottom() + 1);
        }
        for block in &data_blocks {
            size.width = size
                .width
                .max(block.origin.x + label_width(&event_modeling_data_block_label(block)) + 1);
            size.height = size.height.max(block.origin.y + 1);
        }
        EventModelingLayout {
            lanes,
            frames,
            relations,
            data_blocks,
            size,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct EventModelingLane {
    id: String,
    title: String,
}

fn event_modeling_lane_id(entity: &str, entity_type: EventModelingEntityType) -> EventModelingLane {
    let group = event_modeling_lane_group(entity_type);
    if let Some((namespace, _)) = entity.split_once('.') {
        return EventModelingLane {
            id: format!("{namespace}:{group}"),
            title: format!("{namespace} {group}"),
        };
    }
    EventModelingLane {
        id: group.to_owned(),
        title: group.to_owned(),
    }
}

fn event_modeling_lane_group(entity_type: EventModelingEntityType) -> &'static str {
    match entity_type {
        EventModelingEntityType::Ui | EventModelingEntityType::Processor => "UI / Automation",
        EventModelingEntityType::Command | EventModelingEntityType::ReadModel => {
            "Command / Read Model"
        }
        EventModelingEntityType::Event => "Events",
    }
}

fn event_modeling_relation(
    from_index: usize,
    to_index: usize,
    frames: &[PositionedEventModelingFrame],
    explicit: bool,
) -> PositionedEventModelingRelation {
    let from = frames[from_index].rect;
    let to = frames[to_index].rect;
    let start = Point {
        x: from.right(),
        y: from.center().y,
    };
    let end = Point {
        x: to.origin.x,
        y: to.center().y,
    };
    let mid_x = (start.x + end.x) / 2;
    PositionedEventModelingRelation {
        from_index,
        to_index,
        points: vec![
            start,
            Point {
                x: mid_x,
                y: start.y,
            },
            Point { x: mid_x, y: end.y },
            end,
        ],
        explicit,
    }
}

fn event_modeling_data_block(
    block: &EventModelingDataBlock,
    y: i32,
) -> PositionedEventModelingDataBlock {
    PositionedEventModelingDataBlock {
        id: block.id.value.clone(),
        ty: block.data.ty.as_ref().map(|ty| ty.value.clone()),
        summary: event_modeling_data_summary(&block.data.body.text),
        origin: Point { x: 0, y },
    }
}

fn event_modeling_data_summary(value: &str) -> String {
    let compact = value.split_whitespace().collect::<Vec<_>>().join(" ");
    if compact.chars().count() > 32 {
        let prefix = compact.chars().take(29).collect::<String>();
        format!("{prefix}...")
    } else {
        compact
    }
}

fn event_modeling_data_block_label(block: &PositionedEventModelingDataBlock) -> String {
    match &block.ty {
        Some(ty) => format!("data {}({ty}): {}", block.id, block.summary),
        None => format!("data {}: {}", block.id, block.summary),
    }
}

impl TreemapLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: TreemapLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: TreemapLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &TreemapAst) -> TreemapLayout {
        let mut nodes = Vec::new();
        let root_rect = Rect {
            origin: Point { x: 0, y: 0 },
            size: Size {
                width: self.config.width,
                height: self.config.height,
            },
        };
        layout_treemap_nodes(
            &ast.roots,
            root_rect,
            0,
            true,
            self.config.padding,
            &mut nodes,
        );
        let mut size = Size {
            width: self.config.width,
            height: self.config.height,
        };
        for node in &nodes {
            size.width = size.width.max(node.rect.right() + 1);
            size.height = size.height.max(node.rect.bottom() + 1);
        }
        TreemapLayout { nodes, size }
    }
}

fn layout_treemap_nodes(
    source: &[TreemapNode],
    rect: Rect,
    depth: usize,
    horizontal: bool,
    padding: i32,
    out: &mut Vec<PositionedTreemapNode>,
) {
    if source.is_empty() || rect.size.width <= 0 || rect.size.height <= 0 {
        return;
    }
    let weights = source.iter().map(treemap_weight).collect::<Vec<_>>();
    let rects = split_treemap_rects(rect, &weights, horizontal);
    for (node, rect) in source.iter().zip(rects) {
        let aggregate = treemap_weight(node);
        out.push(PositionedTreemapNode {
            label: node.label.text.clone(),
            value: node.value.as_ref().map(|value| value.value.clone()),
            aggregate_value: treemap_number_label(aggregate),
            classes: node
                .classes
                .iter()
                .map(|class| class.value.clone())
                .collect(),
            rect,
            depth,
        });
        if let Some(child_rect) = treemap_child_rect(rect, padding) {
            layout_treemap_nodes(
                &node.children,
                child_rect,
                depth + 1,
                !horizontal,
                padding,
                out,
            );
        }
    }
}

fn split_treemap_rects(rect: Rect, weights: &[f64], horizontal: bool) -> Vec<Rect> {
    if weights.len() <= 1 {
        return vec![rect; weights.len()];
    }
    let total = weights
        .iter()
        .copied()
        .filter(|value| *value > 0.0)
        .sum::<f64>()
        .max(1.0);
    let mut offset = 0;
    let mut remaining = if horizontal {
        rect.size.width
    } else {
        rect.size.height
    };
    let mut rects = Vec::with_capacity(weights.len());
    for (index, weight) in weights.iter().enumerate() {
        let last = index + 1 == weights.len();
        let extent = if last {
            remaining
        } else {
            let raw = ((if horizontal {
                rect.size.width
            } else {
                rect.size.height
            }) as f64
                * (*weight / total))
                .round() as i32;
            raw.max(1).min(remaining.saturating_sub(1))
        };
        let child = if horizontal {
            Rect {
                origin: Point {
                    x: rect.origin.x + offset,
                    y: rect.origin.y,
                },
                size: Size {
                    width: extent,
                    height: rect.size.height,
                },
            }
        } else {
            Rect {
                origin: Point {
                    x: rect.origin.x,
                    y: rect.origin.y + offset,
                },
                size: Size {
                    width: rect.size.width,
                    height: extent,
                },
            }
        };
        rects.push(child);
        offset += extent;
        remaining = remaining.saturating_sub(extent);
    }
    rects
}

fn treemap_child_rect(rect: Rect, padding: i32) -> Option<Rect> {
    let child = Rect {
        origin: Point {
            x: rect.origin.x + padding,
            y: rect.origin.y + 2,
        },
        size: Size {
            width: rect.size.width - padding * 2,
            height: rect.size.height - padding - 2,
        },
    };
    (child.size.width >= 4 && child.size.height >= 3).then_some(child)
}

fn treemap_weight(node: &TreemapNode) -> f64 {
    if let Some(value) = &node.value
        && let Ok(parsed) = value.value.parse::<f64>()
        && parsed.is_finite()
        && parsed > 0.0
    {
        return parsed;
    }
    let child_total = node.children.iter().map(treemap_weight).sum::<f64>();
    if child_total > 0.0 { child_total } else { 1.0 }
}

fn treemap_number_label(value: f64) -> String {
    let rounded = value.round();
    if (value - rounded).abs() < f64::EPSILON {
        format!("{rounded:.0}")
    } else {
        value.to_string()
    }
}

impl VennLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: VennLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: VennLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &VennAst) -> VennLayout {
        let title_offset = ast.title.as_ref().map_or(0, |_| self.config.title_spacing);
        let centers = venn_centers(
            ast.sets.len(),
            self.config.width,
            self.config.height,
            title_offset,
        );
        let sets = ast
            .sets
            .iter()
            .zip(centers.iter())
            .map(|(set, center)| positioned_venn_set(set, *center, self.config))
            .collect::<Vec<_>>();
        let set_index = sets
            .iter()
            .enumerate()
            .map(|(index, set)| (set.id.as_str(), index))
            .collect::<HashMap<_, _>>();
        let unions = ast
            .unions
            .iter()
            .map(|union| positioned_venn_union(union, &sets, &set_index))
            .collect::<Vec<_>>();
        let style_y = title_offset + self.config.height + 1;
        let styles = ast
            .styles
            .iter()
            .enumerate()
            .map(|(index, style)| positioned_venn_style(style, style_y + index as i32))
            .collect::<Vec<_>>();
        let mut size = Size {
            width: self.config.width + 1,
            height: title_offset + self.config.height + 1,
        };
        if let Some(title) = &ast.title {
            size.width = size.width.max(label_width(&title.text) + 1);
        }
        for style in &styles {
            size.width = size
                .width
                .max(style.origin.x + label_width(&venn_style_label(style)) + 1);
            size.height = size.height.max(style.origin.y + 1);
        }
        VennLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            sets,
            unions,
            styles,
            size,
        }
    }
}

fn positioned_venn_set(
    set: &VennSet,
    center: Point,
    config: VennLayoutConfig,
) -> PositionedVennSet {
    PositionedVennSet {
        id: set.id.value.clone(),
        label: set
            .label
            .as_ref()
            .map_or_else(|| set.id.value.clone(), |label| label.text.clone()),
        size: set.size.as_ref().map(|size| size.value.clone()),
        center,
        radius_x: config.radius_x,
        radius_y: config.radius_y,
        texts: set.texts.iter().map(venn_text_label).collect(),
    }
}

fn positioned_venn_union(
    union: &VennUnion,
    sets: &[PositionedVennSet],
    set_index: &HashMap<&str, usize>,
) -> PositionedVennUnion {
    let members = union
        .members
        .iter()
        .map(|member| member.value.clone())
        .collect::<Vec<_>>();
    let points = union
        .members
        .iter()
        .filter_map(|member| {
            set_index
                .get(member.value.as_str())
                .map(|index| sets[*index].center)
        })
        .collect::<Vec<_>>();
    let point = if points.is_empty() {
        Point { x: 0, y: 0 }
    } else {
        Point {
            x: points.iter().map(|point| point.x).sum::<i32>() / points.len() as i32,
            y: points.iter().map(|point| point.y).sum::<i32>() / points.len() as i32,
        }
    };
    PositionedVennUnion {
        members,
        label: union.label.as_ref().map(|label| label.text.clone()),
        size: union.size.as_ref().map(|size| size.value.clone()),
        point,
        texts: union.texts.iter().map(venn_text_label).collect(),
    }
}

fn positioned_venn_style(style: &VennStyle, y: i32) -> PositionedVennStyle {
    PositionedVennStyle {
        targets: style
            .targets
            .iter()
            .map(|target| target.value.clone())
            .collect(),
        declarations: style
            .declarations
            .iter()
            .map(|declaration| format!("{}={}", declaration.key.value, declaration.value.value))
            .collect(),
        origin: Point { x: 0, y },
    }
}

fn venn_centers(count: usize, width: i32, height: i32, title_offset: i32) -> Vec<Point> {
    let center_y = title_offset + height / 2;
    match count {
        0 => Vec::new(),
        1 => vec![Point {
            x: width / 2,
            y: center_y,
        }],
        2 => vec![
            Point {
                x: width / 2 - 9,
                y: center_y,
            },
            Point {
                x: width / 2 + 9,
                y: center_y,
            },
        ],
        3 => vec![
            Point {
                x: width / 2 - 10,
                y: center_y - 3,
            },
            Point {
                x: width / 2 + 10,
                y: center_y - 3,
            },
            Point {
                x: width / 2,
                y: center_y + 4,
            },
        ],
        _ => (0..count)
            .map(|index| {
                let angle = -std::f64::consts::FRAC_PI_2
                    + std::f64::consts::TAU * (index as f64 / count as f64);
                Point {
                    x: width / 2 + (angle.cos() * f64::from(width / 4)).round() as i32,
                    y: center_y + (angle.sin() * f64::from(height / 4)).round() as i32,
                }
            })
            .collect(),
    }
}

fn venn_text_label(text: &VennText) -> String {
    text.label
        .as_ref()
        .map_or_else(|| text.id.value.clone(), |label| label.text.clone())
}

fn venn_style_label(style: &PositionedVennStyle) -> String {
    format!(
        "style {}: {}",
        style.targets.join(","),
        style.declarations.join(", ")
    )
}

impl IshikawaLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: IshikawaLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: IshikawaLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &IshikawaAst) -> IshikawaLayout {
        let event_width = (label_width(&ast.event.text) + self.config.node_padding * 2)
            .max(self.config.min_node_width);
        let spine_start = Point {
            x: 2,
            y: self.config.spine_y,
        };
        let spine_end = Point {
            x: self.config.width - event_width - 5,
            y: self.config.spine_y,
        };
        let event_rect = Rect {
            origin: Point {
                x: spine_end.x + 2,
                y: self.config.spine_y - self.config.node_height / 2,
            },
            size: Size {
                width: event_width,
                height: self.config.node_height,
            },
        };
        let anchors = ishikawa_root_anchors(
            ast.causes.len(),
            spine_start.x + 3,
            spine_end.x.saturating_sub(3),
        );
        let mut nodes = Vec::new();
        let mut edges = Vec::new();
        for (index, cause) in ast.causes.iter().enumerate() {
            let direction = if index % 2 == 0 { -1 } else { 1 };
            let anchor = Point {
                x: anchors.get(index).copied().unwrap_or(spine_start.x + 8),
                y: self.config.spine_y,
            };
            let mut slot = 0;
            layout_ishikawa_branch(
                cause,
                0,
                anchor,
                direction,
                &mut slot,
                None,
                self.config,
                &mut nodes,
                &mut edges,
            );
        }
        let mut layout = IshikawaLayout {
            event: ast.event.text.clone(),
            event_rect,
            spine_start,
            spine_end,
            nodes,
            edges,
            size: Size {
                width: self.config.width,
                height: self.config.spine_y + self.config.root_offset + self.config.node_height + 2,
            },
        };
        normalize_ishikawa_layout(&mut layout);
        layout
    }
}

fn ishikawa_root_anchors(count: usize, start_x: i32, end_x: i32) -> Vec<i32> {
    if count == 0 {
        return Vec::new();
    }
    let span = (end_x - start_x).max(1);
    (0..count)
        .map(|index| start_x + ((index + 1) as i32 * span / (count + 1) as i32))
        .collect()
}

#[allow(clippy::too_many_arguments)]
fn layout_ishikawa_branch(
    node: &IshikawaNode,
    depth: usize,
    anchor: Point,
    direction: i32,
    slot: &mut i32,
    parent: Option<usize>,
    config: IshikawaLayoutConfig,
    nodes: &mut Vec<PositionedIshikawaNode>,
    edges: &mut Vec<PositionedIshikawaEdge>,
) {
    let width =
        (label_width(&node.label.text) + config.node_padding * 2).max(config.min_node_width);
    let distance = config.root_offset + *slot * config.row_spacing;
    let center = Point {
        x: anchor.x - depth as i32 * config.child_indent,
        y: anchor.y + direction * distance,
    };
    let rect = Rect {
        origin: Point {
            x: center.x - width / 2,
            y: center.y - config.node_height / 2,
        },
        size: Size {
            width,
            height: config.node_height,
        },
    };
    let index = nodes.len();
    nodes.push(PositionedIshikawaNode {
        label: node.label.text.clone(),
        rect,
        depth,
    });
    let from = parent
        .map(|parent| ishikawa_node_anchor(nodes[parent].rect, direction))
        .unwrap_or(anchor);
    edges.push(PositionedIshikawaEdge {
        from,
        to: ishikawa_node_anchor(rect, -direction),
    });
    *slot += 1;
    for child in &node.causes {
        layout_ishikawa_branch(
            child,
            depth + 1,
            anchor,
            direction,
            slot,
            Some(index),
            config,
            nodes,
            edges,
        );
    }
}

fn ishikawa_node_anchor(rect: Rect, direction: i32) -> Point {
    if direction < 0 {
        Point {
            x: rect.center().x,
            y: rect.origin.y,
        }
    } else {
        Point {
            x: rect.center().x,
            y: rect.bottom().saturating_sub(1),
        }
    }
}

fn normalize_ishikawa_layout(layout: &mut IshikawaLayout) {
    let min_x = layout
        .nodes
        .iter()
        .map(|node| node.rect.origin.x)
        .min()
        .unwrap_or(layout.spine_start.x)
        .min(layout.spine_start.x)
        .min(layout.event_rect.origin.x)
        .min(0);
    if min_x < 0 {
        let shift = -min_x + 1;
        layout.spine_start.x += shift;
        layout.spine_end.x += shift;
        layout.event_rect.origin.x += shift;
        for node in &mut layout.nodes {
            node.rect.origin.x += shift;
        }
        for edge in &mut layout.edges {
            edge.from.x += shift;
            edge.to.x += shift;
        }
    }
    let mut min_y = layout
        .nodes
        .iter()
        .map(|node| node.rect.origin.y)
        .min()
        .unwrap_or(layout.spine_start.y)
        .min(layout.event_rect.origin.y)
        .min(layout.spine_start.y);
    min_y = min_y.min(0);
    if min_y < 0 {
        let shift = -min_y + 1;
        layout.spine_start.y += shift;
        layout.spine_end.y += shift;
        layout.event_rect.origin.y += shift;
        for node in &mut layout.nodes {
            node.rect.origin.y += shift;
        }
        for edge in &mut layout.edges {
            edge.from.y += shift;
            edge.to.y += shift;
        }
    }
    let max_right = layout
        .nodes
        .iter()
        .map(|node| node.rect.right())
        .chain(std::iter::once(layout.event_rect.right()))
        .chain(std::iter::once(layout.spine_end.x + 1))
        .max()
        .unwrap_or(layout.size.width);
    let max_bottom = layout
        .nodes
        .iter()
        .map(|node| node.rect.bottom())
        .chain(std::iter::once(layout.event_rect.bottom()))
        .chain(std::iter::once(layout.spine_start.y + 1))
        .max()
        .unwrap_or(layout.size.height);
    layout.size = Size {
        width: layout.size.width.max(max_right + 1),
        height: layout.size.height.max(max_bottom + 1),
    };
}

impl WardleyLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: WardleyLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: WardleyLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &WardleyAst) -> WardleyLayout {
        let title_offset = ast.title.as_ref().map_or(0, |_| 2);
        let plot = Rect {
            origin: Point {
                x: self.config.margin_left,
                y: self.config.margin_top + title_offset,
            },
            size: Size {
                width: self.config.plot_width,
                height: self.config.plot_height,
            },
        };
        let components = ast
            .components
            .iter()
            .map(|component| {
                let point = wardley_point(&component.coord, plot);
                let label_origin = Point {
                    x: point.x
                        + component
                            .label_offset
                            .as_ref()
                            .map_or(1, |offset| offset.x / 10),
                    y: point.y
                        + component
                            .label_offset
                            .as_ref()
                            .map_or(-1, |offset| offset.y / 10),
                };
                PositionedWardleyComponent {
                    name: component.name.text.clone(),
                    kind: component.kind,
                    point,
                    label_origin,
                    decorators: component.decorators.clone(),
                    pipeline: component
                        .pipeline
                        .as_ref()
                        .map(|pipeline| pipeline.text.clone()),
                }
            })
            .collect::<Vec<_>>();
        let index = components
            .iter()
            .map(|component| (component.name.as_str(), component.point))
            .collect::<HashMap<_, _>>();
        let links = ast
            .links
            .iter()
            .filter_map(|link| {
                Some(PositionedWardleyLink {
                    from: *index.get(link.from.text.as_str())?,
                    to: *index.get(link.to.text.as_str())?,
                    kind: link.kind,
                    label: link.label.as_ref().map(|label| label.text.clone()),
                })
            })
            .collect::<Vec<_>>();
        let evolves = ast
            .evolves
            .iter()
            .filter_map(|evolve| {
                let from = *index.get(evolve.name.text.as_str())?;
                let target = wardley_axis_value(&evolve.target_evolution.value)?;
                Some(PositionedWardleyEvolve {
                    from,
                    to: Point {
                        x: plot.origin.x + (target * f64::from(plot.size.width - 1)).round() as i32,
                        y: from.y,
                    },
                    name: evolve.name.text.clone(),
                })
            })
            .collect::<Vec<_>>();
        let mut texts = Vec::new();
        texts.extend(ast.notes.iter().map(|note| PositionedWardleyText {
            text: note.text.text.clone(),
            point: wardley_point(&note.coord, plot),
            kind: WardleyTextKind::Note,
        }));
        texts.extend(
            ast.annotations
                .iter()
                .map(|annotation| PositionedWardleyText {
                    text: format!("{} {}", annotation.number.value, annotation.text.text),
                    point: wardley_point(&annotation.coord, plot),
                    kind: WardleyTextKind::Annotation,
                }),
        );
        texts.extend(ast.forces.iter().map(|force| PositionedWardleyText {
            text: force.text.text.clone(),
            point: wardley_point(&force.coord, plot),
            kind: match force.kind {
                WardleyForceKind::Accelerator => WardleyTextKind::Accelerator,
                WardleyForceKind::Deaccelerator => WardleyTextKind::Deaccelerator,
            },
        }));
        let stages = ast.evolution.as_ref().map_or_else(
            || {
                ["Genesis", "Custom", "Product", "Commodity"]
                    .iter()
                    .map(|stage| (*stage).to_owned())
                    .collect::<Vec<_>>()
            },
            |evolution| {
                evolution
                    .stages
                    .iter()
                    .map(|stage| stage.label.text.clone())
                    .collect::<Vec<_>>()
            },
        );
        let annotations_origin = ast
            .annotations_position
            .as_ref()
            .map(|coord| wardley_point(coord, plot));
        let mut layout = WardleyLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            plot,
            components,
            links,
            evolves,
            texts,
            stages,
            annotations_origin,
            size: Size {
                width: self.config.width,
                height: self.config.height + title_offset,
            },
        };
        normalize_wardley_layout(&mut layout);
        layout
    }
}

fn wardley_point(coord: &crate::ast::WardleyCoord, plot: Rect) -> Point {
    let visibility = wardley_axis_value(&coord.visibility.value).unwrap_or(0.5);
    let evolution = wardley_axis_value(&coord.evolution.value).unwrap_or(0.5);
    Point {
        x: plot.origin.x + (evolution * f64::from(plot.size.width - 1)).round() as i32,
        y: plot.origin.y + ((1.0 - visibility) * f64::from(plot.size.height - 1)).round() as i32,
    }
}

fn wardley_axis_value(value: &str) -> Option<f64> {
    let parsed = value.parse::<f64>().ok()?;
    parsed.is_finite().then_some(parsed.clamp(0.0, 1.0))
}

fn normalize_wardley_layout(layout: &mut WardleyLayout) {
    let mut width = layout.size.width.max(layout.plot.right() + 3);
    let mut height = layout.size.height.max(layout.plot.bottom() + 4);
    if let Some(title) = &layout.title {
        width = width.max(label_width(title) + 2);
    }
    for component in &layout.components {
        width = width.max(component.label_origin.x + label_width(&component.name) + 4);
        height = height.max(component.label_origin.y + 2);
    }
    for text in &layout.texts {
        width = width.max(text.point.x + label_width(&text.text) + 4);
        height = height.max(text.point.y + 2);
    }
    layout.size = Size { width, height };
}

impl TreeViewLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: TreeViewLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: TreeViewLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &TreeViewAst) -> TreeViewLayout {
        let mut nodes = Vec::new();
        let mut y = 0i32;
        let mut width = 1i32;
        for (index, root) in ast.roots.iter().enumerate() {
            layout_tree_view_node(
                root,
                0,
                index + 1 == ast.roots.len(),
                &[],
                &mut y,
                &mut width,
                &mut nodes,
                self.config,
            );
        }
        TreeViewLayout {
            nodes,
            size: Size {
                width: width + self.config.padding_x * 2,
                height: y + self.config.padding_y * 2,
            },
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn layout_tree_view_node(
    node: &TreeViewNode,
    depth: usize,
    is_last: bool,
    ancestors: &[bool],
    y: &mut i32,
    width: &mut i32,
    nodes: &mut Vec<PositionedTreeViewNode>,
    config: TreeViewLayoutConfig,
) {
    let is_root = depth == 0;
    let prefix = if is_root {
        String::new()
    } else {
        tree_view_prefix(ancestors, is_last)
    };
    let icon = node
        .icon
        .as_ref()
        .map_or_else(|| tree_view_auto_icon(node), |icon| icon.value.clone());
    let positioned = PositionedTreeViewNode {
        prefix,
        label: node.label.text.clone(),
        directory: node.directory,
        icon,
        classes: node
            .classes
            .iter()
            .map(|class| class.value.clone())
            .collect(),
        description: node
            .description
            .as_ref()
            .map(|description| description.text.clone()),
        depth,
        point: Point {
            x: config.padding_x,
            y: config.padding_y + *y,
        },
    };
    *width = (*width).max(tree_view_line_width(&positioned));
    nodes.push(positioned);
    *y += 1;
    let mut next_ancestors = ancestors.to_vec();
    if !is_root {
        next_ancestors.push(is_last);
    }
    for (index, child) in node.children.iter().enumerate() {
        layout_tree_view_node(
            child,
            depth + 1,
            index + 1 == node.children.len(),
            &next_ancestors,
            y,
            width,
            nodes,
            config,
        );
    }
}

fn tree_view_prefix(ancestors: &[bool], is_last: bool) -> String {
    let mut prefix = String::new();
    for ancestor_last in ancestors {
        prefix.push_str(if *ancestor_last { "   " } else { "|  " });
    }
    prefix.push_str(if is_last { "`-- " } else { "|-- " });
    prefix
}

fn tree_view_line_width(node: &PositionedTreeViewNode) -> i32 {
    let mut width = label_width(&node.prefix) + label_width(&node.icon) + 3;
    width += label_width(&node.label);
    if node.directory {
        width += 1;
    }
    if !node.classes.is_empty() {
        width += label_width(&format!(" [{}]", node.classes.join(",")));
    }
    if let Some(description) = &node.description {
        width += label_width(description) + 4;
    }
    width
}

fn tree_view_auto_icon(node: &TreeViewNode) -> String {
    if node.directory {
        return "folder".to_owned();
    }
    let label = node.label.text.as_str();
    let icon = match label {
        "Dockerfile" => "docker",
        "Makefile" => "terminal",
        ".gitignore" => "git",
        _ => match label.rsplit_once('.').map(|(_, extension)| extension) {
            Some("js" | "mjs" | "cjs") => "javascript",
            Some("ts") => "typescript",
            Some("jsx" | "tsx") => "react",
            Some("py") => "python",
            Some("json") => "json",
            Some("md" | "mdx") => "markdown",
            Some("html" | "htm") => "html",
            Some("css" | "scss") => "css",
            Some("yaml" | "yml") => "yaml",
            Some("sh" | "bash") => "terminal",
            Some("sql" | "db" | "h5") => "database",
            Some("lock") => "lock",
            _ => "file",
        },
    };
    icon.to_owned()
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
            max_label_width: None,
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
                    start_cardinality: relationship
                        .start_cardinality
                        .as_ref()
                        .map(|label| label.text.clone()),
                    end_cardinality: relationship
                        .end_cardinality
                        .as_ref()
                        .map(|label| label.text.clone()),
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
            max_label_width: None,
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
                    start_cardinality: None,
                    end_cardinality: None,
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

impl RequirementLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: RequirementLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: RequirementLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &RequirementAst) -> RequirementLayout {
        let direction = ast
            .direction
            .map_or(Direction::TopDown, |value| value.value);
        let graph = LayoutGraph::from_requirement_ast(ast);
        let layers = assign_layers(&graph);
        let order = minimise_crossings(&graph, &layers);
        let sizes = graph
            .nodes
            .iter()
            .map(|node| requirement_node_size(ast, &node.id, self.config))
            .collect::<Vec<_>>();
        let placement_config = FlowLayoutConfig {
            horizontal_spacing: self.config.horizontal_spacing,
            vertical_spacing: self.config.vertical_spacing,
            horizontal_padding: self.config.horizontal_padding,
            min_node_width: self.config.min_node_width,
            node_height: 3,
            max_label_width: None,
        };
        let mut rects = place_top_down(&sizes, &layers, &order, placement_config);
        transform_rects_for_direction(&mut rects, &layers, direction, placement_config);
        let mut size = layout_size(&rects);

        let nodes = graph
            .nodes
            .iter()
            .enumerate()
            .map(|(index, node)| {
                positioned_requirement_node(
                    ast,
                    &node.id,
                    rects[index],
                    layers[index],
                    order[index],
                )
            })
            .collect::<Vec<_>>();
        let relationships = ast
            .relationships
            .iter()
            .filter_map(|relationship| {
                let from = graph.node_index(&relationship.from.value)?;
                let to = graph.node_index(&relationship.to.value)?;
                Some(PositionedRequirementRelationship {
                    from: relationship.from.value.clone(),
                    to: relationship.to.value.clone(),
                    kind: relationship.kind.value,
                    label: format!(
                        "<<{}>>",
                        requirement_relationship_label(relationship.kind.value)
                    ),
                    points: route_edge(
                        rects[from],
                        rects[to],
                        direction,
                        closes_existing_path(&graph, to, from, (from, to)),
                    ),
                })
            })
            .collect::<Vec<_>>();
        size = layout_size_with_requirement_relationships(size, &relationships);

        RequirementLayout {
            direction,
            nodes,
            relationships,
            size,
        }
    }
}

fn requirement_node_size(ast: &RequirementAst, id: &str, config: RequirementLayoutConfig) -> Size {
    let lines = requirement_node_lines(ast, id);
    let width = lines
        .iter()
        .map(|line| line.chars().count() as i32 + config.horizontal_padding)
        .max()
        .unwrap_or(config.min_node_width)
        .max(config.min_node_width);
    let body_rows = lines.len().saturating_sub(2);
    Size {
        width,
        height: if body_rows == 0 {
            4
        } else {
            body_rows as i32 + 5
        },
    }
}

fn positioned_requirement_node(
    ast: &RequirementAst,
    id: &str,
    rect: Rect,
    layer: usize,
    order: usize,
) -> PositionedRequirementNode {
    if let Some(requirement) = ast
        .requirements
        .iter()
        .find(|requirement| requirement.name.value == id)
    {
        return PositionedRequirementNode {
            id: requirement.name.value.clone(),
            kind: PositionedRequirementNodeKind::Requirement,
            type_label: requirement_type_label(requirement.kind.value).to_owned(),
            name: requirement.name.value.clone(),
            rows: requirement_rows(requirement),
            classes: requirement
                .classes
                .iter()
                .map(|class| class.value.clone())
                .collect(),
            rect,
            layer,
            order,
        };
    }
    if let Some(element) = ast.elements.iter().find(|element| element.name.value == id) {
        return PositionedRequirementNode {
            id: element.name.value.clone(),
            kind: PositionedRequirementNodeKind::Element,
            type_label: "Element".to_owned(),
            name: element.name.value.clone(),
            rows: element_rows(element),
            classes: element
                .classes
                .iter()
                .map(|class| class.value.clone())
                .collect(),
            rect,
            layer,
            order,
        };
    }
    PositionedRequirementNode {
        id: id.to_owned(),
        kind: PositionedRequirementNodeKind::Element,
        type_label: "Element".to_owned(),
        name: id.to_owned(),
        rows: Vec::new(),
        classes: Vec::new(),
        rect,
        layer,
        order,
    }
}

fn requirement_node_lines(ast: &RequirementAst, id: &str) -> Vec<String> {
    if let Some(requirement) = ast
        .requirements
        .iter()
        .find(|requirement| requirement.name.value == id)
    {
        let mut lines = vec![
            format!("<<{}>>", requirement_type_label(requirement.kind.value)),
            requirement.name.value.clone(),
        ];
        lines.extend(requirement_rows(requirement));
        return lines;
    }
    if let Some(element) = ast.elements.iter().find(|element| element.name.value == id) {
        let mut lines = vec!["<<Element>>".to_owned(), element.name.value.clone()];
        lines.extend(element_rows(element));
        return lines;
    }
    vec!["<<Element>>".to_owned(), id.to_owned()]
}

fn requirement_rows(requirement: &RequirementNode) -> Vec<String> {
    let mut rows = Vec::new();
    if let Some(id) = &requirement.requirement_id {
        rows.push(format!("ID: {}", id.text));
    }
    if let Some(text) = &requirement.text {
        rows.push(format!("Text: {}", text.text));
    }
    if let Some(risk) = requirement.risk {
        rows.push(format!("Risk: {}", requirement_risk_label(risk.value)));
    }
    if let Some(verify_method) = requirement.verify_method {
        rows.push(format!(
            "Verification: {}",
            requirement_verify_method_label(verify_method.value)
        ));
    }
    rows
}

fn element_rows(element: &RequirementElement) -> Vec<String> {
    let mut rows = Vec::new();
    if let Some(ty) = &element.ty {
        rows.push(format!("Type: {}", ty.text));
    }
    if let Some(doc_ref) = &element.doc_ref {
        rows.push(format!("Doc Ref: {}", doc_ref.text));
    }
    rows
}

fn requirement_type_label(kind: RequirementKind) -> &'static str {
    match kind {
        RequirementKind::Requirement => "Requirement",
        RequirementKind::Functional => "Functional Requirement",
        RequirementKind::Interface => "Interface Requirement",
        RequirementKind::Performance => "Performance Requirement",
        RequirementKind::Physical => "Physical Requirement",
        RequirementKind::DesignConstraint => "Design Constraint",
    }
}

fn requirement_risk_label(risk: RequirementRisk) -> &'static str {
    match risk {
        RequirementRisk::Low => "Low",
        RequirementRisk::Medium => "Medium",
        RequirementRisk::High => "High",
    }
}

fn requirement_verify_method_label(method: RequirementVerifyMethod) -> &'static str {
    match method {
        RequirementVerifyMethod::Analysis => "Analysis",
        RequirementVerifyMethod::Inspection => "Inspection",
        RequirementVerifyMethod::Test => "Test",
        RequirementVerifyMethod::Demonstration => "Demonstration",
    }
}

fn requirement_relationship_label(kind: RequirementRelationshipKind) -> &'static str {
    match kind {
        RequirementRelationshipKind::Contains => "contains",
        RequirementRelationshipKind::Copies => "copies",
        RequirementRelationshipKind::Derives => "derives",
        RequirementRelationshipKind::Satisfies => "satisfies",
        RequirementRelationshipKind::Verifies => "verifies",
        RequirementRelationshipKind::Refines => "refines",
        RequirementRelationshipKind::Traces => "traces",
    }
}

impl C4LayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: C4LayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: C4LayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &C4Ast) -> C4Layout {
        let config = c4_config_from_statements(self.config, ast);
        let styles = c4_style_map(ast);
        let title = ast.title.as_ref().map(|title| title.text.clone());
        let origin = Point {
            x: 0,
            y: if title.is_some() { 2 } else { 0 },
        };
        let mut placement = C4Placement::default();
        let content_size = c4_place_group(ast, None, origin, 0, &config, &styles, &mut placement);
        let rects = c4_rect_map(&placement.elements, &placement.boundaries);
        let relationships = c4_position_relationships(ast, &rects, &styles);
        let mut size = Size {
            width: content_size.width,
            height: origin.y + content_size.height,
        };
        if let Some(title) = &title {
            size.width = size.width.max(title.chars().count() as i32);
            size.height = size.height.max(1);
        }
        size = layout_size_with_c4_relationships(size, &relationships);
        C4Layout {
            title,
            elements: placement.elements,
            boundaries: placement.boundaries,
            relationships,
            size,
        }
    }
}

#[derive(Debug, Default)]
struct C4Placement {
    elements: Vec<PositionedC4Element>,
    boundaries: Vec<PositionedC4Boundary>,
    order: usize,
}

fn c4_config_from_statements(mut config: C4LayoutConfig, ast: &C4Ast) -> C4LayoutConfig {
    for statement in &ast.statements {
        let C4Statement::Layout(layout) = statement else {
            continue;
        };
        match layout.name.value.as_str() {
            "LAYOUT_LEFT_RIGHT" => config.direction = Direction::LeftRight,
            "LAYOUT_TOP_DOWN" => config.direction = Direction::TopDown,
            "UpdateLayoutConfig" => {
                for field in &layout.fields {
                    let Some(name) = field.name.as_ref() else {
                        continue;
                    };
                    let Some(value) = c4_usize_arg(field) else {
                        continue;
                    };
                    match name.value.as_str() {
                        "c4ShapeInRow" => config.shape_in_row = value.max(1),
                        "c4BoundaryInRow" => config.boundary_in_row = value.max(1),
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
    config
}

fn c4_usize_arg(arg: &C4CallArg) -> Option<usize> {
    arg.value.text.trim().parse::<usize>().ok()
}

fn c4_style_map(ast: &C4Ast) -> HashMap<String, Vec<String>> {
    let mut styles = HashMap::<String, Vec<String>>::new();
    for statement in &ast.statements {
        let C4Statement::Style(style) = statement else {
            continue;
        };
        let Some(row) = c4_style_row(&style.fields) else {
            continue;
        };
        for target in &style.target_ids {
            styles
                .entry(target.value.clone())
                .or_default()
                .push(row.clone());
        }
    }
    styles
}

fn c4_style_row(fields: &[C4CallArg]) -> Option<String> {
    let values = fields.iter().filter_map(c4_arg_text).collect::<Vec<_>>();
    if values.is_empty() {
        None
    } else {
        Some(format!("style: {}", values.join(", ")))
    }
}

fn c4_arg_text(arg: &C4CallArg) -> Option<String> {
    let value = arg.value.text.trim();
    if value.is_empty() {
        return None;
    }
    Some(match &arg.name {
        Some(name) => format!("{}={value}", name.value),
        None => value.to_owned(),
    })
}

fn c4_place_group(
    ast: &C4Ast,
    parent: Option<&str>,
    origin: Point,
    depth: usize,
    config: &C4LayoutConfig,
    styles: &HashMap<String, Vec<String>>,
    placement: &mut C4Placement,
) -> Size {
    let elements = c4_child_elements(ast, parent);
    let element_sizes = elements
        .iter()
        .map(|element| c4_element_size(element, config, styles))
        .collect::<Vec<_>>();
    let (element_rects, element_size) =
        c4_pack_rects(&element_sizes, origin, config.shape_in_row, config);
    for (element, rect) in elements.into_iter().zip(element_rects) {
        let order = placement.order;
        placement.order += 1;
        placement
            .elements
            .push(c4_positioned_element(element, rect, depth, order, styles));
    }

    let boundaries = c4_child_boundaries(ast, parent);
    let boundary_sizes = boundaries
        .iter()
        .map(|boundary| c4_boundary_size(ast, boundary, config, styles))
        .collect::<Vec<_>>();
    let boundary_origin = Point {
        x: origin.x,
        y: origin.y
            + element_size.height
            + if element_size.height > 0 && !boundary_sizes.is_empty() {
                config.vertical_spacing
            } else {
                0
            },
    };
    let (boundary_rects, boundary_size) = c4_pack_rects(
        &boundary_sizes,
        boundary_origin,
        config.boundary_in_row,
        config,
    );
    for (boundary, rect) in boundaries.into_iter().zip(boundary_rects) {
        let order = placement.order;
        placement.order += 1;
        let positioned = c4_positioned_boundary(boundary, rect, depth, order, config, styles);
        let child_origin = Point {
            x: rect.origin.x + config.boundary_padding_x,
            y: rect.origin.y + positioned.header_height + config.boundary_padding_y,
        };
        let child_parent = positioned.id.clone();
        placement.boundaries.push(positioned);
        c4_place_group(
            ast,
            Some(&child_parent),
            child_origin,
            depth + 1,
            config,
            styles,
            placement,
        );
    }

    c4_stack_size(element_size, boundary_size, config.vertical_spacing)
}

fn c4_group_size(
    ast: &C4Ast,
    parent: Option<&str>,
    config: &C4LayoutConfig,
    styles: &HashMap<String, Vec<String>>,
) -> Size {
    let element_sizes = c4_child_elements(ast, parent)
        .iter()
        .map(|element| c4_element_size(element, config, styles))
        .collect::<Vec<_>>();
    let element_size = c4_pack_size(&element_sizes, config.shape_in_row, config);
    let boundary_sizes = c4_child_boundaries(ast, parent)
        .iter()
        .map(|boundary| c4_boundary_size(ast, boundary, config, styles))
        .collect::<Vec<_>>();
    let boundary_size = c4_pack_size(&boundary_sizes, config.boundary_in_row, config);
    c4_stack_size(element_size, boundary_size, config.vertical_spacing)
}

fn c4_stack_size(elements: Size, boundaries: Size, spacing: i32) -> Size {
    Size {
        width: elements.width.max(boundaries.width),
        height: elements.height
            + boundaries.height
            + if elements.height > 0 && boundaries.height > 0 {
                spacing
            } else {
                0
            },
    }
}

fn c4_child_elements<'a>(ast: &'a C4Ast, parent: Option<&str>) -> Vec<&'a C4Element> {
    let mut elements = Vec::new();
    let mut seen = HashSet::<String>::new();
    for statement in &ast.statements {
        let C4Statement::Element(element) = statement else {
            continue;
        };
        if c4_parent_matches(&element.parent, parent) && seen.insert(element.alias.value.clone()) {
            let canonical = ast
                .elements
                .iter()
                .find(|candidate| candidate.alias.value == element.alias.value)
                .unwrap_or(element);
            elements.push(canonical);
        }
    }
    for element in &ast.elements {
        if c4_parent_matches(&element.parent, parent) && seen.insert(element.alias.value.clone()) {
            elements.push(element);
        }
    }
    elements
}

fn c4_child_boundaries<'a>(ast: &'a C4Ast, parent: Option<&str>) -> Vec<&'a C4Boundary> {
    let mut boundaries = Vec::new();
    let mut seen = HashSet::<String>::new();
    for statement in &ast.statements {
        let C4Statement::Boundary(boundary) = statement else {
            continue;
        };
        if c4_parent_matches(&boundary.parent, parent) && seen.insert(boundary.alias.value.clone())
        {
            let canonical = ast
                .boundaries
                .iter()
                .find(|candidate| candidate.alias.value == boundary.alias.value)
                .unwrap_or(boundary);
            boundaries.push(canonical);
        }
    }
    for boundary in &ast.boundaries {
        if c4_parent_matches(&boundary.parent, parent) && seen.insert(boundary.alias.value.clone())
        {
            boundaries.push(boundary);
        }
    }
    boundaries
}

fn c4_parent_matches(parent: &Option<Spanned<String>>, expected: Option<&str>) -> bool {
    parent.as_ref().map(|parent| parent.value.as_str()) == expected
}

fn c4_pack_size(sizes: &[Size], limit: usize, config: &C4LayoutConfig) -> Size {
    c4_pack_rects(sizes, Point { x: 0, y: 0 }, limit, config).1
}

fn c4_pack_rects(
    sizes: &[Size],
    origin: Point,
    limit: usize,
    config: &C4LayoutConfig,
) -> (Vec<Rect>, Size) {
    if sizes.is_empty() {
        return (
            Vec::new(),
            Size {
                width: 0,
                height: 0,
            },
        );
    }
    match config.direction {
        Direction::LeftRight | Direction::RightLeft => {
            c4_pack_columns(sizes, origin, limit.max(1), config)
        }
        Direction::TopDown | Direction::BottomTop => {
            c4_pack_rows(sizes, origin, limit.max(1), config)
        }
    }
}

fn c4_pack_rows(
    sizes: &[Size],
    origin: Point,
    limit: usize,
    config: &C4LayoutConfig,
) -> (Vec<Rect>, Size) {
    let mut rects = Vec::new();
    let mut y = origin.y;
    let mut width = 0;
    for row in sizes.chunks(limit) {
        let row_height = row.iter().map(|size| size.height).max().unwrap_or(0);
        let mut x = origin.x;
        let mut row_width = 0;
        for size in row {
            rects.push(Rect {
                origin: Point { x, y },
                size: *size,
            });
            x += size.width + config.horizontal_spacing;
            row_width += size.width + config.horizontal_spacing;
        }
        width = width.max(row_width.saturating_sub(config.horizontal_spacing));
        y += row_height + config.vertical_spacing;
    }
    (
        rects,
        Size {
            width,
            height: (y - origin.y).saturating_sub(config.vertical_spacing),
        },
    )
}

fn c4_pack_columns(
    sizes: &[Size],
    origin: Point,
    limit: usize,
    config: &C4LayoutConfig,
) -> (Vec<Rect>, Size) {
    let mut rects = Vec::new();
    let mut x = origin.x;
    let mut height = 0;
    for column in sizes.chunks(limit) {
        let column_width = column.iter().map(|size| size.width).max().unwrap_or(0);
        let mut y = origin.y;
        let mut column_height = 0;
        for size in column {
            rects.push(Rect {
                origin: Point { x, y },
                size: *size,
            });
            y += size.height + config.vertical_spacing;
            column_height += size.height + config.vertical_spacing;
        }
        height = height.max(column_height.saturating_sub(config.vertical_spacing));
        x += column_width + config.horizontal_spacing;
    }
    (
        rects,
        Size {
            width: (x - origin.x).saturating_sub(config.horizontal_spacing),
            height,
        },
    )
}

fn c4_element_size(
    element: &C4Element,
    config: &C4LayoutConfig,
    styles: &HashMap<String, Vec<String>>,
) -> Size {
    let detail_rows = c4_element_detail_rows(element, styles);
    let width = c4_max_width(
        [
            element.label.text.as_str(),
            &format!(
                "[{}]",
                c4_element_kind_label(element.kind.value, element.external)
            ),
        ]
        .into_iter()
        .chain(detail_rows.iter().map(String::as_str)),
    )
    .max(config.min_node_width)
        + config.horizontal_padding * 2;
    Size {
        width,
        height: if detail_rows.is_empty() {
            4
        } else {
            5 + detail_rows.len() as i32
        },
    }
}

fn c4_boundary_size(
    ast: &C4Ast,
    boundary: &C4Boundary,
    config: &C4LayoutConfig,
    styles: &HashMap<String, Vec<String>>,
) -> Size {
    let content_size = c4_group_size(ast, Some(&boundary.alias.value), config, styles);
    let style_rows = c4_style_rows(styles, &boundary.alias.value);
    let header_height = c4_boundary_header_height(config, &style_rows);
    let header_width = c4_max_width(
        [
            boundary.label.text.as_str(),
            &c4_boundary_secondary(boundary),
        ]
        .into_iter()
        .chain(style_rows.iter().map(String::as_str)),
    ) + config.horizontal_padding * 2;
    let content_width = if content_size.width == 0 {
        0
    } else {
        content_size.width + config.boundary_padding_x * 2 + 1
    };
    let content_height = if content_size.height == 0 {
        0
    } else {
        config.boundary_padding_y + content_size.height + config.boundary_padding_y
    };
    Size {
        width: header_width.max(content_width).max(config.min_node_width),
        height: (header_height + content_height + 1).max(5),
    }
}

fn c4_positioned_element(
    element: &C4Element,
    rect: Rect,
    layer: usize,
    order: usize,
    styles: &HashMap<String, Vec<String>>,
) -> PositionedC4Element {
    PositionedC4Element {
        id: element.alias.value.clone(),
        label: element.label.text.clone(),
        kind_label: c4_element_kind_label(element.kind.value, element.external),
        technology: element.technology.as_ref().map(|label| label.text.clone()),
        description: element.description.as_ref().map(|label| label.text.clone()),
        style_rows: c4_style_rows(styles, &element.alias.value),
        parent: element.parent.as_ref().map(|parent| parent.value.clone()),
        external: element.external,
        rect,
        layer,
        order,
    }
}

fn c4_positioned_boundary(
    boundary: &C4Boundary,
    rect: Rect,
    depth: usize,
    order: usize,
    config: &C4LayoutConfig,
    styles: &HashMap<String, Vec<String>>,
) -> PositionedC4Boundary {
    let style_rows = c4_style_rows(styles, &boundary.alias.value);
    PositionedC4Boundary {
        id: boundary.alias.value.clone(),
        label: boundary.label.text.clone(),
        kind_label: c4_boundary_kind_label(boundary.kind.value).to_owned(),
        ty: boundary.ty.as_ref().map(|label| label.text.clone()),
        header_height: c4_boundary_header_height(config, &style_rows),
        style_rows,
        parent: boundary.parent.as_ref().map(|parent| parent.value.clone()),
        rect,
        depth,
        order,
    }
}

fn c4_boundary_header_height(config: &C4LayoutConfig, style_rows: &[String]) -> i32 {
    config.boundary_header_height + style_rows.len() as i32
}

fn c4_element_detail_rows(
    element: &C4Element,
    styles: &HashMap<String, Vec<String>>,
) -> Vec<String> {
    let mut rows = Vec::new();
    if let Some(technology) = &element.technology {
        rows.push(format!("technology: {}", technology.text));
    }
    if let Some(description) = &element.description {
        rows.push(description.text.clone());
    }
    rows.extend(c4_style_rows(styles, &element.alias.value));
    rows
}

fn c4_style_rows(styles: &HashMap<String, Vec<String>>, id: &str) -> Vec<String> {
    styles.get(id).cloned().unwrap_or_default()
}

fn c4_max_width<'a>(rows: impl IntoIterator<Item = &'a str>) -> i32 {
    rows.into_iter()
        .map(|row| row.chars().count() as i32)
        .max()
        .unwrap_or(0)
}

fn c4_rect_map(
    elements: &[PositionedC4Element],
    boundaries: &[PositionedC4Boundary],
) -> HashMap<String, Rect> {
    let mut rects = HashMap::new();
    for element in elements {
        rects.insert(element.id.clone(), element.rect);
    }
    for boundary in boundaries {
        rects.insert(boundary.id.clone(), boundary.rect);
    }
    rects
}

fn c4_position_relationships(
    ast: &C4Ast,
    rects: &HashMap<String, Rect>,
    styles: &HashMap<String, Vec<String>>,
) -> Vec<PositionedC4Relationship> {
    ast.relationships
        .iter()
        .filter_map(|relationship| {
            let from = *rects.get(&relationship.from.value)?;
            let to = *rects.get(&relationship.to.value)?;
            let direction = c4_relationship_direction(relationship.kind.value, from, to);
            let label = c4_relationship_text(relationship);
            let style_rows = relationship
                .index
                .as_ref()
                .map_or_else(Vec::new, |index| c4_style_rows(styles, &index.value));
            let label_width = c4_max_width(
                [label.as_str()]
                    .into_iter()
                    .chain(style_rows.iter().map(String::as_str)),
            );
            let points = route_c4_relationship(
                from,
                to,
                direction,
                relationship.kind.value == C4RelationshipKind::Back,
                label_width,
            );
            Some(PositionedC4Relationship {
                from: relationship.from.value.clone(),
                to: relationship.to.value.clone(),
                kind: relationship.kind.value,
                label,
                technology: relationship
                    .technology
                    .as_ref()
                    .map(|label| label.text.clone()),
                style_rows,
                points,
            })
        })
        .collect()
}

fn route_c4_relationship(
    from: Rect,
    to: Rect,
    direction: Direction,
    back_edge_below: bool,
    label_width: i32,
) -> Vec<Point> {
    let same_row = from.origin.y < to.bottom() && to.origin.y < from.bottom();
    let horizontal = matches!(direction, Direction::LeftRight | Direction::RightLeft);
    let gap = if from.right() <= to.origin.x {
        to.origin.x - from.right()
    } else if to.right() <= from.origin.x {
        from.origin.x - to.right()
    } else {
        0
    };
    if same_row && horizontal && gap < label_width + 2 {
        return c4_horizontal_offset_edge(from, to);
    }
    if matches!(direction, Direction::TopDown | Direction::BottomTop) {
        let points = route_edge(from, to, direction, back_edge_below);
        if let [first, last] = points.as_slice()
            && first.x != last.x
        {
            let y = first.y + (last.y - first.y).signum();
            return vec![
                *first,
                Point { x: first.x, y },
                Point { x: last.x, y },
                *last,
            ];
        }
    }
    route_class_relationship(from, to, direction, back_edge_below)
}

fn c4_horizontal_offset_edge(from: Rect, to: Rect) -> Vec<Point> {
    let rightward = to.center().x >= from.center().x;
    let from_x = if rightward {
        from.right()
    } else {
        from.origin.x - 1
    };
    let to_outer_x = if rightward {
        to.origin.x - 1
    } else {
        to.right()
    };
    let step = if rightward { 1 } else { -1 };
    let to_bend_x = to_outer_x - step;
    let y = from.bottom().max(to.bottom()) + 1;
    vec![
        Point {
            x: from_x,
            y: from.center().y,
        },
        Point {
            x: from_x + step,
            y,
        },
        Point { x: to_bend_x, y },
        Point {
            x: to_bend_x,
            y: to.center().y,
        },
        Point {
            x: to_outer_x,
            y: to.center().y,
        },
    ]
}

fn c4_relationship_direction(kind: C4RelationshipKind, from: Rect, to: Rect) -> Direction {
    match kind {
        C4RelationshipKind::Up => Direction::BottomTop,
        C4RelationshipKind::Down => Direction::TopDown,
        C4RelationshipKind::Left => Direction::RightLeft,
        C4RelationshipKind::Right => Direction::LeftRight,
        C4RelationshipKind::Back => Direction::TopDown,
        C4RelationshipKind::Directed
        | C4RelationshipKind::Bidirectional
        | C4RelationshipKind::Indexed => c4_auto_direction(from, to),
    }
}

fn c4_auto_direction(from: Rect, to: Rect) -> Direction {
    let from_center = from.center();
    let to_center = to.center();
    let dx = to_center.x - from_center.x;
    let dy = to_center.y - from_center.y;
    if dx.abs() >= dy.abs() {
        if dx >= 0 {
            Direction::LeftRight
        } else {
            Direction::RightLeft
        }
    } else if dy >= 0 {
        Direction::TopDown
    } else {
        Direction::BottomTop
    }
}

fn c4_element_kind_label(kind: C4ElementKind, external: bool) -> String {
    let base = match kind {
        C4ElementKind::Person | C4ElementKind::PersonExternal => "person",
        C4ElementKind::System | C4ElementKind::SystemExternal => "system",
        C4ElementKind::SystemDb | C4ElementKind::SystemDbExternal => "system database",
        C4ElementKind::SystemQueue | C4ElementKind::SystemQueueExternal => "system queue",
        C4ElementKind::Container | C4ElementKind::ContainerExternal => "container",
        C4ElementKind::ContainerDb | C4ElementKind::ContainerDbExternal => "container database",
        C4ElementKind::ContainerQueue | C4ElementKind::ContainerQueueExternal => "container queue",
        C4ElementKind::Component | C4ElementKind::ComponentExternal => "component",
        C4ElementKind::ComponentDb | C4ElementKind::ComponentDbExternal => "component database",
        C4ElementKind::ComponentQueue | C4ElementKind::ComponentQueueExternal => "component queue",
        C4ElementKind::DeploymentNode => "deployment node",
    };
    if external {
        format!("external {base}")
    } else {
        base.to_owned()
    }
}

fn c4_boundary_kind_label(kind: C4BoundaryKind) -> &'static str {
    match kind {
        C4BoundaryKind::Boundary => "boundary",
        C4BoundaryKind::Enterprise => "enterprise boundary",
        C4BoundaryKind::System => "system boundary",
        C4BoundaryKind::Container => "container boundary",
        C4BoundaryKind::DeploymentNode => "deployment node",
    }
}

fn c4_boundary_secondary(boundary: &C4Boundary) -> String {
    match &boundary.ty {
        Some(ty) => format!(
            "[{}] {}",
            c4_boundary_kind_label(boundary.kind.value),
            ty.text
        ),
        None => format!("[{}]", c4_boundary_kind_label(boundary.kind.value)),
    }
}

fn c4_relationship_text(relationship: &C4Relationship) -> String {
    let mut text = String::new();
    if let Some(index) = &relationship.index {
        text.push_str(&index.value);
        text.push(' ');
    }
    text.push_str(&relationship.label.text);
    if let Some(technology) = &relationship.technology {
        text.push_str(" [");
        text.push_str(&technology.text);
        text.push(']');
    }
    text
}

fn layout_size_with_c4_relationships(
    size: Size,
    relationships: &[PositionedC4Relationship],
) -> Size {
    Size {
        width: relationships
            .iter()
            .flat_map(|relationship| {
                relationship
                    .points
                    .iter()
                    .map(|point| point.x + 1)
                    .chain(c4_relationship_label_width(relationship).into_iter())
            })
            .fold(size.width, i32::max),
        height: relationships
            .iter()
            .flat_map(|relationship| {
                relationship
                    .points
                    .iter()
                    .map(|point| point.y + 1)
                    .chain(c4_relationship_label_height(relationship).into_iter())
            })
            .fold(size.height, i32::max),
    }
}

fn c4_relationship_label_width(relationship: &PositionedC4Relationship) -> Option<i32> {
    let point = c4_polyline_label_point(&relationship.points)?;
    let width = c4_relationship_rows(relationship)
        .iter()
        .map(|row| row.chars().count() as i32)
        .max()
        .unwrap_or(0);
    Some((point.x - width / 2).max(0) + width + 1)
}

fn c4_relationship_label_height(relationship: &PositionedC4Relationship) -> Option<i32> {
    let point = c4_polyline_label_point(&relationship.points)?;
    Some(point.y + c4_relationship_rows(relationship).len() as i32)
}

fn c4_relationship_rows(relationship: &PositionedC4Relationship) -> Vec<String> {
    let mut rows = vec![relationship.label.clone()];
    rows.extend(relationship.style_rows.clone());
    rows
}

fn c4_polyline_label_point(points: &[Point]) -> Option<Point> {
    if let Some(segment) = points.windows(2).max_by_key(|pair| {
        if pair[0].y == pair[1].y {
            (pair[0].x - pair[1].x).abs()
        } else {
            0
        }
    }) && segment[0].y == segment[1].y
    {
        return Some(Point {
            x: (segment[0].x + segment[1].x) / 2,
            y: segment[0].y,
        });
    }
    let first = points.first()?;
    let last = points.last()?;
    if first.x == last.x && first.y != last.y {
        return Some(Point {
            x: first.x,
            y: first.y + (last.y - first.y).signum(),
        });
    }
    Some(Point {
        x: (first.x + last.x) / 2,
        y: (first.y + last.y) / 2,
    })
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
        let schedule_config = gantt_schedule_config(ast);
        let scheduled = schedule_gantt_tasks(ast, &schedule_config);
        let min_day = scheduled.iter().map(|task| task.start).min().unwrap_or(0);
        let max_day = scheduled
            .iter()
            .map(|task| task.end.max(task.start + 1))
            .max()
            .unwrap_or(min_day + 1);
        let day_width =
            gantt_effective_day_width(min_day, max_day, self.config.day_width, &schedule_config);
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
            let x = self.config.left_width + (task.start - min_day) * day_width;
            let width = ((task.end - task.start).max(1) * day_width).max(1);
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

        let ticks = gantt_axis_ticks(
            min_day,
            max_day,
            self.config.left_width,
            day_width,
            &schedule_config,
        );
        let excluded_days = (min_day..max_day)
            .filter(|day| is_gantt_excluded_day(*day, &schedule_config))
            .collect::<Vec<_>>();
        let today_x = schedule_config
            .today_marker
            .then(|| gantt_today_day())
            .flatten()
            .and_then(|today| {
                (min_day..=max_day)
                    .contains(&today)
                    .then(|| self.config.left_width + (today - min_day) * day_width)
            });
        let title_width = ast
            .title
            .as_ref()
            .map_or(0, |title| title.text.chars().count() as i32);
        let tick_width = ticks.iter().fold(0, |width, tick| {
            width.max(tick.x + tick.label.chars().count() as i32 + 1)
        });
        GanttLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            sections,
            tasks,
            ticks,
            excluded_days,
            today_x,
            day_width,
            min_day,
            max_day,
            size: Size {
                width: (self.config.left_width + (max_day - min_day).max(1) * day_width + 2)
                    .max(title_width)
                    .max(tick_width),
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

#[derive(Debug, Clone, PartialEq, Eq)]
struct GanttScheduleConfig {
    axis_format: String,
    tick_interval_days: Option<i32>,
    excludes_weekends: bool,
    excluded_weekdays: Vec<i32>,
    excluded_dates: Vec<i32>,
    weekend_start: i32,
    today_marker: bool,
}

fn schedule_gantt_tasks(ast: &GanttAst, config: &GanttScheduleConfig) -> Vec<ScheduledGanttTask> {
    let mut scheduled = Vec::new();
    let mut previous_end = 0;
    for task in &ast.tasks {
        let (start, end) = resolve_gantt_task(task, previous_end, &scheduled, config);
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
            let (start, end) = resolve_gantt_task(task, previous_end, &scheduled, config);
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
    config: &GanttScheduleConfig,
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
    let end = resolve_gantt_end(end_spec, start, scheduled, config);
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

fn resolve_gantt_end(
    value: &str,
    start: i32,
    scheduled: &[ScheduledGanttTask],
    config: &GanttScheduleConfig,
) -> i32 {
    if let Some(id) = value.strip_prefix("until ") {
        return gantt_task_by_id(scheduled, id.trim()).map_or(start, |task| task.start);
    }
    if let Some(duration) = gantt_duration_days(value) {
        return add_gantt_duration_days(start, duration.max(0), config);
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

fn add_gantt_duration_days(start: i32, duration: i32, config: &GanttScheduleConfig) -> i32 {
    let mut day = start;
    let mut remaining = duration;
    while remaining > 0 {
        if !is_gantt_excluded_day(day, config) {
            remaining -= 1;
        }
        day += 1;
    }
    day
}

fn is_gantt_excluded_day(day: i32, config: &GanttScheduleConfig) -> bool {
    config.excluded_dates.contains(&day)
        || config.excluded_weekdays.contains(&weekday_from_day(day))
        || (config.excludes_weekends && is_gantt_weekend(day, config.weekend_start))
}

fn is_gantt_weekend(day: i32, weekend_start: i32) -> bool {
    let weekday = weekday_from_day(day);
    weekday == weekend_start || weekday == (weekend_start + 1).rem_euclid(7)
}

fn weekday_from_day(day: i32) -> i32 {
    (day + 4).rem_euclid(7)
}

fn gantt_schedule_config(ast: &GanttAst) -> GanttScheduleConfig {
    let mut config = GanttScheduleConfig {
        axis_format: ast
            .axis_format
            .as_ref()
            .map_or_else(|| "%Y-%m-%d".to_owned(), |format| format.value.clone()),
        tick_interval_days: None,
        excludes_weekends: false,
        excluded_weekdays: Vec::new(),
        excluded_dates: Vec::new(),
        weekend_start: 6,
        today_marker: true,
    };
    for statement in &ast.statements {
        let GanttStatement::Config(statement) = statement else {
            continue;
        };
        let value = statement.value.as_ref().map(|value| value.text.as_str());
        match statement.key.value.as_str() {
            "excludes" => {
                if let Some(value) = value {
                    push_gantt_excludes(value, &mut config);
                }
            }
            "weekend" => {
                if let Some(value) = value.and_then(gantt_weekday_index) {
                    config.weekend_start = value;
                }
            }
            "tickInterval" => {
                config.tick_interval_days = value.and_then(gantt_tick_interval_days);
            }
            "todayMarker" => {
                config.today_marker = value != Some("off");
            }
            _ => {}
        }
    }
    config
}

fn push_gantt_excludes(value: &str, config: &mut GanttScheduleConfig) {
    for token in value.split_ascii_whitespace() {
        if token == "weekends" {
            config.excludes_weekends = true;
        } else if let Some(weekday) = gantt_weekday_index(token) {
            push_unique_i32(&mut config.excluded_weekdays, weekday);
        } else if let Some(day) = gantt_date_day(token) {
            push_unique_i32(&mut config.excluded_dates, day);
        }
    }
}

fn push_unique_i32(values: &mut Vec<i32>, value: i32) {
    if !values.contains(&value) {
        values.push(value);
    }
}

fn gantt_weekday_index(value: &str) -> Option<i32> {
    match value.to_ascii_lowercase().as_str() {
        "sunday" => Some(0),
        "monday" => Some(1),
        "tuesday" => Some(2),
        "wednesday" => Some(3),
        "thursday" => Some(4),
        "friday" => Some(5),
        "saturday" => Some(6),
        _ => None,
    }
}

fn gantt_tick_interval_days(value: &str) -> Option<i32> {
    let suffix_start = value
        .find(|ch: char| !ch.is_ascii_digit())
        .unwrap_or(value.len());
    if suffix_start == 0 || suffix_start == value.len() {
        return None;
    }
    let amount = value[..suffix_start].parse::<i32>().ok()?;
    let unit = &value[suffix_start..];
    let days = match unit {
        "day" | "days" => amount,
        "week" | "weeks" => amount * 7,
        "month" | "months" => amount * 30,
        _ => return None,
    };
    Some(days.max(1))
}

fn gantt_axis_ticks(
    min_day: i32,
    max_day: i32,
    left_width: i32,
    day_width: i32,
    config: &GanttScheduleConfig,
) -> Vec<PositionedGanttTick> {
    let tick_days = if let Some(interval) = config.tick_interval_days {
        let mut days = Vec::new();
        let mut day = min_day;
        while day <= max_day {
            days.push(day);
            day += interval;
        }
        if days.last().copied() != Some(max_day) {
            days.push(max_day);
        }
        days
    } else if min_day == max_day {
        vec![min_day]
    } else {
        vec![min_day, max_day]
    };

    tick_days
        .into_iter()
        .map(|day| PositionedGanttTick {
            day,
            x: left_width + (day - min_day) * day_width,
            label: format_gantt_axis_day(day, &config.axis_format),
        })
        .collect()
}

fn gantt_effective_day_width(
    min_day: i32,
    max_day: i32,
    base_width: i32,
    config: &GanttScheduleConfig,
) -> i32 {
    let Some(interval) = config.tick_interval_days else {
        return base_width;
    };
    let label_width = [min_day, max_day]
        .into_iter()
        .map(|day| {
            format_gantt_axis_day(day, &config.axis_format)
                .chars()
                .count() as i32
        })
        .max()
        .unwrap_or(0);
    let needed = (label_width + 1 + interval - 1) / interval;

    base_width.max(needed)
}

fn format_gantt_axis_day(day: i32, format: &str) -> String {
    let (year, month, month_day) = civil_from_days(day);
    let weekday = weekday_from_day(day) as usize;
    let mut output = String::new();
    let mut chars = format.chars();
    while let Some(ch) = chars.next() {
        if ch != '%' {
            output.push(ch);
            continue;
        }
        match chars.next() {
            Some('%') => output.push('%'),
            Some('Y') => output.push_str(&format!("{year:04}")),
            Some('y') => output.push_str(&format!("{:02}", year.rem_euclid(100))),
            Some('m') => output.push_str(&format!("{month:02}")),
            Some('d') => output.push_str(&format!("{month_day:02}")),
            Some('e') => output.push_str(&format!("{month_day:>2}")),
            Some('b') => output.push_str(GANTT_MONTH_SHORT[(month - 1) as usize]),
            Some('B') => output.push_str(GANTT_MONTH_LONG[(month - 1) as usize]),
            Some('a') => output.push_str(GANTT_WEEKDAY_SHORT[weekday]),
            Some('A') => output.push_str(GANTT_WEEKDAY_LONG[weekday]),
            Some(other) => {
                output.push('%');
                output.push(other);
            }
            None => output.push('%'),
        }
    }
    output
}

const GANTT_MONTH_SHORT: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];
const GANTT_MONTH_LONG: [&str; 12] = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];
const GANTT_WEEKDAY_SHORT: [&str; 7] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const GANTT_WEEKDAY_LONG: [&str; 7] = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
];

fn civil_from_days(days: i32) -> (i32, i32, i32) {
    let days = days + 719_468;
    let era = if days >= 0 { days } else { days - 146_096 } / 146_097;
    let doe = days - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    let year = year + i32::from(month <= 2);
    (year, month, day)
}

fn gantt_today_day() -> Option<i32> {
    let duration = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?;
    Some((duration.as_secs() / 86_400) as i32)
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
        let mut cumulative = Vec::new();
        let mut slice_inputs = Vec::new();
        let mut running = 0u64;
        for slice in &ast.slices {
            let start_units = running;
            running = running.saturating_add(slice.value_units.value);
            cumulative.push(running);
            slice_inputs.push(PieSliceLayoutInput {
                label: slice.label.text.clone(),
                value_text: slice.value_text.value.clone(),
                value_units: slice.value_units.value,
                percent_basis_points: pie_percent_basis_points(slice.value_units.value, total),
                start_units,
                end_units: running,
            });
        }
        let title_width = ast
            .title
            .as_ref()
            .map_or(0, |title| title.text.chars().count() as i32);
        let legend_width = slice_inputs
            .iter()
            .map(|slice| pie_legend_width(slice, ast.show_data))
            .max()
            .unwrap_or(0);
        let regions = pie_layout_regions(
            self.config,
            ast.config.legend_position,
            legend_width,
            slice_inputs.len() as i32,
            title_width,
        );
        let center = Point {
            x: regions.pie_origin.x + self.config.radius_x,
            y: regions.pie_origin.y + self.config.top_padding + self.config.radius_y,
        };
        let cells = pie_cells(&self.config, center, total, &cumulative);
        let slices = slice_inputs
            .into_iter()
            .enumerate()
            .map(|(index, slice)| PositionedPieSlice {
                label_origin: pie_label_origin(
                    self.config,
                    center,
                    total,
                    slice.start_units,
                    slice.end_units,
                    slice.percent_basis_points,
                    ast.config.text_position_milli,
                ),
                legend_origin: Point {
                    x: regions.legend_origin.x,
                    y: regions.legend_origin.y + index as i32,
                },
                label: slice.label,
                value_text: slice.value_text,
                value_units: slice.value_units,
                percent_basis_points: slice.percent_basis_points,
            })
            .collect();

        PieLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            show_data: ast.show_data,
            center,
            slices,
            cells,
            size: regions.size,
        }
    }
}

impl QuadrantLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: QuadrantLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: QuadrantLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &QuadrantAst) -> QuadrantLayout {
        let title = ast.title.as_ref().map(|title| title.text.clone());
        let x_start = ast
            .x_axis
            .as_ref()
            .map_or_else(String::new, |axis| axis.start.text.clone());
        let x_end = ast
            .x_axis
            .as_ref()
            .map_or_else(String::new, |axis| axis.end.text.clone());
        let y_start = ast
            .y_axis
            .as_ref()
            .map_or_else(String::new, |axis| axis.start.text.clone());
        let y_end = ast
            .y_axis
            .as_ref()
            .map_or_else(String::new, |axis| axis.end.text.clone());
        let plot_y = if title.is_some() {
            self.config.top_padding + 1
        } else {
            0
        };
        let left_margin = self.config.left_margin.max(
            label_width(&y_start)
                .max(label_width(&y_end))
                .saturating_add(2),
        );
        let plot = Rect {
            origin: Point {
                x: left_margin,
                y: plot_y,
            },
            size: Size {
                width: self.config.plot_width.max(5),
                height: self.config.plot_height.max(5),
            },
        };
        let points = ast
            .points
            .iter()
            .map(|point| {
                let origin = quadrant_point_origin(plot, point.x.value, point.y.value);
                PositionedQuadrantPoint {
                    label: point.label.text.clone(),
                    x_value: point.x.value,
                    y_value: point.y.value,
                    point: origin,
                    label_origin: Point {
                        x: origin.x + 2,
                        y: origin.y,
                    },
                }
            })
            .collect::<Vec<_>>();
        let mut quadrants = ast
            .quadrants
            .iter()
            .map(|quadrant| PositionedQuadrantSection {
                index: quadrant.index.value,
                label: quadrant.label.text.clone(),
                origin: quadrant_section_origin(plot, quadrant.index.value),
            })
            .collect::<Vec<_>>();
        quadrants.sort_by_key(|quadrant| quadrant.index);

        let x_axis_y = plot.bottom() + self.config.label_gap;
        let mut width = plot
            .right()
            .max(label_width(&y_start))
            .max(label_width(&y_end));
        let mut height = x_axis_y + 1;
        if let Some(title) = &title {
            width = width.max(label_width(title));
        }
        width = width
            .max(plot.origin.x + label_width(&x_start))
            .max((plot.right() - label_width(&x_end)).max(0) + label_width(&x_end));
        for quadrant in &quadrants {
            width = width.max(quadrant.origin.x + label_width(&quadrant.label));
            height = height.max(quadrant.origin.y + 1);
        }
        for point in &points {
            width = width.max(point.label_origin.x + label_width(&point.label));
            height = height.max(point.label_origin.y + 1);
        }

        QuadrantLayout {
            title,
            x_start,
            x_end,
            y_start,
            y_end,
            plot,
            quadrants,
            points,
            size: Size { width, height },
        }
    }
}

fn quadrant_point_origin(plot: Rect, x_value: u16, y_value: u16) -> Point {
    let inner_width = (plot.size.width - 3).max(1);
    let inner_height = (plot.size.height - 3).max(1);
    Point {
        x: plot.origin.x + 1 + i32::from(x_value) * inner_width / 1000,
        y: plot.origin.y + 1 + i32::from(1000u16.saturating_sub(y_value)) * inner_height / 1000,
    }
}

fn quadrant_section_origin(plot: Rect, index: u8) -> Point {
    let mid_x = plot.origin.x + plot.size.width / 2;
    let mid_y = plot.origin.y + plot.size.height / 2;
    match index {
        1 => Point {
            x: mid_x + 2,
            y: plot.origin.y + 1,
        },
        2 => Point {
            x: plot.origin.x + 2,
            y: plot.origin.y + 1,
        },
        3 => Point {
            x: plot.origin.x + 2,
            y: mid_y + 1,
        },
        4 => Point {
            x: mid_x + 2,
            y: mid_y + 1,
        },
        _ => Point {
            x: plot.origin.x + 2,
            y: plot.origin.y + 1,
        },
    }
}

fn label_width(label: &str) -> i32 {
    label.chars().count() as i32
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PieSliceLayoutInput {
    label: String,
    value_text: String,
    value_units: u64,
    percent_basis_points: u16,
    start_units: u64,
    end_units: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct PieLayoutRegions {
    pie_origin: Point,
    legend_origin: Point,
    size: Size,
}

fn pie_layout_regions(
    config: PieLayoutConfig,
    legend_position: PieLegendPosition,
    legend_width: i32,
    legend_rows: i32,
    title_width: i32,
) -> PieLayoutRegions {
    let pie_width = config.radius_x * 2 + 1;
    let pie_height = config.top_padding + config.radius_y * 2 + 1;
    let vertical_gap = 1;
    match legend_position {
        PieLegendPosition::Left => {
            let pie_origin = Point {
                x: legend_width + config.legend_gap,
                y: 0,
            };
            let legend_origin = Point {
                x: 0,
                y: config.top_padding,
            };
            PieLayoutRegions {
                pie_origin,
                legend_origin,
                size: Size {
                    width: (pie_origin.x + pie_width).max(title_width),
                    height: pie_height.max(legend_origin.y + legend_rows),
                },
            }
        }
        PieLegendPosition::Top => {
            let pie_origin = Point {
                x: 0,
                y: config.top_padding + legend_rows + vertical_gap,
            };
            let legend_origin = Point {
                x: 0,
                y: config.top_padding,
            };
            PieLayoutRegions {
                pie_origin,
                legend_origin,
                size: Size {
                    width: pie_width.max(legend_width).max(title_width),
                    height: pie_origin.y + pie_height,
                },
            }
        }
        PieLegendPosition::Bottom => {
            let pie_origin = Point { x: 0, y: 0 };
            let legend_origin = Point {
                x: 0,
                y: pie_height + vertical_gap,
            };
            PieLayoutRegions {
                pie_origin,
                legend_origin,
                size: Size {
                    width: pie_width.max(legend_width).max(title_width),
                    height: legend_origin.y + legend_rows,
                },
            }
        }
        PieLegendPosition::Center => {
            let pie_origin = Point { x: 0, y: 0 };
            let center = Point {
                x: config.radius_x,
                y: config.top_padding + config.radius_y,
            };
            let legend_origin = Point {
                x: (center.x - legend_width / 2).max(0),
                y: (center.y - legend_rows / 2).max(config.top_padding),
            };
            PieLayoutRegions {
                pie_origin,
                legend_origin,
                size: Size {
                    width: pie_width
                        .max(legend_origin.x + legend_width)
                        .max(title_width),
                    height: pie_height.max(legend_origin.y + legend_rows),
                },
            }
        }
        PieLegendPosition::Right => {
            let pie_origin = Point { x: 0, y: 0 };
            let legend_origin = Point {
                x: config.radius_x * 2 + config.legend_gap,
                y: config.top_padding,
            };
            PieLayoutRegions {
                pie_origin,
                legend_origin,
                size: Size {
                    width: pie_width
                        .max(legend_origin.x + legend_width)
                        .max(title_width),
                    height: pie_height.max(legend_origin.y + legend_rows),
                },
            }
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

fn pie_label_origin(
    config: PieLayoutConfig,
    center: Point,
    total: u64,
    start_units: u64,
    end_units: u64,
    percent_basis_points: u16,
    text_position_milli: u16,
) -> Point {
    if total == 0 {
        return center;
    }
    let midpoint = start_units as f64 + (end_units.saturating_sub(start_units) as f64 / 2.0);
    let angle = midpoint / total as f64 * std::f64::consts::PI * 2.0;
    let ratio = f64::from(text_position_milli) / 1000.0;
    let label = pie_slice_percent_label(percent_basis_points);
    Point {
        x: (f64::from(center.x) + angle.sin() * f64::from(config.radius_x) * ratio).round() as i32
            - (label.chars().count() as i32 / 2),
        y: (f64::from(center.y) - angle.cos() * f64::from(config.radius_y) * ratio).round() as i32,
    }
}

fn pie_legend_width(slice: &PieSliceLayoutInput, show_data: bool) -> i32 {
    let mut width = 2 + slice.label.chars().count() as i32;
    if show_data {
        width += 3 + slice.value_text.chars().count() as i32;
    }
    width
}

fn pie_slice_percent_label(basis_points: u16) -> String {
    format!("{}%", (basis_points + 50) / 100)
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
        let mut actors = Vec::<String>::new();
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

            let task_actors = task
                .actors
                .iter()
                .map(|actor| actor.value.clone())
                .collect::<Vec<_>>();
            let actor_style_indices = task_actors
                .iter()
                .map(|actor| journey_actor_index(&mut actors, actor))
                .collect::<Vec<_>>();
            tasks.push(PositionedJourneyTask {
                index,
                label: task.label.text.clone(),
                section,
                score: task.score.value,
                actors: task_actors,
                actor_style_indices,
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
            actors,
            tasks,
            size: Size {
                width: title_width.max(section_width).max(task_width).max(1),
                height: y.max(self.config.top_padding + 1),
            },
        }
    }
}

fn journey_actor_index(actors: &mut Vec<String>, actor: &str) -> usize {
    if let Some(index) = actors.iter().position(|existing| existing == actor) {
        return index;
    }
    actors.push(actor.to_owned());
    actors.len() - 1
}

fn journey_task_width(task: &PositionedJourneyTask, config: JourneyLayoutConfig) -> i32 {
    let actor_width = journey_actor_text_width(task);
    let label_width = task.label.chars().count() as i32;
    let score_end = task.score_origin.x + config.score_label_width;
    label_width
        .max(score_end)
        .max(task.actors_origin.x + actor_width)
}

fn journey_actor_text_width(task: &PositionedJourneyTask) -> i32 {
    if task.actors.is_empty() {
        return 0;
    }
    let actor_names = task
        .actors
        .iter()
        .map(|actor| actor.chars().count() as i32 + 2)
        .sum::<i32>();
    let separators = (task.actors.len().saturating_sub(1) * 2) as i32;
    actor_names + separators
}

impl GitGraphLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: GitGraphLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: GitGraphLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &GitGraphAst) -> GitGraphLayout {
        let simulation = simulate_gitgraph(ast);
        let lanes = gitgraph_lanes(&simulation.branches);
        let max_step = simulation.commits.len().saturating_sub(1);
        let commits = simulation
            .commits
            .iter()
            .enumerate()
            .map(|(index, commit)| {
                let lane = lanes[commit.branch_index];
                let point = gitgraph_point(
                    ast.header.orientation.value,
                    lane,
                    index,
                    max_step,
                    self.config,
                );
                let id = commit.id.clone();
                PositionedGitGraphCommit {
                    index,
                    id: id.clone(),
                    tag: commit.tag.clone(),
                    branch: simulation.branches[commit.branch_index].name.clone(),
                    kind: commit.kind,
                    point,
                    label_origin: gitgraph_label_origin(ast.header.orientation.value, point, &id),
                    tag_origin: commit
                        .tag
                        .as_ref()
                        .map(|tag| gitgraph_tag_origin(ast.header.orientation.value, point, tag)),
                    is_merge: commit.is_merge,
                    is_cherry_pick: commit.is_cherry_pick,
                }
            })
            .collect::<Vec<_>>();
        let branches = gitgraph_positioned_branches(
            ast.header.orientation.value,
            &simulation.branches,
            &lanes,
            commits.len().max(1),
            self.config,
        );
        let mut edges = Vec::new();
        for (to, commit) in simulation.commits.iter().enumerate() {
            for from in commit.parents.iter().copied() {
                let points = route_gitgraph_edge(
                    ast.header.orientation.value,
                    commits[from].point,
                    commits[to].point,
                );
                edges.push(PositionedGitGraphEdge { from, to, points });
            }
        }
        let size = gitgraph_layout_size(&branches, &commits, &edges);

        GitGraphLayout {
            orientation: ast.header.orientation.value,
            branches,
            commits,
            edges,
            size,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SimulatedGitGraph {
    branches: Vec<SimulatedGitGraphBranch>,
    commits: Vec<SimulatedGitGraphCommit>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SimulatedGitGraphBranch {
    name: String,
    order: Option<i32>,
    insertion: usize,
    head: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SimulatedGitGraphCommit {
    id: String,
    tag: Option<String>,
    branch_index: usize,
    kind: GitGraphCommitKind,
    parents: Vec<usize>,
    is_merge: bool,
    is_cherry_pick: bool,
}

fn simulate_gitgraph(ast: &GitGraphAst) -> SimulatedGitGraph {
    let mut branches = vec![SimulatedGitGraphBranch {
        name: "main".to_owned(),
        order: Some(0),
        insertion: 0,
        head: None,
    }];
    let mut commits = Vec::new();
    let mut current_branch = 0usize;

    for statement in &ast.statements {
        match statement {
            GitGraphStatement::Commit(commit) => {
                let parent = branches[current_branch].head;
                let id = gitgraph_commit_id(commit, commits.len(), "c");
                push_simulated_gitgraph_commit(
                    &mut branches,
                    &mut commits,
                    SimulatedGitGraphCommit {
                        id,
                        tag: commit.tag.as_ref().map(|tag| tag.value.clone()),
                        branch_index: current_branch,
                        kind: commit.kind.value,
                        parents: parent.into_iter().collect(),
                        is_merge: false,
                        is_cherry_pick: false,
                    },
                );
            }
            GitGraphStatement::Branch(branch) => {
                let head = branches[current_branch].head;
                current_branch = ensure_gitgraph_branch(
                    &mut branches,
                    &branch.name.value,
                    branch.order.map(|order| order.value),
                    head,
                );
            }
            GitGraphStatement::Checkout(branch) => {
                current_branch = ensure_gitgraph_branch(&mut branches, &branch.value, None, None);
            }
            GitGraphStatement::Merge(merge) => {
                let source_branch =
                    ensure_gitgraph_branch(&mut branches, &merge.branch.value, None, None);
                let mut parents = Vec::new();
                if let Some(parent) = branches[current_branch].head {
                    parents.push(parent);
                }
                if let Some(parent) = branches[source_branch].head
                    && !parents.contains(&parent)
                {
                    parents.push(parent);
                }
                let id = merge
                    .id
                    .as_ref()
                    .map_or_else(|| format!("m{}", commits.len() + 1), |id| id.value.clone());
                push_simulated_gitgraph_commit(
                    &mut branches,
                    &mut commits,
                    SimulatedGitGraphCommit {
                        id,
                        tag: merge.tag.as_ref().map(|tag| tag.value.clone()),
                        branch_index: current_branch,
                        kind: merge.kind.value,
                        parents,
                        is_merge: true,
                        is_cherry_pick: false,
                    },
                );
            }
            GitGraphStatement::CherryPick(cherry_pick) => {
                let mut parents = Vec::new();
                if let Some(parent) = branches[current_branch].head {
                    parents.push(parent);
                }
                if let Some(parent) = commits
                    .iter()
                    .position(|commit| commit.id == cherry_pick.id.value)
                    && !parents.contains(&parent)
                {
                    parents.push(parent);
                }
                let id = format!("pick-{}", cherry_pick.id.value);
                push_simulated_gitgraph_commit(
                    &mut branches,
                    &mut commits,
                    SimulatedGitGraphCommit {
                        id,
                        tag: Some(cherry_pick.id.value.clone()),
                        branch_index: current_branch,
                        kind: GitGraphCommitKind::Highlight,
                        parents,
                        is_merge: false,
                        is_cherry_pick: true,
                    },
                );
            }
            GitGraphStatement::Comment(_) | GitGraphStatement::Directive(_) => {}
        }
    }

    SimulatedGitGraph { branches, commits }
}

fn push_simulated_gitgraph_commit(
    branches: &mut [SimulatedGitGraphBranch],
    commits: &mut Vec<SimulatedGitGraphCommit>,
    commit: SimulatedGitGraphCommit,
) {
    let index = commits.len();
    let branch_index = commit.branch_index;
    commits.push(commit);
    branches[branch_index].head = Some(index);
}

fn gitgraph_commit_id(commit: &GitGraphCommit, index: usize, prefix: &str) -> String {
    commit
        .id
        .as_ref()
        .map_or_else(|| format!("{prefix}{}", index + 1), |id| id.value.clone())
}

fn ensure_gitgraph_branch(
    branches: &mut Vec<SimulatedGitGraphBranch>,
    name: &str,
    order: Option<i32>,
    head: Option<usize>,
) -> usize {
    if let Some(index) = branches.iter().position(|branch| branch.name == name) {
        if order.is_some() {
            branches[index].order = order;
        }
        if branches[index].head.is_none() {
            branches[index].head = head;
        }
        return index;
    }
    let insertion = branches.len();
    branches.push(SimulatedGitGraphBranch {
        name: name.to_owned(),
        order,
        insertion,
        head,
    });
    insertion
}

fn gitgraph_lanes(branches: &[SimulatedGitGraphBranch]) -> Vec<usize> {
    let mut ordered = (0..branches.len()).collect::<Vec<_>>();
    ordered.sort_by_key(|index| {
        let branch = &branches[*index];
        if branch.name == "main" {
            (0, 0, branch.insertion)
        } else if let Some(order) = branch.order {
            (2, order, branch.insertion)
        } else {
            (1, 0, branch.insertion)
        }
    });
    let mut lanes = vec![0; branches.len()];
    for (lane, branch_index) in ordered.into_iter().enumerate() {
        lanes[branch_index] = lane;
    }
    lanes
}

fn gitgraph_point(
    orientation: GitGraphOrientation,
    lane: usize,
    step: usize,
    max_step: usize,
    config: GitGraphLayoutConfig,
) -> Point {
    let lane_offset = lane as i32 * config.branch_spacing;
    let step_offset = step as i32 * config.commit_spacing;
    let max_offset = max_step as i32 * config.commit_spacing;
    match orientation {
        GitGraphOrientation::LeftRight => Point {
            x: config.label_width + config.left_padding + step_offset,
            y: config.top_padding + lane_offset,
        },
        GitGraphOrientation::TopBottom => Point {
            x: config.left_padding + lane_offset,
            y: config.top_padding + step_offset,
        },
        GitGraphOrientation::BottomTop => Point {
            x: config.left_padding + lane_offset,
            y: config.top_padding + max_offset - step_offset,
        },
    }
}

fn gitgraph_label_origin(orientation: GitGraphOrientation, point: Point, label: &str) -> Point {
    let width = label.chars().count() as i32;
    match orientation {
        GitGraphOrientation::LeftRight => Point {
            x: point.x - width / 2,
            y: point.y + 1,
        },
        GitGraphOrientation::TopBottom | GitGraphOrientation::BottomTop => Point {
            x: point.x + 2,
            y: point.y,
        },
    }
}

fn gitgraph_tag_origin(orientation: GitGraphOrientation, point: Point, tag: &str) -> Point {
    let width = tag.chars().count() as i32 + 2;
    match orientation {
        GitGraphOrientation::LeftRight => Point {
            x: point.x - width / 2,
            y: point.y - 1,
        },
        GitGraphOrientation::TopBottom | GitGraphOrientation::BottomTop => Point {
            x: point.x + 2,
            y: point.y - 1,
        },
    }
}

fn gitgraph_positioned_branches(
    orientation: GitGraphOrientation,
    branches: &[SimulatedGitGraphBranch],
    lanes: &[usize],
    commit_count: usize,
    config: GitGraphLayoutConfig,
) -> Vec<PositionedGitGraphBranch> {
    let max_step = commit_count.saturating_sub(1);
    branches
        .iter()
        .enumerate()
        .map(|(index, branch)| {
            let lane = lanes[index];
            let start = gitgraph_point(orientation, lane, 0, max_step, config);
            let end = gitgraph_point(orientation, lane, max_step, max_step, config);
            let label_origin = match orientation {
                GitGraphOrientation::LeftRight => Point { x: 0, y: start.y },
                GitGraphOrientation::TopBottom | GitGraphOrientation::BottomTop => {
                    Point { x: start.x, y: 0 }
                }
            };
            PositionedGitGraphBranch {
                name: branch.name.clone(),
                lane,
                label_origin,
                points: vec![start, end],
            }
        })
        .collect()
}

fn route_gitgraph_edge(orientation: GitGraphOrientation, from: Point, to: Point) -> Vec<Point> {
    if from.x == to.x || from.y == to.y {
        return vec![from, to];
    }
    match orientation {
        GitGraphOrientation::LeftRight => vec![from, Point { x: to.x, y: from.y }, to],
        GitGraphOrientation::TopBottom | GitGraphOrientation::BottomTop => {
            vec![from, Point { x: from.x, y: to.y }, to]
        }
    }
}

fn gitgraph_layout_size(
    branches: &[PositionedGitGraphBranch],
    commits: &[PositionedGitGraphCommit],
    edges: &[PositionedGitGraphEdge],
) -> Size {
    let mut width = 1;
    let mut height = 1;
    for branch in branches {
        width = width.max(branch.label_origin.x + branch.name.chars().count() as i32);
        height = height.max(branch.label_origin.y + 1);
        for point in &branch.points {
            width = width.max(point.x + 1);
            height = height.max(point.y + 1);
        }
    }
    for commit in commits {
        width = width.max(commit.point.x + 1);
        height = height.max(commit.point.y + 1);
        width = width.max(commit.label_origin.x + commit.id.chars().count() as i32);
        height = height.max(commit.label_origin.y + 1);
        if let (Some(tag), Some(origin)) = (&commit.tag, commit.tag_origin) {
            width = width.max(origin.x + tag.chars().count() as i32 + 2);
            height = height.max(origin.y + 1);
        }
    }
    for edge in edges {
        for point in &edge.points {
            width = width.max(point.x + 1);
            height = height.max(point.y + 1);
        }
    }
    Size {
        width: width + 2,
        height: height + 2,
    }
}

impl TimelineLayoutEngine {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            config: TimelineLayoutConfig::default_values(),
        }
    }

    #[must_use]
    pub const fn new(config: TimelineLayoutConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub fn layout(&self, ast: &TimelineAst) -> TimelineLayout {
        let groups = timeline_groups(ast);
        let mut sections = Vec::new();
        let mut periods = Vec::new();
        let mut y = self.config.top_padding;

        for group in groups {
            let start_index = periods.len();
            let axis_y = y + if group.section.is_some() { 2 } else { 1 };
            if let Some(label) = &group.section {
                sections.push(PositionedTimelineSection {
                    label: Some(label.clone()),
                    y,
                    axis_start: Point { x: 0, y: axis_y },
                    axis_end: Point { x: 0, y: axis_y },
                });
            }

            let mut max_events = 1usize;
            for (offset, period) in group.periods.iter().enumerate() {
                let x = self.config.left_padding + offset as i32 * self.config.period_spacing;
                max_events = max_events.max(period.events.len());
                periods.push(PositionedTimelinePeriod {
                    index: period.index,
                    label: period.label.clone(),
                    section: group.section.clone(),
                    events: period.events.clone(),
                    point: Point { x, y: axis_y },
                    label_origin: centered_origin(x, axis_y - 1, &period.label),
                    event_origins: period
                        .events
                        .iter()
                        .enumerate()
                        .map(|(event_index, _)| Point {
                            x: x + 2,
                            y: axis_y + 1 + event_index as i32,
                        })
                        .collect(),
                });
            }

            if let Some(section) = sections.last_mut()
                && group.section.is_some()
            {
                let group_periods = &periods[start_index..];
                let start = group_periods
                    .first()
                    .map_or(self.config.left_padding, |p| p.point.x);
                let end = group_periods.last().map_or(start, |p| p.point.x);
                section.axis_start = Point {
                    x: start,
                    y: axis_y,
                };
                section.axis_end = Point { x: end, y: axis_y };
            } else if group.section.is_none() {
                let group_periods = &periods[start_index..];
                let start = group_periods
                    .first()
                    .map_or(self.config.left_padding, |p| p.point.x);
                let end = group_periods.last().map_or(start, |p| p.point.x);
                sections.push(PositionedTimelineSection {
                    label: None,
                    y,
                    axis_start: Point {
                        x: start,
                        y: axis_y,
                    },
                    axis_end: Point { x: end, y: axis_y },
                });
            }

            y = axis_y + max_events as i32 + self.config.section_gap;
        }

        let size = timeline_layout_size(
            ast.title.as_ref().map(|title| title.text.as_str()),
            &periods,
        );

        TimelineLayout {
            title: ast.title.as_ref().map(|title| title.text.clone()),
            sections,
            periods,
            size,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct TimelineGroup {
    section: Option<String>,
    periods: Vec<TimelineGroupPeriod>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct TimelineGroupPeriod {
    index: usize,
    label: String,
    events: Vec<String>,
}

fn timeline_groups(ast: &TimelineAst) -> Vec<TimelineGroup> {
    let mut groups = Vec::new();
    let mut current_section = None::<String>;
    for (index, period) in ast.periods.iter().enumerate() {
        let section = period.section.as_ref().map(|section| section.text.clone());
        if groups.is_empty() || section != current_section {
            groups.push(TimelineGroup {
                section: section.clone(),
                periods: Vec::new(),
            });
            current_section = section.clone();
        }
        groups
            .last_mut()
            .expect("group exists")
            .periods
            .push(TimelineGroupPeriod {
                index,
                label: period.label.text.clone(),
                events: period
                    .events
                    .iter()
                    .map(|event| event.text.clone())
                    .collect(),
            });
    }
    groups
}

fn centered_origin(center_x: i32, y: i32, label: &str) -> Point {
    Point {
        x: (center_x - label.chars().count() as i32 / 2).max(0),
        y,
    }
}

fn timeline_layout_size(title: Option<&str>, periods: &[PositionedTimelinePeriod]) -> Size {
    let mut width = title.map_or(1, |title| title.chars().count() as i32);
    let mut height = 1;
    for period in periods {
        width = width.max(period.point.x + 1);
        height = height.max(period.point.y + 1);
        width = width.max(period.label_origin.x + period.label.chars().count() as i32);
        height = height.max(period.label_origin.y + 1);
        for (event, origin) in period.events.iter().zip(&period.event_origins) {
            width = width.max(origin.x + event.chars().count() as i32);
            height = height.max(origin.y + 1);
        }
    }
    Size {
        width: width + 2,
        height: height + 2,
    }
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
            SequenceStatement::Create(create) => {
                ensure_sequence_participant(&mut participants, &create.participant);
            }
            SequenceStatement::Destroy(destroy) => {
                ensure_sequence_id(&mut participants, &destroy.participant.value);
            }
            SequenceStatement::Box(sequence_box) => {
                ensure_sequence_box_participants(&mut participants, sequence_box);
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
        SequenceStatement::Create(create) => {
            ensure_sequence_participant(participants, &create.participant);
        }
        SequenceStatement::Destroy(destroy) => {
            ensure_sequence_id(participants, &destroy.participant.value);
        }
        SequenceStatement::Box(sequence_box) => {
            ensure_sequence_box_participants(participants, sequence_box);
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

fn ensure_sequence_box_participants(
    participants: &mut Vec<SequenceParticipantRef>,
    sequence_box: &SequenceBox,
) {
    for participant in &sequence_box.participants {
        ensure_sequence_id(participants, &participant.value);
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
    shape: FlowShape,
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
                    shape: FlowShape::Rectangle,
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
                    shape: FlowShape::Rectangle,
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

    fn from_requirement_ast(ast: &RequirementAst) -> Self {
        let mut graph = Self {
            nodes: Vec::new(),
            edges: Vec::new(),
            subgraphs: Vec::new(),
        };
        for requirement in &ast.requirements {
            graph.push_unique_node(&requirement.name.value);
        }
        for element in &ast.elements {
            graph.push_unique_node(&element.name.value);
        }
        for relationship in &ast.relationships {
            graph.push_unique_node(&relationship.from.value);
            graph.push_unique_node(&relationship.to.value);
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

    fn push_unique_node(&mut self, id: &str) {
        if self.nodes.iter().any(|node| node.id == id) {
            return;
        }
        self.nodes.push(LayoutNode {
            id: id.to_owned(),
            label: id.to_owned(),
            shape: FlowShape::Rectangle,
        });
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
            if self.nodes[index].shape == FlowShape::Rectangle
                || node.shape.value != FlowShape::Rectangle
            {
                self.nodes[index].shape = node.shape.value.clone();
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
            shape: node.shape.value.clone(),
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
    let edges = graph
        .edges
        .iter()
        .map(|edge| optimise::LayeredEdge::new(edge.from, edge.to))
        .collect::<Vec<_>>();
    optimise::minimise_crossings(layers, &edges)
}

fn place_graph(
    graph: &LayoutGraph,
    layers: &[usize],
    order: &[usize],
    direction: Direction,
    config: FlowLayoutConfig,
) -> FlowLayout {
    let labels = graph
        .nodes
        .iter()
        .map(|node| wrap_label(&node.label, config.max_label_width))
        .collect::<Vec<_>>();
    let sizes = graph
        .nodes
        .iter()
        .enumerate()
        .map(|(index, _)| node_size(&labels[index], config))
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
            label: labels[index].clone(),
            shape: node.shape.clone(),
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
    let (line_width, line_count) = label_metrics(label);
    Size {
        width: config
            .min_node_width
            .max(line_width + config.horizontal_padding),
        height: config.node_height.max(line_count + 2),
    }
}

fn label_metrics(label: &str) -> (i32, i32) {
    let mut width = 0i32;
    let mut count = 0i32;
    for line in label.lines() {
        width = width.max(line.chars().count() as i32);
        count += 1;
    }
    (width, count.max(1))
}

fn wrap_label(label: &str, max_label_width: Option<i32>) -> String {
    let Some(width) = max_label_width.filter(|width| *width > 0) else {
        return label.to_owned();
    };
    let width = width as usize;
    let mut lines = Vec::new();
    if label.is_empty() {
        return String::new();
    }
    for line in label.lines() {
        wrap_label_line(line, width, &mut lines);
    }
    lines.join("\n")
}

fn wrap_label_line(line: &str, width: usize, lines: &mut Vec<String>) {
    if line.chars().count() <= width {
        lines.push(line.to_owned());
        return;
    }
    let mut current = String::new();
    for word in line.split_whitespace() {
        let word_width = word.chars().count();
        let current_width = current.chars().count();
        if current.is_empty() && word_width <= width {
            current.push_str(word);
        } else if !current.is_empty() && current_width + 1 + word_width <= width {
            current.push(' ');
            current.push_str(word);
        } else {
            if !current.is_empty() {
                lines.push(std::mem::take(&mut current));
            }
            push_wrapped_word(word, width, lines, &mut current);
        }
    }
    if !current.is_empty() {
        lines.push(current);
    } else if lines.is_empty() {
        lines.push(String::new());
    }
}

fn push_wrapped_word(word: &str, width: usize, lines: &mut Vec<String>, current: &mut String) {
    if word.chars().count() <= width {
        current.push_str(word);
        return;
    }
    let mut chunk = String::new();
    let mut count = 0usize;
    for character in word.chars() {
        chunk.push(character);
        count += 1;
        if count == width {
            lines.push(std::mem::take(&mut chunk));
            count = 0;
        }
    }
    if !chunk.is_empty() {
        current.push_str(&chunk);
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

fn layout_size_with_requirement_relationships(
    size: Size,
    relationships: &[PositionedRequirementRelationship],
) -> Size {
    Size {
        width: relationships
            .iter()
            .flat_map(|relationship| {
                relationship
                    .points
                    .iter()
                    .map(|point| point.x + 1)
                    .chain(relationship_label_width(relationship).into_iter())
            })
            .fold(size.width, i32::max),
        height: relationships
            .iter()
            .flat_map(|relationship| relationship.points.iter().map(|point| point.y + 1))
            .fold(size.height, i32::max),
    }
}

fn relationship_label_width(relationship: &PositionedRequirementRelationship) -> Option<i32> {
    let first = relationship.points.first()?;
    let last = relationship.points.last()?;
    let mid_x = (first.x + last.x) / 2;
    Some(mid_x + relationship.label.chars().count() as i32 + 1)
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
    use super::{
        C4LayoutEngine, FlowLayoutConfig, FlowLayoutEngine, Point, SequenceLayoutEngine,
        StateLayoutEngine, optimise,
    };
    use crate::ast::{ArrowHead, DiagramKind, FlowShape, FlowchartAst};
    use crate::ast::{
        Direction, FlowEdge, FlowEdgeLink, FlowEdgeStroke, FlowNode, FlowStatement, FlowSubgraph,
        FlowchartDirective, FlowchartHeader, Label, LabelKind, SequenceArrow, SequenceAst,
        SequenceControlBlock, SequenceControlKind, SequenceHeader, SequenceMessage, SequenceNote,
        SequenceNotePlacement, SequenceParticipant, SequenceParticipantKind, SequenceStatement,
        Span, Spanned, StateAst, StateDirective, StateHeader, StateNode, StateNodeKind,
        StateStatement, StateTransition,
    };
    use crate::parser::Parser;

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
    fn wraps_flowchart_labels_to_max_width() {
        let ast = flowchart(
            Direction::TopDown,
            vec![FlowStatement::Node(labelled_node("A", "Alpha Beta Gamma"))],
        );
        let layout = FlowLayoutEngine::new(FlowLayoutConfig {
            max_label_width: Some(5),
            ..FlowLayoutConfig::default()
        })
        .layout(&ast);
        let node = node(&layout, "A");

        assert_eq!(node.label, "Alpha\nBeta\nGamma");
        assert_eq!(node.rect.size.width, 9);
        assert_eq!(node.rect.size.height, 5);
        assert_eq!(
            super::wrap_label("SuperLongName", Some(4)),
            "Supe\nrLon\ngNam\ne"
        );
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

    #[test]
    fn optimise_reduces_two_layer_crossings() {
        let layers = [0, 0, 1, 1];
        let edges = [
            optimise::LayeredEdge::new(0, 3),
            optimise::LayeredEdge::new(1, 2),
        ];
        let initial_order = [0, 1, 0, 1];
        let optimised_order = optimise::minimise_crossings(&layers, &edges);

        assert_eq!(
            optimise::count_crossings(&layers, &initial_order, &edges),
            1
        );
        assert_eq!(
            optimise::count_crossings(&layers, &optimised_order, &edges),
            0
        );
        assert!(optimised_order[3] < optimised_order[2]);
    }

    #[test]
    fn flowchart_layout_uses_crossing_minimisation_order() {
        let ast = flowchart(
            Direction::TopDown,
            vec![
                FlowStatement::Node(simple_node("A")),
                FlowStatement::Node(simple_node("B")),
                FlowStatement::Node(simple_node("C")),
                FlowStatement::Node(simple_node("D")),
                FlowStatement::Edge(Box::new(edge("A", "D"))),
                FlowStatement::Edge(Box::new(edge("B", "C"))),
            ],
        );

        let layout = FlowLayoutEngine::default().layout(&ast);

        assert!(node(&layout, "D").rect.origin.x < node(&layout, "C").rect.origin.x);
        assert_eq!(node(&layout, "D").order, 0);
        assert_eq!(node(&layout, "C").order, 1);
    }

    #[test]
    fn c4_layout_calls_update_direction_and_row_limit() {
        let diagram = Parser::parse_diagram(
            r#"C4Context
LAYOUT_LEFT_RIGHT()
UpdateLayoutConfig($c4ShapeInRow="2")
System(a, "A")
System(b, "B")
System(c, "C")"#,
        )
        .unwrap();
        let DiagramKind::C4(ast) = diagram.kind else {
            panic!("expected C4 diagram");
        };

        let layout = C4LayoutEngine::default().layout(&ast);
        let a = c4_element(&layout, "a");
        let b = c4_element(&layout, "b");
        let c = c4_element(&layout, "c");

        assert_eq!(a.rect.origin.x, b.rect.origin.x);
        assert!(b.rect.origin.y > a.rect.origin.y);
        assert!(c.rect.origin.x > a.rect.origin.x);
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

    fn c4_element<'a>(layout: &'a super::C4Layout, id: &str) -> &'a super::PositionedC4Element {
        layout
            .elements
            .iter()
            .find(|element| element.id == id)
            .unwrap()
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
        labelled_node(id, id)
    }

    fn labelled_node(id: &str, label: &str) -> FlowNode {
        FlowNode {
            id: Spanned::new(id.to_owned(), Span::new(0, 0)),
            label: Some(Label {
                text: label.to_owned(),
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
            activation: None,
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
