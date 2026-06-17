#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagram {
    pub metadata: DiagramMetadata,
    pub directives: Vec<MermaidDirective>,
    pub kind: DiagramKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DiagramKind {
    Flowchart(Box<FlowchartAst>),
    Sequence(Box<SequenceAst>),
    State(Box<StateAst>),
    Class(Box<ClassAst>),
    Er(Box<ErAst>),
    Gantt(Box<GanttAst>),
    Pie(Box<PieAst>),
    Quadrant(Box<QuadrantAst>),
    ZenUml(Box<ZenUmlAst>),
    Sankey(Box<SankeyAst>),
    XyChart(Box<XyChartAst>),
    Block(Box<BlockDiagramAst>),
    Packet(Box<PacketAst>),
    Kanban(Box<KanbanAst>),
    Architecture(Box<ArchitectureAst>),
    Radar(Box<RadarAst>),
    EventModeling(Box<EventModelingAst>),
    Treemap(Box<TreemapAst>),
    Venn(Box<VennAst>),
    Ishikawa(Box<IshikawaAst>),
    Wardley(Box<WardleyAst>),
    Mindmap(Box<MindmapAst>),
    Journey(Box<JourneyAst>),
    GitGraph(Box<GitGraphAst>),
    Timeline(Box<TimelineAst>),
    Requirement(Box<RequirementAst>),
    C4(Box<C4Ast>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiagramMetadata {
    pub title: Option<Label>,
    pub accessibility_title: Option<Label>,
    pub accessibility_description: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    #[must_use]
    pub const fn new(start: usize, end: usize) -> Self {
        Self { start, end }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Spanned<T> {
    pub value: T,
    pub span: Span,
}

impl<T> Spanned<T> {
    #[must_use]
    pub const fn new(value: T, span: Span) -> Self {
        Self { value, span }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlowchartDirective {
    Flowchart,
    Graph,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    TopDown,
    BottomTop,
    LeftRight,
    RightLeft,
}

impl Direction {
    #[must_use]
    pub const fn from_mermaid(value: &str) -> Option<Self> {
        match value.as_bytes() {
            b"TB" | b"TD" => Some(Self::TopDown),
            b"BT" => Some(Self::BottomTop),
            b"LR" => Some(Self::LeftRight),
            b"RL" => Some(Self::RightLeft),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowchartHeader {
    pub directive: Spanned<FlowchartDirective>,
    pub direction: Spanned<Direction>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LabelKind {
    Plain,
    String,
    Markdown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Label {
    pub text: String,
    pub kind: LabelKind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FlowShape {
    Rectangle,
    Round,
    Stadium,
    Subroutine,
    Cylinder,
    Circle,
    Asymmetric,
    Rhombus,
    Hexagon,
    Parallelogram,
    ParallelogramAlt,
    Trapezoid,
    TrapezoidAlt,
    DoubleCircle,
    Named(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowNode {
    pub id: Spanned<String>,
    pub label: Option<Label>,
    pub shape: Spanned<FlowShape>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlowEdgeStroke {
    Normal,
    Thick,
    Dotted,
    Invisible,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArrowHead {
    None,
    Arrow,
    Circle,
    Cross,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FlowEdgeLink {
    pub stroke: FlowEdgeStroke,
    pub arrow_start: ArrowHead,
    pub arrow_end: ArrowHead,
    pub min_length: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowEdge {
    pub from: FlowNode,
    pub to: FlowNode,
    pub link: Spanned<FlowEdgeLink>,
    pub label: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FlowStatement {
    Node(FlowNode),
    Edge(Box<FlowEdge>),
    Subgraph(FlowSubgraph),
    ClassDef(FlowClassDef),
    ClassApply(FlowClassApply),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowSubgraph {
    pub id: Spanned<String>,
    pub label: Option<Label>,
    pub direction: Option<Spanned<Direction>>,
    pub statements: Vec<FlowStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowStyleDeclaration {
    pub key: Spanned<String>,
    pub value: Spanned<String>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowClassDef {
    pub class_ids: Vec<Spanned<String>>,
    pub styles: Vec<FlowStyleDeclaration>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowClassApply {
    pub node_ids: Vec<Spanned<String>>,
    pub class_ids: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MermaidComment {
    pub text: String,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MermaidDirective {
    pub raw: String,
    pub key: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowchartAst {
    pub header: FlowchartHeader,
    pub statements: Vec<FlowStatement>,
    pub nodes: Vec<FlowNode>,
    pub edges: Vec<FlowEdge>,
    pub subgraphs: Vec<FlowSubgraph>,
    pub classes: Vec<FlowClassDef>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceAst {
    pub header: SequenceHeader,
    pub statements: Vec<SequenceStatement>,
    pub participants: Vec<SequenceParticipant>,
    pub boxes: Vec<SequenceBox>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SequenceHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SequenceStatement {
    Participant(Box<SequenceParticipant>),
    Create(Box<SequenceCreate>),
    Destroy(Box<SequenceDestroy>),
    Box(Box<SequenceBox>),
    Message(Box<SequenceMessage>),
    ActivationStart(Spanned<String>),
    ActivationEnd(Spanned<String>),
    Note(Box<SequenceNote>),
    Control(Box<SequenceControlBlock>),
    AutoNumber(SequenceAutoNumber),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceParticipant {
    pub id: Spanned<String>,
    pub alias: Option<Label>,
    pub kind: SequenceParticipantKind,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SequenceParticipantKind {
    Participant,
    Actor,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceCreate {
    pub participant: SequenceParticipant,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceDestroy {
    pub participant: Spanned<String>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceBox {
    pub label: Option<Label>,
    pub participants: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceMessage {
    pub from: Spanned<String>,
    pub to: Spanned<String>,
    pub arrow: SequenceArrow,
    pub activation: Option<Spanned<SequenceActivation>>,
    pub label: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SequenceArrow {
    SolidLine,
    DottedLine,
    SolidArrow,
    DottedArrow,
    SolidCross,
    DottedCross,
    SolidOpen,
    DottedOpen,
    SolidBidirectional,
    DottedBidirectional,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SequenceActivation {
    Start,
    End,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceNote {
    pub placement: SequenceNotePlacement,
    pub participants: Vec<Spanned<String>>,
    pub label: Label,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SequenceNotePlacement {
    LeftOf,
    RightOf,
    Over,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceControlBlock {
    pub kind: SequenceControlKind,
    pub label: Option<Label>,
    pub statements: Vec<SequenceStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SequenceControlKind {
    Loop,
    Alt,
    Opt,
    Par,
    Critical,
    Break,
    Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceAutoNumber {
    pub start: Option<Spanned<String>>,
    pub step: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StateAst {
    pub header: StateHeader,
    pub direction: Option<Spanned<Direction>>,
    pub statements: Vec<StateStatement>,
    pub states: Vec<StateNode>,
    pub transitions: Vec<StateTransition>,
    pub classes: Vec<FlowClassDef>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StateHeader {
    pub directive: StateDirective,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StateDirective {
    StateDiagram,
    StateDiagramV2,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StateStatement {
    State(Box<StateNode>),
    Transition(Box<StateTransition>),
    Composite(Box<StateNode>),
    ClassDef(FlowClassDef),
    ClassApply(StateClassApply),
    Direction(Spanned<Direction>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StateNode {
    pub id: Spanned<String>,
    pub label: Option<Label>,
    pub kind: StateNodeKind,
    pub descriptions: Vec<Label>,
    pub note: Option<StateNote>,
    pub children: Vec<StateStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StateNodeKind {
    Default,
    Start,
    End,
    Fork,
    Join,
    Choice,
    Divider,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StateTransition {
    pub from: Spanned<String>,
    pub to: Spanned<String>,
    pub label: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StateNote {
    pub placement: StateNotePlacement,
    pub label: Label,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StateNotePlacement {
    LeftOf,
    RightOf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StateClassApply {
    pub state_ids: Vec<Spanned<String>>,
    pub class_ids: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassAst {
    pub header: ClassHeader,
    pub direction: Option<Spanned<Direction>>,
    pub statements: Vec<ClassStatement>,
    pub classes: Vec<ClassNode>,
    pub relationships: Vec<ClassRelationship>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ClassHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClassStatement {
    Class(Box<ClassNode>),
    Member(Box<ClassMemberAssignment>),
    Relationship(Box<ClassRelationship>),
    Direction(Spanned<Direction>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassNode {
    pub id: Spanned<String>,
    pub annotations: Vec<Label>,
    pub members: Vec<ClassMember>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassMemberAssignment {
    pub class_id: Spanned<String>,
    pub member: ClassMember,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassMember {
    pub visibility: Option<char>,
    pub name: Spanned<String>,
    pub ty: Option<Label>,
    pub kind: ClassMemberKind,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClassMemberKind {
    Field,
    Method,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassRelationship {
    pub from: Spanned<String>,
    pub to: Spanned<String>,
    pub line: ClassRelationshipLine,
    pub start_marker: ClassRelationshipMarker,
    pub end_marker: ClassRelationshipMarker,
    pub start_cardinality: Option<Label>,
    pub end_cardinality: Option<Label>,
    pub label: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClassRelationshipLine {
    Solid,
    Dotted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClassRelationshipMarker {
    None,
    Arrow,
    Inheritance,
    Aggregation,
    Composition,
    One,
    ZeroOrOne,
    Many,
    ZeroOrMany,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ErAst {
    pub header: ErHeader,
    pub statements: Vec<ErStatement>,
    pub entities: Vec<ErEntity>,
    pub relationships: Vec<ErRelationship>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ErHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ErStatement {
    Entity(Box<ErEntity>),
    Relationship(Box<ErRelationship>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ErEntity {
    pub id: Spanned<String>,
    pub attributes: Vec<ErAttribute>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ErAttribute {
    pub ty: Spanned<String>,
    pub name: Spanned<String>,
    pub key: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ErRelationship {
    pub from: Spanned<String>,
    pub to: Spanned<String>,
    pub start_cardinality: ErCardinality,
    pub end_cardinality: ErCardinality,
    pub identifying: bool,
    pub label: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErCardinality {
    One,
    ZeroOrOne,
    OneOrMany,
    ZeroOrMany,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GanttAst {
    pub header: GanttHeader,
    pub title: Option<Label>,
    pub date_format: Option<Spanned<String>>,
    pub axis_format: Option<Spanned<String>>,
    pub statements: Vec<GanttStatement>,
    pub tasks: Vec<GanttTask>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GanttHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GanttStatement {
    Title(Label),
    DateFormat(Spanned<String>),
    AxisFormat(Spanned<String>),
    Section(Label),
    Task(Box<GanttTask>),
    Config(GanttConfigStatement),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GanttConfigStatement {
    pub key: Spanned<String>,
    pub value: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GanttTask {
    pub title: Label,
    pub section: Option<Label>,
    pub tags: Vec<GanttTaskTag>,
    pub id: Option<Spanned<String>>,
    pub metadata: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GanttTaskTag {
    Active,
    Done,
    Crit,
    Milestone,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PieAst {
    pub header: PieHeader,
    pub title: Option<Label>,
    pub show_data: bool,
    pub config: PieConfig,
    pub statements: Vec<PieStatement>,
    pub slices: Vec<PieSlice>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PieHeader {
    pub show_data: bool,
    pub title: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PieConfig {
    pub text_position_milli: u16,
    pub legend_position: PieLegendPosition,
}

impl Default for PieConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl PieConfig {
    #[must_use]
    pub const fn default_values() -> Self {
        Self {
            text_position_milli: 750,
            legend_position: PieLegendPosition::Right,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PieLegendPosition {
    Top,
    Bottom,
    Left,
    Right,
    Center,
}

impl PieLegendPosition {
    #[must_use]
    pub const fn from_mermaid(value: &str) -> Option<Self> {
        match value.as_bytes() {
            b"top" => Some(Self::Top),
            b"bottom" => Some(Self::Bottom),
            b"left" => Some(Self::Left),
            b"right" => Some(Self::Right),
            b"center" => Some(Self::Center),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PieStatement {
    Title(Label),
    Slice(PieSlice),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PieSlice {
    pub label: Label,
    pub value_units: Spanned<u64>,
    pub value_text: Spanned<String>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QuadrantAst {
    pub header: QuadrantHeader,
    pub title: Option<Label>,
    pub x_axis: Option<QuadrantAxis>,
    pub y_axis: Option<QuadrantAxis>,
    pub quadrants: Vec<QuadrantSection>,
    pub points: Vec<QuadrantPoint>,
    pub classes: Vec<FlowClassDef>,
    pub statements: Vec<QuadrantStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct QuadrantHeader {
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QuadrantAxisKind {
    X,
    Y,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QuadrantAxis {
    pub kind: Spanned<QuadrantAxisKind>,
    pub start: Label,
    pub end: Label,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QuadrantSection {
    pub index: Spanned<u8>,
    pub label: Label,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QuadrantPoint {
    pub label: Label,
    pub x: Spanned<u16>,
    pub y: Spanned<u16>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum QuadrantStatement {
    Title(Label),
    Axis(QuadrantAxis),
    Quadrant(QuadrantSection),
    Point(Box<QuadrantPoint>),
    ClassDef(FlowClassDef),
    ClassApply(FlowClassApply),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZenUmlAst {
    pub header: ZenUmlHeader,
    pub title: Option<Label>,
    pub participants: Vec<ZenUmlParticipant>,
    pub messages: Vec<ZenUmlMessage>,
    pub fragments: Vec<ZenUmlFragment>,
    pub statements: Vec<ZenUmlStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ZenUmlHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZenUmlParticipant {
    pub id: Spanned<String>,
    pub label: Option<Label>,
    pub annotator: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ZenUmlMessageKind {
    Sync,
    Async,
    Create,
    Reply,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZenUmlMessage {
    pub from: Option<Spanned<String>>,
    pub to: Spanned<String>,
    pub label: Option<Label>,
    pub kind: Spanned<ZenUmlMessageKind>,
    pub depth: u16,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ZenUmlFragmentKind {
    Loop,
    Alt,
    Opt,
    Parallel,
    Try,
    Catch,
    Finally,
    Block,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZenUmlFragment {
    pub kind: Spanned<ZenUmlFragmentKind>,
    pub label: Option<Label>,
    pub depth: u16,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ZenUmlStatement {
    Title(Label),
    Participant(ZenUmlParticipant),
    Message(Box<ZenUmlMessage>),
    Fragment(ZenUmlFragment),
    BlockEnd(Span),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SankeyAst {
    pub header: SankeyHeader,
    pub links: Vec<SankeyLink>,
    pub statements: Vec<SankeyStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SankeyHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SankeyLink {
    pub source: Label,
    pub target: Label,
    pub value_units: Spanned<u64>,
    pub value_text: Spanned<String>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SankeyStatement {
    Link(Box<SankeyLink>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XyChartAst {
    pub header: XyChartHeader,
    pub title: Option<Label>,
    pub x_axis: Option<XyChartAxis>,
    pub y_axis: Option<XyChartAxis>,
    pub series: Vec<XyChartSeries>,
    pub statements: Vec<XyChartStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct XyChartHeader {
    pub orientation: Option<Spanned<XyChartOrientation>>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum XyChartOrientation {
    Vertical,
    Horizontal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum XyChartAxisKind {
    X,
    Y,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum XyChartAxisScale {
    Categories(Vec<Label>),
    Range {
        min: Spanned<i64>,
        max: Spanned<i64>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XyChartAxis {
    pub kind: Spanned<XyChartAxisKind>,
    pub title: Option<Label>,
    pub scale: Option<XyChartAxisScale>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum XyChartSeriesKind {
    Bar,
    Line,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XyChartSeries {
    pub kind: Spanned<XyChartSeriesKind>,
    pub values: Vec<Spanned<i64>>,
    pub value_texts: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum XyChartStatement {
    Title(Label),
    Axis(XyChartAxis),
    Series(XyChartSeries),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockDiagramAst {
    pub header: BlockDiagramHeader,
    pub statements: Vec<BlockStatement>,
    pub blocks: Vec<BlockNode>,
    pub edges: Vec<BlockEdge>,
    pub classes: Vec<FlowClassDef>,
    pub styles: Vec<BlockStyle>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BlockDiagramHeader {
    pub columns: Option<Spanned<u16>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BlockStatement {
    Columns(Spanned<u16>),
    Node(Box<BlockNode>),
    Space(BlockSpace),
    Container(Box<BlockContainer>),
    Edge(Box<BlockEdge>),
    ClassDef(FlowClassDef),
    ClassApply(FlowClassApply),
    Style(BlockStyle),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockNode {
    pub id: Spanned<String>,
    pub label: Option<Label>,
    pub shape: Spanned<BlockShape>,
    pub width: Spanned<u16>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BlockShape {
    Flow(FlowShape),
    Arrow(Vec<Spanned<BlockArrowDirection>>),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlockArrowDirection {
    Left,
    Right,
    Up,
    Down,
    X,
    Y,
}

impl BlockArrowDirection {
    #[must_use]
    pub const fn from_mermaid(value: &str) -> Option<Self> {
        match value.as_bytes() {
            b"left" => Some(Self::Left),
            b"right" => Some(Self::Right),
            b"up" => Some(Self::Up),
            b"down" => Some(Self::Down),
            b"x" => Some(Self::X),
            b"y" => Some(Self::Y),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BlockSpace {
    pub width: Spanned<u16>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockContainer {
    pub id: Option<Spanned<String>>,
    pub width: Spanned<u16>,
    pub columns: Option<Spanned<u16>>,
    pub statements: Vec<BlockStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockEdge {
    pub from: Spanned<String>,
    pub to: Spanned<String>,
    pub from_node: BlockNode,
    pub to_node: BlockNode,
    pub link: Spanned<FlowEdgeLink>,
    pub label: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockStyle {
    pub target: Spanned<String>,
    pub styles: Vec<FlowStyleDeclaration>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PacketAst {
    pub header: PacketHeader,
    pub title: Option<Label>,
    pub fields: Vec<PacketField>,
    pub statements: Vec<PacketStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PacketHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PacketStatement {
    Title(Label),
    Field(Box<PacketField>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PacketField {
    pub range: PacketRange,
    pub label: Label,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PacketRange {
    pub start: Spanned<u32>,
    pub end: Spanned<u32>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KanbanAst {
    pub header: KanbanHeader,
    pub columns: Vec<KanbanColumn>,
    pub statements: Vec<KanbanStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KanbanHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KanbanStatement {
    Column(Box<KanbanColumn>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KanbanColumn {
    pub id: Option<Spanned<String>>,
    pub title: Label,
    pub tasks: Vec<KanbanTask>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KanbanTask {
    pub id: Option<Spanned<String>>,
    pub label: Label,
    pub metadata: Vec<KanbanMetadata>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KanbanMetadata {
    pub key: Spanned<String>,
    pub value: Label,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArchitectureAst {
    pub header: ArchitectureHeader,
    pub groups: Vec<ArchitectureGroup>,
    pub services: Vec<ArchitectureService>,
    pub junctions: Vec<ArchitectureJunction>,
    pub edges: Vec<ArchitectureEdge>,
    pub alignments: Vec<ArchitectureAlignment>,
    pub statements: Vec<ArchitectureStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ArchitectureHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ArchitectureStatement {
    Group(Box<ArchitectureGroup>),
    Service(Box<ArchitectureService>),
    Junction(Box<ArchitectureJunction>),
    Edge(Box<ArchitectureEdge>),
    Alignment(Box<ArchitectureAlignment>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArchitectureGroup {
    pub id: Spanned<String>,
    pub icon: Option<Label>,
    pub title: Option<Label>,
    pub parent: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArchitectureService {
    pub id: Spanned<String>,
    pub icon: Option<Label>,
    pub title: Option<Label>,
    pub parent: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArchitectureJunction {
    pub id: Spanned<String>,
    pub parent: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArchitectureEdge {
    pub from: ArchitectureEndpoint,
    pub to: ArchitectureEndpoint,
    pub arrow_start: bool,
    pub arrow_end: bool,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArchitectureEndpoint {
    pub id: Spanned<String>,
    pub side: Spanned<ArchitectureSide>,
    pub group: bool,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArchitectureSide {
    Top,
    Bottom,
    Left,
    Right,
}

impl ArchitectureSide {
    #[must_use]
    pub const fn from_mermaid(value: &str) -> Option<Self> {
        match value.as_bytes() {
            b"T" => Some(Self::Top),
            b"B" => Some(Self::Bottom),
            b"L" => Some(Self::Left),
            b"R" => Some(Self::Right),
            _ => None,
        }
    }

    #[must_use]
    pub const fn as_mermaid(self) -> &'static str {
        match self {
            Self::Top => "T",
            Self::Bottom => "B",
            Self::Left => "L",
            Self::Right => "R",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArchitectureAlignment {
    pub axis: Spanned<ArchitectureAlignAxis>,
    pub members: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArchitectureAlignAxis {
    Row,
    Column,
}

impl ArchitectureAlignAxis {
    #[must_use]
    pub const fn from_mermaid(value: &str) -> Option<Self> {
        match value.as_bytes() {
            b"row" => Some(Self::Row),
            b"column" => Some(Self::Column),
            _ => None,
        }
    }

    #[must_use]
    pub const fn as_mermaid(self) -> &'static str {
        match self {
            Self::Row => "row",
            Self::Column => "column",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RadarAst {
    pub header: RadarHeader,
    pub title: Option<Label>,
    pub axes: Vec<RadarAxis>,
    pub curves: Vec<RadarCurve>,
    pub options: Vec<RadarOption>,
    pub statements: Vec<RadarStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RadarHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RadarStatement {
    Title(Label),
    Axis(Box<RadarAxis>),
    Curve(Box<RadarCurve>),
    Option(Box<RadarOption>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RadarAxis {
    pub id: Spanned<String>,
    pub label: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RadarCurve {
    pub id: Spanned<String>,
    pub label: Option<Label>,
    pub values: Vec<RadarCurveValue>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RadarCurveValue {
    pub axis: Option<Spanned<String>>,
    pub value: Spanned<String>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RadarOption {
    pub kind: Spanned<RadarOptionKind>,
    pub value: Spanned<String>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RadarOptionKind {
    ShowLegend,
    Max,
    Min,
    Graticule,
    Ticks,
}

impl RadarOptionKind {
    #[must_use]
    pub const fn from_mermaid(value: &str) -> Option<Self> {
        match value.as_bytes() {
            b"showLegend" => Some(Self::ShowLegend),
            b"max" => Some(Self::Max),
            b"min" => Some(Self::Min),
            b"graticule" => Some(Self::Graticule),
            b"ticks" => Some(Self::Ticks),
            _ => None,
        }
    }

    #[must_use]
    pub const fn as_mermaid(self) -> &'static str {
        match self {
            Self::ShowLegend => "showLegend",
            Self::Max => "max",
            Self::Min => "min",
            Self::Graticule => "graticule",
            Self::Ticks => "ticks",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventModelingAst {
    pub header: EventModelingHeader,
    pub timeframes: Vec<EventModelingTimeFrame>,
    pub data_blocks: Vec<EventModelingDataBlock>,
    pub statements: Vec<EventModelingStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EventModelingHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EventModelingStatement {
    TimeFrame(Box<EventModelingTimeFrame>),
    DataBlock(Box<EventModelingDataBlock>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventModelingTimeFrame {
    pub kind: Spanned<EventModelingFrameKind>,
    pub number: Spanned<String>,
    pub entity_type: Spanned<EventModelingEntityType>,
    pub entity: Spanned<String>,
    pub data_ref: Option<Spanned<String>>,
    pub data: Option<EventModelingData>,
    pub relations: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventModelingFrameKind {
    TimeFrame,
    ResetFrame,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventModelingEntityType {
    Ui,
    Processor,
    Command,
    ReadModel,
    Event,
}

impl EventModelingEntityType {
    #[must_use]
    pub const fn from_mermaid(value: &str) -> Option<Self> {
        match value.as_bytes() {
            b"ui" => Some(Self::Ui),
            b"pcr" | b"processor" => Some(Self::Processor),
            b"cmd" | b"command" => Some(Self::Command),
            b"rmo" | b"readmodel" => Some(Self::ReadModel),
            b"evt" | b"event" => Some(Self::Event),
            _ => None,
        }
    }

    #[must_use]
    pub const fn as_mermaid(self) -> &'static str {
        match self {
            Self::Ui => "ui",
            Self::Processor => "processor",
            Self::Command => "command",
            Self::ReadModel => "readmodel",
            Self::Event => "event",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventModelingDataBlock {
    pub id: Spanned<String>,
    pub data: EventModelingData,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventModelingData {
    pub ty: Option<Spanned<String>>,
    pub body: Label,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreemapAst {
    pub header: TreemapHeader,
    pub statements: Vec<TreemapStatement>,
    pub roots: Vec<TreemapNode>,
    pub classes: Vec<FlowClassDef>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TreemapHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TreemapStatement {
    Node(Box<TreemapNode>),
    ClassDef(FlowClassDef),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreemapNode {
    pub label: Label,
    pub value: Option<Spanned<String>>,
    pub classes: Vec<Spanned<String>>,
    pub children: Vec<TreemapNode>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VennAst {
    pub header: VennHeader,
    pub title: Option<Label>,
    pub sets: Vec<VennSet>,
    pub unions: Vec<VennUnion>,
    pub texts: Vec<VennText>,
    pub styles: Vec<VennStyle>,
    pub statements: Vec<VennStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VennHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VennStatement {
    Title(Label),
    Set(Box<VennSet>),
    Union(Box<VennUnion>),
    Text(Box<VennText>),
    Style(VennStyle),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VennSet {
    pub id: Spanned<String>,
    pub label: Option<Label>,
    pub size: Option<Spanned<String>>,
    pub texts: Vec<VennText>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VennUnion {
    pub members: Vec<Spanned<String>>,
    pub label: Option<Label>,
    pub size: Option<Spanned<String>>,
    pub texts: Vec<VennText>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VennText {
    pub id: Spanned<String>,
    pub label: Option<Label>,
    pub owner: Option<VennTextOwner>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VennTextOwner {
    Set(String),
    Union(Vec<String>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VennStyle {
    pub targets: Vec<Spanned<String>>,
    pub declarations: Vec<FlowStyleDeclaration>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IshikawaAst {
    pub header: IshikawaHeader,
    pub event: Label,
    pub causes: Vec<IshikawaNode>,
    pub statements: Vec<IshikawaStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct IshikawaHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IshikawaStatement {
    Event(Label),
    Cause(Box<IshikawaNode>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IshikawaNode {
    pub label: Label,
    pub causes: Vec<IshikawaNode>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyAst {
    pub header: WardleyHeader,
    pub title: Option<Label>,
    pub size: Option<WardleySize>,
    pub components: Vec<WardleyComponent>,
    pub links: Vec<WardleyLink>,
    pub evolves: Vec<WardleyEvolve>,
    pub notes: Vec<WardleyNote>,
    pub annotations_position: Option<WardleyCoord>,
    pub annotations: Vec<WardleyAnnotation>,
    pub forces: Vec<WardleyForce>,
    pub evolution: Option<WardleyEvolution>,
    pub statements: Vec<WardleyStatement>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WardleyHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WardleyStatement {
    Title(Label),
    Size(WardleySize),
    Component(Box<WardleyComponent>),
    Link(WardleyLink),
    Evolve(WardleyEvolve),
    Note(WardleyNote),
    Annotations(WardleyCoord),
    Annotation(WardleyAnnotation),
    Force(WardleyForce),
    Evolution(WardleyEvolution),
    Pipeline(Label),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WardleySize {
    pub width: u32,
    pub height: u32,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyComponent {
    pub kind: WardleyComponentKind,
    pub name: Label,
    pub coord: WardleyCoord,
    pub label_offset: Option<WardleyLabelOffset>,
    pub decorators: Vec<WardleyDecorator>,
    pub pipeline: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WardleyComponentKind {
    Component,
    Anchor,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyCoord {
    pub visibility: Spanned<String>,
    pub evolution: Spanned<String>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WardleyLabelOffset {
    pub x: i32,
    pub y: i32,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WardleyDecorator {
    Inertia,
    Build,
    Buy,
    Outsource,
    Market,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyLink {
    pub from: Label,
    pub to: Label,
    pub kind: WardleyLinkKind,
    pub label: Option<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WardleyLinkKind {
    Dependency,
    Dashed,
    Flow,
    ReverseFlow,
    BidirectionalFlow,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyEvolve {
    pub name: Label,
    pub target_evolution: Spanned<String>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyNote {
    pub text: Label,
    pub coord: WardleyCoord,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyAnnotation {
    pub number: Spanned<String>,
    pub coord: WardleyCoord,
    pub text: Label,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyForce {
    pub kind: WardleyForceKind,
    pub text: Label,
    pub coord: WardleyCoord,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WardleyForceKind {
    Accelerator,
    Deaccelerator,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyEvolution {
    pub stages: Vec<WardleyEvolutionStage>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WardleyEvolutionStage {
    pub label: Label,
    pub boundary: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MindmapAst {
    pub header: MindmapHeader,
    pub statements: Vec<MindmapStatement>,
    pub roots: Vec<MindmapNode>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MindmapHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MindmapStatement {
    Node(Box<MindmapNode>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MindmapNode {
    pub label: Label,
    pub shape: MindmapShape,
    pub icon: Option<Spanned<String>>,
    pub classes: Vec<Spanned<String>>,
    pub children: Vec<MindmapNode>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MindmapShape {
    Default,
    Square,
    Rounded,
    Circle,
    Bang,
    Cloud,
    Hexagon,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JourneyAst {
    pub header: JourneyHeader,
    pub title: Option<Label>,
    pub statements: Vec<JourneyStatement>,
    pub tasks: Vec<JourneyTask>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct JourneyHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JourneyStatement {
    Title(Label),
    Section(Label),
    Task(Box<JourneyTask>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JourneyTask {
    pub label: Label,
    pub section: Option<Label>,
    pub score: Spanned<u8>,
    pub actors: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitGraphAst {
    pub header: GitGraphHeader,
    pub statements: Vec<GitGraphStatement>,
    pub commits: Vec<GitGraphCommit>,
    pub branches: Vec<GitGraphBranch>,
    pub merges: Vec<GitGraphMerge>,
    pub cherry_picks: Vec<GitGraphCherryPick>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GitGraphHeader {
    pub orientation: Spanned<GitGraphOrientation>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitGraphOrientation {
    LeftRight,
    TopBottom,
    BottomTop,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GitGraphStatement {
    Commit(Box<GitGraphCommit>),
    Branch(Box<GitGraphBranch>),
    Checkout(Spanned<String>),
    Merge(Box<GitGraphMerge>),
    CherryPick(Box<GitGraphCherryPick>),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitGraphCommitKind {
    Normal,
    Reverse,
    Highlight,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitGraphCommit {
    pub id: Option<Spanned<String>>,
    pub tag: Option<Spanned<String>>,
    pub kind: Spanned<GitGraphCommitKind>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitGraphBranch {
    pub name: Spanned<String>,
    pub order: Option<Spanned<i32>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitGraphMerge {
    pub branch: Spanned<String>,
    pub id: Option<Spanned<String>>,
    pub tag: Option<Spanned<String>>,
    pub kind: Spanned<GitGraphCommitKind>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitGraphCherryPick {
    pub id: Spanned<String>,
    pub parent: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimelineAst {
    pub header: TimelineHeader,
    pub title: Option<Label>,
    pub statements: Vec<TimelineStatement>,
    pub periods: Vec<TimelinePeriod>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TimelineHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TimelineStatement {
    Title(Label),
    Section(Label),
    Period(Box<TimelinePeriod>),
    Event(Label),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimelinePeriod {
    pub label: Label,
    pub section: Option<Label>,
    pub events: Vec<Label>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequirementAst {
    pub header: RequirementHeader,
    pub direction: Option<Spanned<Direction>>,
    pub statements: Vec<RequirementStatement>,
    pub requirements: Vec<RequirementNode>,
    pub elements: Vec<RequirementElement>,
    pub relationships: Vec<RequirementRelationship>,
    pub classes: Vec<FlowClassDef>,
    pub styles: Vec<RequirementStyle>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RequirementHeader {
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RequirementStatement {
    Requirement(Box<RequirementNode>),
    Element(Box<RequirementElement>),
    Relationship(Box<RequirementRelationship>),
    Direction(Spanned<Direction>),
    Style(RequirementStyle),
    ClassDef(FlowClassDef),
    ClassApply(FlowClassApply),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequirementKind {
    Requirement,
    Functional,
    Interface,
    Performance,
    Physical,
    DesignConstraint,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequirementRisk {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequirementVerifyMethod {
    Analysis,
    Inspection,
    Test,
    Demonstration,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequirementNode {
    pub name: Spanned<String>,
    pub kind: Spanned<RequirementKind>,
    pub requirement_id: Option<Label>,
    pub text: Option<Label>,
    pub risk: Option<Spanned<RequirementRisk>>,
    pub verify_method: Option<Spanned<RequirementVerifyMethod>>,
    pub classes: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequirementElement {
    pub name: Spanned<String>,
    pub ty: Option<Label>,
    pub doc_ref: Option<Label>,
    pub classes: Vec<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequirementRelationshipKind {
    Contains,
    Copies,
    Derives,
    Satisfies,
    Verifies,
    Refines,
    Traces,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequirementRelationship {
    pub from: Spanned<String>,
    pub to: Spanned<String>,
    pub kind: Spanned<RequirementRelationshipKind>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequirementStyle {
    pub node_ids: Vec<Spanned<String>>,
    pub styles: Vec<FlowStyleDeclaration>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct C4Ast {
    pub header: C4Header,
    pub title: Option<Label>,
    pub statements: Vec<C4Statement>,
    pub elements: Vec<C4Element>,
    pub relationships: Vec<C4Relationship>,
    pub boundaries: Vec<C4Boundary>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct C4Header {
    pub diagram_type: Spanned<C4DiagramType>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum C4DiagramType {
    Context,
    Container,
    Component,
    Dynamic,
    Deployment,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum C4Statement {
    Title(Label),
    Element(Box<C4Element>),
    Relationship(Box<C4Relationship>),
    Boundary(Box<C4Boundary>),
    Style(C4StyleUpdate),
    Layout(C4LayoutConfig),
    Comment(MermaidComment),
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum C4ElementKind {
    Person,
    PersonExternal,
    System,
    SystemExternal,
    SystemDb,
    SystemDbExternal,
    SystemQueue,
    SystemQueueExternal,
    Container,
    ContainerExternal,
    ContainerDb,
    ContainerDbExternal,
    ContainerQueue,
    ContainerQueueExternal,
    Component,
    ComponentExternal,
    ComponentDb,
    ComponentDbExternal,
    ComponentQueue,
    ComponentQueueExternal,
    DeploymentNode,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct C4Element {
    pub alias: Spanned<String>,
    pub label: Label,
    pub kind: Spanned<C4ElementKind>,
    pub technology: Option<Label>,
    pub description: Option<Label>,
    pub parent: Option<Spanned<String>>,
    pub external: bool,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum C4BoundaryKind {
    Boundary,
    Enterprise,
    System,
    Container,
    DeploymentNode,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct C4Boundary {
    pub alias: Spanned<String>,
    pub label: Label,
    pub kind: Spanned<C4BoundaryKind>,
    pub ty: Option<Label>,
    pub parent: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum C4RelationshipKind {
    Directed,
    Bidirectional,
    Up,
    Down,
    Left,
    Right,
    Back,
    Indexed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct C4Relationship {
    pub from: Spanned<String>,
    pub to: Spanned<String>,
    pub label: Label,
    pub technology: Option<Label>,
    pub kind: Spanned<C4RelationshipKind>,
    pub index: Option<Spanned<String>>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct C4StyleUpdate {
    pub target_ids: Vec<Spanned<String>>,
    pub fields: Vec<C4CallArg>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct C4LayoutConfig {
    pub name: Spanned<String>,
    pub fields: Vec<C4CallArg>,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct C4CallArg {
    pub name: Option<Spanned<String>>,
    pub value: Label,
    pub span: Span,
}

#[cfg(test)]
mod tests {
    use super::{
        ClassAst, ClassHeader, Diagram, DiagramKind, DiagramMetadata, Direction, FlowchartAst,
        FlowchartDirective, FlowchartHeader, Span, Spanned,
    };

    #[test]
    fn builds_flowchart_diagram_root() {
        let header = FlowchartHeader {
            directive: Spanned::new(FlowchartDirective::Graph, Span::new(0, 5)),
            direction: Spanned::new(Direction::LeftRight, Span::new(6, 8)),
            span: Span::new(0, 8),
        };
        let flowchart = FlowchartAst {
            header,
            statements: Vec::new(),
            nodes: Vec::new(),
            edges: Vec::new(),
            subgraphs: Vec::new(),
            classes: Vec::new(),
            span: Span::new(0, 8),
        };
        let diagram = Diagram {
            metadata: DiagramMetadata {
                title: None,
                accessibility_title: None,
                accessibility_description: None,
                span: Span::new(0, 0),
            },
            directives: Vec::new(),
            kind: DiagramKind::Flowchart(Box::new(flowchart)),
            span: Span::new(0, 8),
        };

        assert!(matches!(diagram.kind, DiagramKind::Flowchart(_)));
    }

    #[test]
    fn builds_class_diagram_root() {
        let class = ClassAst {
            header: ClassHeader {
                span: Span::new(0, 12),
            },
            direction: None,
            statements: Vec::new(),
            classes: Vec::new(),
            relationships: Vec::new(),
            span: Span::new(0, 12),
        };
        let diagram = Diagram {
            metadata: DiagramMetadata {
                title: None,
                accessibility_title: None,
                accessibility_description: None,
                span: Span::new(0, 0),
            },
            directives: Vec::new(),
            kind: DiagramKind::Class(Box::new(class)),
            span: Span::new(0, 12),
        };

        assert!(matches!(diagram.kind, DiagramKind::Class(_)));
    }
}
