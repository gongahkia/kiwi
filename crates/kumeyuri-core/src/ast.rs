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
    Mindmap(Box<MindmapAst>),
    Journey(Box<JourneyAst>),
    GitGraph(Box<GitGraphAst>),
    Timeline(Box<TimelineAst>),
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
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SequenceAutoNumber {
    pub start: Option<u64>,
    pub step: Option<u64>,
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
