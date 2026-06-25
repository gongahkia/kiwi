//! Parsed Mermaid AST data model.
#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for diagram.
pub struct Diagram {
    /// metadata.
    pub metadata: DiagramMetadata,
    /// directives.
    pub directives: Vec<MermaidDirective>,
    /// kind.
    pub kind: DiagramKind,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for diagram kind.
pub enum DiagramKind {
    /// flowchart.
    Flowchart(Box<FlowchartAst>),
    /// sequence.
    Sequence(Box<SequenceAst>),
    /// state.
    State(Box<StateAst>),
    /// class.
    Class(Box<ClassAst>),
    /// er.
    Er(Box<ErAst>),
    /// gantt.
    Gantt(Box<GanttAst>),
    /// pie.
    Pie(Box<PieAst>),
    /// quadrant.
    Quadrant(Box<QuadrantAst>),
    /// zenuml.
    ZenUml(Box<ZenUmlAst>),
    /// sankey.
    Sankey(Box<SankeyAst>),
    /// xy chart.
    XyChart(Box<XyChartAst>),
    /// block.
    Block(Box<BlockDiagramAst>),
    /// packet.
    Packet(Box<PacketAst>),
    /// kanban.
    Kanban(Box<KanbanAst>),
    /// architecture.
    Architecture(Box<ArchitectureAst>),
    /// radar.
    Radar(Box<RadarAst>),
    /// event modeling.
    EventModeling(Box<EventModelingAst>),
    /// treemap.
    Treemap(Box<TreemapAst>),
    /// venn.
    Venn(Box<VennAst>),
    /// ishikawa.
    Ishikawa(Box<IshikawaAst>),
    /// wardley.
    Wardley(Box<WardleyAst>),
    /// tree view.
    TreeView(Box<TreeViewAst>),
    /// mindmap.
    Mindmap(Box<MindmapAst>),
    /// journey.
    Journey(Box<JourneyAst>),
    /// git graph.
    GitGraph(Box<GitGraphAst>),
    /// timeline.
    Timeline(Box<TimelineAst>),
    /// requirement.
    Requirement(Box<RequirementAst>),
    /// c4.
    C4(Box<C4Ast>),
    /// cynefin framework.
    Cynefin(Box<CynefinAst>),
    /// railroad diagram.
    Railroad(Box<RailroadAst>),
    /// swimlanes diagram.
    Swimlanes(Box<SwimlanesAst>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for diagram metadata.
pub struct DiagramMetadata {
    /// title.
    pub title: Option<Label>,
    /// accessibility_title.
    pub accessibility_title: Option<Label>,
    /// accessibility_description.
    pub accessibility_description: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for span.
pub struct Span {
    /// start.
    pub start: usize,
    /// end.
    pub end: usize,
}

impl Span {
    #[must_use]
    /// Create a new value.
    pub const fn new(start: usize, end: usize) -> Self {
        Self { start, end }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for spanned.
pub struct Spanned<T> {
    /// value.
    pub value: T,
    /// span.
    pub span: Span,
}

impl<T> Spanned<T> {
    #[must_use]
    /// Create a new value.
    pub const fn new(value: T, span: Span) -> Self {
        Self { value, span }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for flowchart directive.
pub enum FlowchartDirective {
    /// flowchart.
    Flowchart,
    /// graph.
    Graph,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for direction.
pub enum Direction {
    /// top down.
    TopDown,
    /// bottom top.
    BottomTop,
    /// left right.
    LeftRight,
    /// right left.
    RightLeft,
}

impl Direction {
    #[must_use]
    /// Parse a Mermaid direction token.
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
/// Parsed data for flowchart header.
pub struct FlowchartHeader {
    /// directive.
    pub directive: Spanned<FlowchartDirective>,
    /// direction.
    pub direction: Spanned<Direction>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for label kind.
pub enum LabelKind {
    /// plain.
    Plain,
    /// string.
    String,
    /// markdown.
    Markdown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for label.
pub struct Label {
    /// text.
    pub text: String,
    /// kind.
    pub kind: LabelKind,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for flow shape.
pub enum FlowShape {
    /// rectangle.
    Rectangle,
    /// round.
    Round,
    /// stadium.
    Stadium,
    /// subroutine.
    Subroutine,
    /// cylinder.
    Cylinder,
    /// circle.
    Circle,
    /// asymmetric.
    Asymmetric,
    /// rhombus.
    Rhombus,
    /// hexagon.
    Hexagon,
    /// parallelogram.
    Parallelogram,
    /// parallelogram alt.
    ParallelogramAlt,
    /// trapezoid.
    Trapezoid,
    /// trapezoid alt.
    TrapezoidAlt,
    /// double circle.
    DoubleCircle,
    /// named.
    Named(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for flow node.
pub struct FlowNode {
    /// id.
    pub id: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// shape.
    pub shape: Spanned<FlowShape>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for flow edge stroke.
pub enum FlowEdgeStroke {
    /// normal.
    Normal,
    /// thick.
    Thick,
    /// dotted.
    Dotted,
    /// invisible.
    Invisible,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for arrow head.
pub enum ArrowHead {
    /// none.
    None,
    /// arrow.
    Arrow,
    /// circle.
    Circle,
    /// cross.
    Cross,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for flow edge link.
pub struct FlowEdgeLink {
    /// stroke.
    pub stroke: FlowEdgeStroke,
    /// arrow_start.
    pub arrow_start: ArrowHead,
    /// arrow_end.
    pub arrow_end: ArrowHead,
    /// min_length.
    pub min_length: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for flow edge.
pub struct FlowEdge {
    /// from.
    pub from: FlowNode,
    /// to.
    pub to: FlowNode,
    /// link.
    pub link: Spanned<FlowEdgeLink>,
    /// label.
    pub label: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for flow statement.
pub enum FlowStatement {
    /// node.
    Node(FlowNode),
    /// edge.
    Edge(Box<FlowEdge>),
    /// subgraph.
    Subgraph(FlowSubgraph),
    /// class def.
    ClassDef(FlowClassDef),
    /// class apply.
    ClassApply(FlowClassApply),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for flow subgraph.
pub struct FlowSubgraph {
    /// id.
    pub id: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// direction.
    pub direction: Option<Spanned<Direction>>,
    /// statements.
    pub statements: Vec<FlowStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for flow style declaration.
pub struct FlowStyleDeclaration {
    /// key.
    pub key: Spanned<String>,
    /// value.
    pub value: Spanned<String>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for flow class def.
pub struct FlowClassDef {
    /// class_ids.
    pub class_ids: Vec<Spanned<String>>,
    /// styles.
    pub styles: Vec<FlowStyleDeclaration>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for flow class apply.
pub struct FlowClassApply {
    /// node_ids.
    pub node_ids: Vec<Spanned<String>>,
    /// class_ids.
    pub class_ids: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for mermaid comment.
pub struct MermaidComment {
    /// text.
    pub text: String,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for mermaid directive.
pub struct MermaidDirective {
    /// raw.
    pub raw: String,
    /// key.
    pub key: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for flowchart ast.
pub struct FlowchartAst {
    /// header.
    pub header: FlowchartHeader,
    /// statements.
    pub statements: Vec<FlowStatement>,
    /// nodes.
    pub nodes: Vec<FlowNode>,
    /// edges.
    pub edges: Vec<FlowEdge>,
    /// subgraphs.
    pub subgraphs: Vec<FlowSubgraph>,
    /// classes.
    pub classes: Vec<FlowClassDef>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sequence ast.
pub struct SequenceAst {
    /// header.
    pub header: SequenceHeader,
    /// statements.
    pub statements: Vec<SequenceStatement>,
    /// participants.
    pub participants: Vec<SequenceParticipant>,
    /// boxes.
    pub boxes: Vec<SequenceBox>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for sequence header.
pub struct SequenceHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for sequence statement.
pub enum SequenceStatement {
    /// participant.
    Participant(Box<SequenceParticipant>),
    /// create.
    Create(Box<SequenceCreate>),
    /// destroy.
    Destroy(Box<SequenceDestroy>),
    /// box.
    Box(Box<SequenceBox>),
    /// message.
    Message(Box<SequenceMessage>),
    /// activation start.
    ActivationStart(Spanned<String>),
    /// activation end.
    ActivationEnd(Spanned<String>),
    /// note.
    Note(Box<SequenceNote>),
    /// control.
    Control(Box<SequenceControlBlock>),
    /// auto number.
    AutoNumber(SequenceAutoNumber),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sequence participant.
pub struct SequenceParticipant {
    /// id.
    pub id: Spanned<String>,
    /// alias.
    pub alias: Option<Label>,
    /// kind.
    pub kind: SequenceParticipantKind,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for sequence participant kind.
pub enum SequenceParticipantKind {
    /// participant.
    Participant,
    /// actor.
    Actor,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sequence create.
pub struct SequenceCreate {
    /// participant.
    pub participant: SequenceParticipant,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sequence destroy.
pub struct SequenceDestroy {
    /// participant.
    pub participant: Spanned<String>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sequence box.
pub struct SequenceBox {
    /// label.
    pub label: Option<Label>,
    /// participants.
    pub participants: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sequence message.
pub struct SequenceMessage {
    /// from.
    pub from: Spanned<String>,
    /// to.
    pub to: Spanned<String>,
    /// arrow.
    pub arrow: SequenceArrow,
    /// activation.
    pub activation: Option<Spanned<SequenceActivation>>,
    /// label.
    pub label: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for sequence arrow.
pub enum SequenceArrow {
    /// solid line.
    SolidLine,
    /// dotted line.
    DottedLine,
    /// solid arrow.
    SolidArrow,
    /// dotted arrow.
    DottedArrow,
    /// solid cross.
    SolidCross,
    /// dotted cross.
    DottedCross,
    /// solid open.
    SolidOpen,
    /// dotted open.
    DottedOpen,
    /// solid bidirectional.
    SolidBidirectional,
    /// dotted bidirectional.
    DottedBidirectional,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for sequence activation.
pub enum SequenceActivation {
    /// start.
    Start,
    /// end.
    End,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sequence note.
pub struct SequenceNote {
    /// placement.
    pub placement: SequenceNotePlacement,
    /// participants.
    pub participants: Vec<Spanned<String>>,
    /// label.
    pub label: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for sequence note placement.
pub enum SequenceNotePlacement {
    /// left of.
    LeftOf,
    /// right of.
    RightOf,
    /// over.
    Over,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sequence control block.
pub struct SequenceControlBlock {
    /// kind.
    pub kind: SequenceControlKind,
    /// label.
    pub label: Option<Label>,
    /// statements.
    pub statements: Vec<SequenceStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for sequence control kind.
pub enum SequenceControlKind {
    /// loop.
    Loop,
    /// alt.
    Alt,
    /// opt.
    Opt,
    /// par.
    Par,
    /// critical.
    Critical,
    /// break.
    Break,
    /// rect.
    Rect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sequence auto number.
pub struct SequenceAutoNumber {
    /// start.
    pub start: Option<Spanned<String>>,
    /// step.
    pub step: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for state ast.
pub struct StateAst {
    /// header.
    pub header: StateHeader,
    /// direction.
    pub direction: Option<Spanned<Direction>>,
    /// statements.
    pub statements: Vec<StateStatement>,
    /// states.
    pub states: Vec<StateNode>,
    /// transitions.
    pub transitions: Vec<StateTransition>,
    /// classes.
    pub classes: Vec<FlowClassDef>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for state header.
pub struct StateHeader {
    /// directive.
    pub directive: StateDirective,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for state directive.
pub enum StateDirective {
    /// state diagram.
    StateDiagram,
    /// state diagram v2.
    StateDiagramV2,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for state statement.
pub enum StateStatement {
    /// state.
    State(Box<StateNode>),
    /// transition.
    Transition(Box<StateTransition>),
    /// composite.
    Composite(Box<StateNode>),
    /// class def.
    ClassDef(FlowClassDef),
    /// class apply.
    ClassApply(StateClassApply),
    /// direction.
    Direction(Spanned<Direction>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for state node.
pub struct StateNode {
    /// id.
    pub id: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// kind.
    pub kind: StateNodeKind,
    /// descriptions.
    pub descriptions: Vec<Label>,
    /// note.
    pub note: Option<StateNote>,
    /// children.
    pub children: Vec<StateStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for state node kind.
pub enum StateNodeKind {
    /// default.
    Default,
    /// start.
    Start,
    /// end.
    End,
    /// fork.
    Fork,
    /// join.
    Join,
    /// choice.
    Choice,
    /// divider.
    Divider,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for state transition.
pub struct StateTransition {
    /// from.
    pub from: Spanned<String>,
    /// to.
    pub to: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for state note.
pub struct StateNote {
    /// placement.
    pub placement: StateNotePlacement,
    /// label.
    pub label: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for state note placement.
pub enum StateNotePlacement {
    /// left of.
    LeftOf,
    /// right of.
    RightOf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for state class apply.
pub struct StateClassApply {
    /// state_ids.
    pub state_ids: Vec<Spanned<String>>,
    /// class_ids.
    pub class_ids: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for class ast.
pub struct ClassAst {
    /// header.
    pub header: ClassHeader,
    /// direction.
    pub direction: Option<Spanned<Direction>>,
    /// statements.
    pub statements: Vec<ClassStatement>,
    /// classes.
    pub classes: Vec<ClassNode>,
    /// relationships.
    pub relationships: Vec<ClassRelationship>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for class header.
pub struct ClassHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for class statement.
pub enum ClassStatement {
    /// class.
    Class(Box<ClassNode>),
    /// member.
    Member(Box<ClassMemberAssignment>),
    /// relationship.
    Relationship(Box<ClassRelationship>),
    /// direction.
    Direction(Spanned<Direction>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for class node.
pub struct ClassNode {
    /// id.
    pub id: Spanned<String>,
    /// annotations.
    pub annotations: Vec<Label>,
    /// members.
    pub members: Vec<ClassMember>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for class member assignment.
pub struct ClassMemberAssignment {
    /// class_id.
    pub class_id: Spanned<String>,
    /// member.
    pub member: ClassMember,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for class member.
pub struct ClassMember {
    /// visibility.
    pub visibility: Option<char>,
    /// name.
    pub name: Spanned<String>,
    /// ty.
    pub ty: Option<Label>,
    /// kind.
    pub kind: ClassMemberKind,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for class member kind.
pub enum ClassMemberKind {
    /// field.
    Field,
    /// method.
    Method,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for class relationship.
pub struct ClassRelationship {
    /// from.
    pub from: Spanned<String>,
    /// to.
    pub to: Spanned<String>,
    /// line.
    pub line: ClassRelationshipLine,
    /// start_marker.
    pub start_marker: ClassRelationshipMarker,
    /// end_marker.
    pub end_marker: ClassRelationshipMarker,
    /// start_cardinality.
    pub start_cardinality: Option<Label>,
    /// end_cardinality.
    pub end_cardinality: Option<Label>,
    /// label.
    pub label: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for class relationship line.
pub enum ClassRelationshipLine {
    /// solid.
    Solid,
    /// dotted.
    Dotted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for class relationship marker.
pub enum ClassRelationshipMarker {
    /// none.
    None,
    /// arrow.
    Arrow,
    /// inheritance.
    Inheritance,
    /// aggregation.
    Aggregation,
    /// composition.
    Composition,
    /// one.
    One,
    /// zero or one.
    ZeroOrOne,
    /// many.
    Many,
    /// zero or many.
    ZeroOrMany,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for er ast.
pub struct ErAst {
    /// header.
    pub header: ErHeader,
    /// statements.
    pub statements: Vec<ErStatement>,
    /// entities.
    pub entities: Vec<ErEntity>,
    /// relationships.
    pub relationships: Vec<ErRelationship>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for er header.
pub struct ErHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for er statement.
pub enum ErStatement {
    /// entity.
    Entity(Box<ErEntity>),
    /// relationship.
    Relationship(Box<ErRelationship>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for er entity.
pub struct ErEntity {
    /// id.
    pub id: Spanned<String>,
    /// attributes.
    pub attributes: Vec<ErAttribute>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for er attribute.
pub struct ErAttribute {
    /// ty.
    pub ty: Spanned<String>,
    /// name.
    pub name: Spanned<String>,
    /// key.
    pub key: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for er relationship.
pub struct ErRelationship {
    /// from.
    pub from: Spanned<String>,
    /// to.
    pub to: Spanned<String>,
    /// start_cardinality.
    pub start_cardinality: ErCardinality,
    /// end_cardinality.
    pub end_cardinality: ErCardinality,
    /// identifying.
    pub identifying: bool,
    /// label.
    pub label: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for er cardinality.
pub enum ErCardinality {
    /// one.
    One,
    /// zero or one.
    ZeroOrOne,
    /// one or many.
    OneOrMany,
    /// zero or many.
    ZeroOrMany,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for gantt ast.
pub struct GanttAst {
    /// header.
    pub header: GanttHeader,
    /// title.
    pub title: Option<Label>,
    /// date_format.
    pub date_format: Option<Spanned<String>>,
    /// axis_format.
    pub axis_format: Option<Spanned<String>>,
    /// statements.
    pub statements: Vec<GanttStatement>,
    /// tasks.
    pub tasks: Vec<GanttTask>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for gantt header.
pub struct GanttHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for gantt statement.
pub enum GanttStatement {
    /// title.
    Title(Label),
    /// date format.
    DateFormat(Spanned<String>),
    /// axis format.
    AxisFormat(Spanned<String>),
    /// section.
    Section(Label),
    /// task.
    Task(Box<GanttTask>),
    /// config.
    Config(GanttConfigStatement),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for gantt config statement.
pub struct GanttConfigStatement {
    /// key.
    pub key: Spanned<String>,
    /// value.
    pub value: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for gantt task.
pub struct GanttTask {
    /// title.
    pub title: Label,
    /// section.
    pub section: Option<Label>,
    /// tags.
    pub tags: Vec<GanttTaskTag>,
    /// id.
    pub id: Option<Spanned<String>>,
    /// metadata.
    pub metadata: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for gantt task tag.
pub enum GanttTaskTag {
    /// active.
    Active,
    /// done.
    Done,
    /// crit.
    Crit,
    /// milestone.
    Milestone,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for pie ast.
pub struct PieAst {
    /// header.
    pub header: PieHeader,
    /// title.
    pub title: Option<Label>,
    /// show_data.
    pub show_data: bool,
    /// config.
    pub config: PieConfig,
    /// statements.
    pub statements: Vec<PieStatement>,
    /// slices.
    pub slices: Vec<PieSlice>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for pie header.
pub struct PieHeader {
    /// show_data.
    pub show_data: bool,
    /// title.
    pub title: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for pie config.
pub struct PieConfig {
    /// text_position_milli.
    pub text_position_milli: u16,
    /// legend_position.
    pub legend_position: PieLegendPosition,
}

impl Default for PieConfig {
    fn default() -> Self {
        Self::default_values()
    }
}

impl PieConfig {
    #[must_use]
    /// Default_values.
    pub const fn default_values() -> Self {
        Self {
            text_position_milli: 750,
            legend_position: PieLegendPosition::Right,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for pie legend position.
pub enum PieLegendPosition {
    /// top.
    Top,
    /// bottom.
    Bottom,
    /// left.
    Left,
    /// right.
    Right,
    /// center.
    Center,
}

impl PieLegendPosition {
    #[must_use]
    /// Parse a Mermaid direction token.
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
/// Variants for pie statement.
pub enum PieStatement {
    /// title.
    Title(Label),
    /// slice.
    Slice(PieSlice),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for pie slice.
pub struct PieSlice {
    /// label.
    pub label: Label,
    /// value_units.
    pub value_units: Spanned<u64>,
    /// value_text.
    pub value_text: Spanned<String>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for quadrant ast.
pub struct QuadrantAst {
    /// header.
    pub header: QuadrantHeader,
    /// title.
    pub title: Option<Label>,
    /// x_axis.
    pub x_axis: Option<QuadrantAxis>,
    /// y_axis.
    pub y_axis: Option<QuadrantAxis>,
    /// quadrants.
    pub quadrants: Vec<QuadrantSection>,
    /// points.
    pub points: Vec<QuadrantPoint>,
    /// classes.
    pub classes: Vec<FlowClassDef>,
    /// statements.
    pub statements: Vec<QuadrantStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for quadrant header.
pub struct QuadrantHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for quadrant axis kind.
pub enum QuadrantAxisKind {
    /// x.
    X,
    /// y.
    Y,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for quadrant axis.
pub struct QuadrantAxis {
    /// kind.
    pub kind: Spanned<QuadrantAxisKind>,
    /// start.
    pub start: Label,
    /// end.
    pub end: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for quadrant section.
pub struct QuadrantSection {
    /// index.
    pub index: Spanned<u8>,
    /// label.
    pub label: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for quadrant point.
pub struct QuadrantPoint {
    /// label.
    pub label: Label,
    /// x.
    pub x: Spanned<u16>,
    /// y.
    pub y: Spanned<u16>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for quadrant statement.
pub enum QuadrantStatement {
    /// title.
    Title(Label),
    /// axis.
    Axis(QuadrantAxis),
    /// quadrant.
    Quadrant(QuadrantSection),
    /// point.
    Point(Box<QuadrantPoint>),
    /// class def.
    ClassDef(FlowClassDef),
    /// class apply.
    ClassApply(FlowClassApply),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for zenuml ast.
pub struct ZenUmlAst {
    /// header.
    pub header: ZenUmlHeader,
    /// title.
    pub title: Option<Label>,
    /// participants.
    pub participants: Vec<ZenUmlParticipant>,
    /// messages.
    pub messages: Vec<ZenUmlMessage>,
    /// fragments.
    pub fragments: Vec<ZenUmlFragment>,
    /// statements.
    pub statements: Vec<ZenUmlStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for zenuml header.
pub struct ZenUmlHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for zenuml participant.
pub struct ZenUmlParticipant {
    /// id.
    pub id: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// annotator.
    pub annotator: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for zenuml message kind.
pub enum ZenUmlMessageKind {
    /// sync.
    Sync,
    /// async.
    Async,
    /// create.
    Create,
    /// reply.
    Reply,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for zenuml message.
pub struct ZenUmlMessage {
    /// from.
    pub from: Option<Spanned<String>>,
    /// to.
    pub to: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// kind.
    pub kind: Spanned<ZenUmlMessageKind>,
    /// depth.
    pub depth: u16,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for zenuml fragment kind.
pub enum ZenUmlFragmentKind {
    /// loop.
    Loop,
    /// alt.
    Alt,
    /// opt.
    Opt,
    /// parallel.
    Parallel,
    /// try.
    Try,
    /// catch.
    Catch,
    /// finally.
    Finally,
    /// block.
    Block,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for zenuml fragment.
pub struct ZenUmlFragment {
    /// kind.
    pub kind: Spanned<ZenUmlFragmentKind>,
    /// label.
    pub label: Option<Label>,
    /// depth.
    pub depth: u16,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for zenuml statement.
pub enum ZenUmlStatement {
    /// title.
    Title(Label),
    /// participant.
    Participant(ZenUmlParticipant),
    /// message.
    Message(Box<ZenUmlMessage>),
    /// fragment.
    Fragment(ZenUmlFragment),
    /// block end.
    BlockEnd(Span),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sankey ast.
pub struct SankeyAst {
    /// header.
    pub header: SankeyHeader,
    /// links.
    pub links: Vec<SankeyLink>,
    /// statements.
    pub statements: Vec<SankeyStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for sankey header.
pub struct SankeyHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for sankey link.
pub struct SankeyLink {
    /// source.
    pub source: Label,
    /// target.
    pub target: Label,
    /// value_units.
    pub value_units: Spanned<u64>,
    /// value_text.
    pub value_text: Spanned<String>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for sankey statement.
pub enum SankeyStatement {
    /// link.
    Link(Box<SankeyLink>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for xy chart ast.
pub struct XyChartAst {
    /// header.
    pub header: XyChartHeader,
    /// title.
    pub title: Option<Label>,
    /// x_axis.
    pub x_axis: Option<XyChartAxis>,
    /// y_axis.
    pub y_axis: Option<XyChartAxis>,
    /// series.
    pub series: Vec<XyChartSeries>,
    /// statements.
    pub statements: Vec<XyChartStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for xy chart header.
pub struct XyChartHeader {
    /// orientation.
    pub orientation: Option<Spanned<XyChartOrientation>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for xy chart orientation.
pub enum XyChartOrientation {
    /// vertical.
    Vertical,
    /// horizontal.
    Horizontal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for xy chart axis kind.
pub enum XyChartAxisKind {
    /// x.
    X,
    /// y.
    Y,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for xy chart axis scale.
pub enum XyChartAxisScale {
    /// categories.
    Categories(Vec<Label>),
    /// numeric range.
    Range {
        /// minimum value.
        min: Spanned<i64>,
        /// maximum value.
        max: Spanned<i64>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for xy chart axis.
pub struct XyChartAxis {
    /// kind.
    pub kind: Spanned<XyChartAxisKind>,
    /// title.
    pub title: Option<Label>,
    /// scale.
    pub scale: Option<XyChartAxisScale>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for xy chart series kind.
pub enum XyChartSeriesKind {
    /// bar.
    Bar,
    /// line.
    Line,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for xy chart series.
pub struct XyChartSeries {
    /// kind.
    pub kind: Spanned<XyChartSeriesKind>,
    /// values.
    pub values: Vec<Spanned<i64>>,
    /// value_texts.
    pub value_texts: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for xy chart statement.
pub enum XyChartStatement {
    /// title.
    Title(Label),
    /// axis.
    Axis(XyChartAxis),
    /// series.
    Series(XyChartSeries),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for block diagram ast.
pub struct BlockDiagramAst {
    /// header.
    pub header: BlockDiagramHeader,
    /// statements.
    pub statements: Vec<BlockStatement>,
    /// blocks.
    pub blocks: Vec<BlockNode>,
    /// edges.
    pub edges: Vec<BlockEdge>,
    /// classes.
    pub classes: Vec<FlowClassDef>,
    /// styles.
    pub styles: Vec<BlockStyle>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for block diagram header.
pub struct BlockDiagramHeader {
    /// columns.
    pub columns: Option<Spanned<u16>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for block statement.
pub enum BlockStatement {
    /// columns.
    Columns(Spanned<u16>),
    /// node.
    Node(Box<BlockNode>),
    /// space.
    Space(BlockSpace),
    /// container.
    Container(Box<BlockContainer>),
    /// edge.
    Edge(Box<BlockEdge>),
    /// class def.
    ClassDef(FlowClassDef),
    /// class apply.
    ClassApply(FlowClassApply),
    /// style.
    Style(BlockStyle),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for block node.
pub struct BlockNode {
    /// id.
    pub id: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// shape.
    pub shape: Spanned<BlockShape>,
    /// width.
    pub width: Spanned<u16>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for block shape.
pub enum BlockShape {
    /// flow.
    Flow(FlowShape),
    /// arrow.
    Arrow(Vec<Spanned<BlockArrowDirection>>),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for block arrow direction.
pub enum BlockArrowDirection {
    /// left.
    Left,
    /// right.
    Right,
    /// up.
    Up,
    /// down.
    Down,
    /// x.
    X,
    /// y.
    Y,
}

impl BlockArrowDirection {
    #[must_use]
    /// Parse a Mermaid direction token.
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
/// Parsed data for block space.
pub struct BlockSpace {
    /// width.
    pub width: Spanned<u16>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for block container.
pub struct BlockContainer {
    /// id.
    pub id: Option<Spanned<String>>,
    /// width.
    pub width: Spanned<u16>,
    /// columns.
    pub columns: Option<Spanned<u16>>,
    /// statements.
    pub statements: Vec<BlockStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for block edge.
pub struct BlockEdge {
    /// from.
    pub from: Spanned<String>,
    /// to.
    pub to: Spanned<String>,
    /// from_node.
    pub from_node: BlockNode,
    /// to_node.
    pub to_node: BlockNode,
    /// link.
    pub link: Spanned<FlowEdgeLink>,
    /// label.
    pub label: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for block style.
pub struct BlockStyle {
    /// target.
    pub target: Spanned<String>,
    /// styles.
    pub styles: Vec<FlowStyleDeclaration>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for packet ast.
pub struct PacketAst {
    /// header.
    pub header: PacketHeader,
    /// title.
    pub title: Option<Label>,
    /// fields.
    pub fields: Vec<PacketField>,
    /// statements.
    pub statements: Vec<PacketStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for packet header.
pub struct PacketHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for packet statement.
pub enum PacketStatement {
    /// title.
    Title(Label),
    /// field.
    Field(Box<PacketField>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for packet field.
pub struct PacketField {
    /// range.
    pub range: PacketRange,
    /// label.
    pub label: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for packet range.
pub struct PacketRange {
    /// start.
    pub start: Spanned<u32>,
    /// end.
    pub end: Spanned<u32>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for kanban ast.
pub struct KanbanAst {
    /// header.
    pub header: KanbanHeader,
    /// columns.
    pub columns: Vec<KanbanColumn>,
    /// statements.
    pub statements: Vec<KanbanStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for kanban header.
pub struct KanbanHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for kanban statement.
pub enum KanbanStatement {
    /// column.
    Column(Box<KanbanColumn>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for kanban column.
pub struct KanbanColumn {
    /// id.
    pub id: Option<Spanned<String>>,
    /// title.
    pub title: Label,
    /// tasks.
    pub tasks: Vec<KanbanTask>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for kanban task.
pub struct KanbanTask {
    /// id.
    pub id: Option<Spanned<String>>,
    /// label.
    pub label: Label,
    /// metadata.
    pub metadata: Vec<KanbanMetadata>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for kanban metadata.
pub struct KanbanMetadata {
    /// key.
    pub key: Spanned<String>,
    /// value.
    pub value: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for architecture ast.
pub struct ArchitectureAst {
    /// header.
    pub header: ArchitectureHeader,
    /// groups.
    pub groups: Vec<ArchitectureGroup>,
    /// services.
    pub services: Vec<ArchitectureService>,
    /// junctions.
    pub junctions: Vec<ArchitectureJunction>,
    /// edges.
    pub edges: Vec<ArchitectureEdge>,
    /// alignments.
    pub alignments: Vec<ArchitectureAlignment>,
    /// statements.
    pub statements: Vec<ArchitectureStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for architecture header.
pub struct ArchitectureHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for architecture statement.
pub enum ArchitectureStatement {
    /// group.
    Group(Box<ArchitectureGroup>),
    /// service.
    Service(Box<ArchitectureService>),
    /// junction.
    Junction(Box<ArchitectureJunction>),
    /// edge.
    Edge(Box<ArchitectureEdge>),
    /// alignment.
    Alignment(Box<ArchitectureAlignment>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for architecture group.
pub struct ArchitectureGroup {
    /// id.
    pub id: Spanned<String>,
    /// icon.
    pub icon: Option<Label>,
    /// title.
    pub title: Option<Label>,
    /// parent.
    pub parent: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for architecture service.
pub struct ArchitectureService {
    /// id.
    pub id: Spanned<String>,
    /// icon.
    pub icon: Option<Label>,
    /// title.
    pub title: Option<Label>,
    /// parent.
    pub parent: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for architecture junction.
pub struct ArchitectureJunction {
    /// id.
    pub id: Spanned<String>,
    /// parent.
    pub parent: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for architecture edge.
pub struct ArchitectureEdge {
    /// from.
    pub from: ArchitectureEndpoint,
    /// to.
    pub to: ArchitectureEndpoint,
    /// arrow_start.
    pub arrow_start: bool,
    /// arrow_end.
    pub arrow_end: bool,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for architecture endpoint.
pub struct ArchitectureEndpoint {
    /// id.
    pub id: Spanned<String>,
    /// side.
    pub side: Spanned<ArchitectureSide>,
    /// group.
    pub group: bool,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for architecture side.
pub enum ArchitectureSide {
    /// top.
    Top,
    /// bottom.
    Bottom,
    /// left.
    Left,
    /// right.
    Right,
}

impl ArchitectureSide {
    #[must_use]
    /// Parse a Mermaid direction token.
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
    /// As_mermaid.
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
/// Parsed data for architecture alignment.
pub struct ArchitectureAlignment {
    /// axis.
    pub axis: Spanned<ArchitectureAlignAxis>,
    /// members.
    pub members: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for architecture align axis.
pub enum ArchitectureAlignAxis {
    /// row.
    Row,
    /// column.
    Column,
}

impl ArchitectureAlignAxis {
    #[must_use]
    /// Parse a Mermaid direction token.
    pub const fn from_mermaid(value: &str) -> Option<Self> {
        match value.as_bytes() {
            b"row" => Some(Self::Row),
            b"column" => Some(Self::Column),
            _ => None,
        }
    }

    #[must_use]
    /// As_mermaid.
    pub const fn as_mermaid(self) -> &'static str {
        match self {
            Self::Row => "row",
            Self::Column => "column",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for radar ast.
pub struct RadarAst {
    /// header.
    pub header: RadarHeader,
    /// title.
    pub title: Option<Label>,
    /// axes.
    pub axes: Vec<RadarAxis>,
    /// curves.
    pub curves: Vec<RadarCurve>,
    /// options.
    pub options: Vec<RadarOption>,
    /// statements.
    pub statements: Vec<RadarStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for radar header.
pub struct RadarHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for radar statement.
pub enum RadarStatement {
    /// title.
    Title(Label),
    /// axis.
    Axis(Box<RadarAxis>),
    /// curve.
    Curve(Box<RadarCurve>),
    /// option.
    Option(Box<RadarOption>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for radar axis.
pub struct RadarAxis {
    /// id.
    pub id: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for radar curve.
pub struct RadarCurve {
    /// id.
    pub id: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// values.
    pub values: Vec<RadarCurveValue>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for radar curve value.
pub struct RadarCurveValue {
    /// axis.
    pub axis: Option<Spanned<String>>,
    /// value.
    pub value: Spanned<String>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for radar option.
pub struct RadarOption {
    /// kind.
    pub kind: Spanned<RadarOptionKind>,
    /// value.
    pub value: Spanned<String>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for radar option kind.
pub enum RadarOptionKind {
    /// show legend.
    ShowLegend,
    /// max.
    Max,
    /// min.
    Min,
    /// graticule.
    Graticule,
    /// ticks.
    Ticks,
}

impl RadarOptionKind {
    #[must_use]
    /// Parse a Mermaid direction token.
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
    /// As_mermaid.
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
/// Parsed data for event modeling ast.
pub struct EventModelingAst {
    /// header.
    pub header: EventModelingHeader,
    /// timeframes.
    pub timeframes: Vec<EventModelingTimeFrame>,
    /// data_blocks.
    pub data_blocks: Vec<EventModelingDataBlock>,
    /// statements.
    pub statements: Vec<EventModelingStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for event modeling header.
pub struct EventModelingHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for event modeling statement.
pub enum EventModelingStatement {
    /// time frame.
    TimeFrame(Box<EventModelingTimeFrame>),
    /// data block.
    DataBlock(Box<EventModelingDataBlock>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for event modeling time frame.
pub struct EventModelingTimeFrame {
    /// kind.
    pub kind: Spanned<EventModelingFrameKind>,
    /// number.
    pub number: Spanned<String>,
    /// entity_type.
    pub entity_type: Spanned<EventModelingEntityType>,
    /// entity.
    pub entity: Spanned<String>,
    /// data_ref.
    pub data_ref: Option<Spanned<String>>,
    /// data.
    pub data: Option<EventModelingData>,
    /// relations.
    pub relations: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for event modeling frame kind.
pub enum EventModelingFrameKind {
    /// time frame.
    TimeFrame,
    /// reset frame.
    ResetFrame,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for event modeling entity type.
pub enum EventModelingEntityType {
    /// ui.
    Ui,
    /// processor.
    Processor,
    /// command.
    Command,
    /// read model.
    ReadModel,
    /// event.
    Event,
}

impl EventModelingEntityType {
    #[must_use]
    /// Parse a Mermaid direction token.
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
    /// As_mermaid.
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
/// Parsed data for event modeling data block.
pub struct EventModelingDataBlock {
    /// id.
    pub id: Spanned<String>,
    /// data.
    pub data: EventModelingData,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for event modeling data.
pub struct EventModelingData {
    /// ty.
    pub ty: Option<Spanned<String>>,
    /// body.
    pub body: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for treemap ast.
pub struct TreemapAst {
    /// header.
    pub header: TreemapHeader,
    /// statements.
    pub statements: Vec<TreemapStatement>,
    /// roots.
    pub roots: Vec<TreemapNode>,
    /// classes.
    pub classes: Vec<FlowClassDef>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for treemap header.
pub struct TreemapHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for treemap statement.
pub enum TreemapStatement {
    /// node.
    Node(Box<TreemapNode>),
    /// class def.
    ClassDef(FlowClassDef),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for treemap node.
pub struct TreemapNode {
    /// label.
    pub label: Label,
    /// value.
    pub value: Option<Spanned<String>>,
    /// classes.
    pub classes: Vec<Spanned<String>>,
    /// children.
    pub children: Vec<TreemapNode>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for venn ast.
pub struct VennAst {
    /// header.
    pub header: VennHeader,
    /// title.
    pub title: Option<Label>,
    /// sets.
    pub sets: Vec<VennSet>,
    /// unions.
    pub unions: Vec<VennUnion>,
    /// texts.
    pub texts: Vec<VennText>,
    /// styles.
    pub styles: Vec<VennStyle>,
    /// statements.
    pub statements: Vec<VennStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for venn header.
pub struct VennHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for venn statement.
pub enum VennStatement {
    /// title.
    Title(Label),
    /// set.
    Set(Box<VennSet>),
    /// union.
    Union(Box<VennUnion>),
    /// text.
    Text(Box<VennText>),
    /// style.
    Style(VennStyle),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for venn set.
pub struct VennSet {
    /// id.
    pub id: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// size.
    pub size: Option<Spanned<String>>,
    /// texts.
    pub texts: Vec<VennText>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for venn union.
pub struct VennUnion {
    /// members.
    pub members: Vec<Spanned<String>>,
    /// label.
    pub label: Option<Label>,
    /// size.
    pub size: Option<Spanned<String>>,
    /// texts.
    pub texts: Vec<VennText>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for venn text.
pub struct VennText {
    /// id.
    pub id: Spanned<String>,
    /// label.
    pub label: Option<Label>,
    /// owner.
    pub owner: Option<VennTextOwner>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for venn text owner.
pub enum VennTextOwner {
    /// set.
    Set(String),
    /// union.
    Union(Vec<String>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for venn style.
pub struct VennStyle {
    /// targets.
    pub targets: Vec<Spanned<String>>,
    /// declarations.
    pub declarations: Vec<FlowStyleDeclaration>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for ishikawa ast.
pub struct IshikawaAst {
    /// header.
    pub header: IshikawaHeader,
    /// event.
    pub event: Label,
    /// causes.
    pub causes: Vec<IshikawaNode>,
    /// statements.
    pub statements: Vec<IshikawaStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for ishikawa header.
pub struct IshikawaHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for ishikawa statement.
pub enum IshikawaStatement {
    /// event.
    Event(Label),
    /// cause.
    Cause(Box<IshikawaNode>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for ishikawa node.
pub struct IshikawaNode {
    /// label.
    pub label: Label,
    /// causes.
    pub causes: Vec<IshikawaNode>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley ast.
pub struct WardleyAst {
    /// header.
    pub header: WardleyHeader,
    /// title.
    pub title: Option<Label>,
    /// size.
    pub size: Option<WardleySize>,
    /// components.
    pub components: Vec<WardleyComponent>,
    /// links.
    pub links: Vec<WardleyLink>,
    /// evolves.
    pub evolves: Vec<WardleyEvolve>,
    /// notes.
    pub notes: Vec<WardleyNote>,
    /// annotations_position.
    pub annotations_position: Option<WardleyCoord>,
    /// annotations.
    pub annotations: Vec<WardleyAnnotation>,
    /// forces.
    pub forces: Vec<WardleyForce>,
    /// evolution.
    pub evolution: Option<WardleyEvolution>,
    /// statements.
    pub statements: Vec<WardleyStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for wardley header.
pub struct WardleyHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for wardley statement.
pub enum WardleyStatement {
    /// title.
    Title(Label),
    /// size.
    Size(WardleySize),
    /// component.
    Component(Box<WardleyComponent>),
    /// link.
    Link(WardleyLink),
    /// evolve.
    Evolve(WardleyEvolve),
    /// note.
    Note(WardleyNote),
    /// annotations.
    Annotations(WardleyCoord),
    /// annotation.
    Annotation(WardleyAnnotation),
    /// force.
    Force(WardleyForce),
    /// evolution.
    Evolution(WardleyEvolution),
    /// pipeline.
    Pipeline(Label),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for wardley size.
pub struct WardleySize {
    /// width.
    pub width: u32,
    /// height.
    pub height: u32,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley component.
pub struct WardleyComponent {
    /// kind.
    pub kind: WardleyComponentKind,
    /// name.
    pub name: Label,
    /// coord.
    pub coord: WardleyCoord,
    /// label_offset.
    pub label_offset: Option<WardleyLabelOffset>,
    /// decorators.
    pub decorators: Vec<WardleyDecorator>,
    /// pipeline.
    pub pipeline: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for wardley component kind.
pub enum WardleyComponentKind {
    /// component.
    Component,
    /// anchor.
    Anchor,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley coord.
pub struct WardleyCoord {
    /// visibility.
    pub visibility: Spanned<String>,
    /// evolution.
    pub evolution: Spanned<String>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for wardley label offset.
pub struct WardleyLabelOffset {
    /// x.
    pub x: i32,
    /// y.
    pub y: i32,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for wardley decorator.
pub enum WardleyDecorator {
    /// inertia.
    Inertia,
    /// build.
    Build,
    /// buy.
    Buy,
    /// outsource.
    Outsource,
    /// market.
    Market,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley link.
pub struct WardleyLink {
    /// from.
    pub from: Label,
    /// to.
    pub to: Label,
    /// kind.
    pub kind: WardleyLinkKind,
    /// label.
    pub label: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for wardley link kind.
pub enum WardleyLinkKind {
    /// dependency.
    Dependency,
    /// dashed.
    Dashed,
    /// flow.
    Flow,
    /// reverse flow.
    ReverseFlow,
    /// bidirectional flow.
    BidirectionalFlow,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley evolve.
pub struct WardleyEvolve {
    /// name.
    pub name: Label,
    /// target_evolution.
    pub target_evolution: Spanned<String>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley note.
pub struct WardleyNote {
    /// text.
    pub text: Label,
    /// coord.
    pub coord: WardleyCoord,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley annotation.
pub struct WardleyAnnotation {
    /// number.
    pub number: Spanned<String>,
    /// coord.
    pub coord: WardleyCoord,
    /// text.
    pub text: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley force.
pub struct WardleyForce {
    /// kind.
    pub kind: WardleyForceKind,
    /// text.
    pub text: Label,
    /// coord.
    pub coord: WardleyCoord,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for wardley force kind.
pub enum WardleyForceKind {
    /// accelerator.
    Accelerator,
    /// deaccelerator.
    Deaccelerator,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley evolution.
pub struct WardleyEvolution {
    /// stages.
    pub stages: Vec<WardleyEvolutionStage>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for wardley evolution stage.
pub struct WardleyEvolutionStage {
    /// label.
    pub label: Label,
    /// boundary.
    pub boundary: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for tree view ast.
pub struct TreeViewAst {
    /// header.
    pub header: TreeViewHeader,
    /// statements.
    pub statements: Vec<TreeViewStatement>,
    /// roots.
    pub roots: Vec<TreeViewNode>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for tree view header.
pub struct TreeViewHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for tree view statement.
pub enum TreeViewStatement {
    /// node.
    Node(Box<TreeViewNode>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for tree view node.
pub struct TreeViewNode {
    /// label.
    pub label: Label,
    /// directory.
    pub directory: bool,
    /// icon.
    pub icon: Option<Spanned<String>>,
    /// classes.
    pub classes: Vec<Spanned<String>>,
    /// description.
    pub description: Option<Label>,
    /// children.
    pub children: Vec<TreeViewNode>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for cynefin ast.
pub struct CynefinAst {
    /// header.
    pub header: CynefinHeader,
    /// title.
    pub title: Option<Label>,
    /// domains.
    pub domains: Vec<CynefinDomain>,
    /// transitions.
    pub transitions: Vec<CynefinTransition>,
    /// statements.
    pub statements: Vec<CynefinStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for cynefin header.
pub struct CynefinHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for cynefin domain kind.
pub enum CynefinDomainKind {
    /// complex.
    Complex,
    /// complicated.
    Complicated,
    /// clear.
    Clear,
    /// chaotic.
    Chaotic,
    /// confusion.
    Confusion,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for cynefin statement.
pub enum CynefinStatement {
    /// title.
    Title(Label),
    /// domain.
    Domain(Box<CynefinDomain>),
    /// transition.
    Transition(Box<CynefinTransition>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for cynefin domain.
pub struct CynefinDomain {
    /// kind.
    pub kind: Spanned<CynefinDomainKind>,
    /// items.
    pub items: Vec<CynefinItem>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for cynefin item.
pub struct CynefinItem {
    /// label.
    pub label: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for cynefin transition.
pub struct CynefinTransition {
    /// from.
    pub from: Spanned<CynefinDomainKind>,
    /// to.
    pub to: Spanned<CynefinDomainKind>,
    /// label.
    pub label: Option<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for railroad ast.
pub struct RailroadAst {
    /// header.
    pub header: RailroadHeader,
    /// title.
    pub title: Option<Label>,
    /// rules.
    pub rules: Vec<RailroadRule>,
    /// statements.
    pub statements: Vec<RailroadStatement>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for railroad header.
pub struct RailroadHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for railroad statement.
pub enum RailroadStatement {
    /// title.
    Title(Label),
    /// rule.
    Rule(Box<RailroadRule>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for railroad rule.
pub struct RailroadRule {
    /// name.
    pub name: Spanned<String>,
    /// expression.
    pub expression: Label,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for swimlanes ast.
pub struct SwimlanesAst {
    /// header.
    pub header: SwimlanesHeader,
    /// flow graph.
    pub graph: FlowchartAst,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for swimlanes header.
pub struct SwimlanesHeader {
    /// direction.
    pub direction: Spanned<Direction>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for mindmap ast.
pub struct MindmapAst {
    /// header.
    pub header: MindmapHeader,
    /// statements.
    pub statements: Vec<MindmapStatement>,
    /// roots.
    pub roots: Vec<MindmapNode>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for mindmap header.
pub struct MindmapHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for mindmap statement.
pub enum MindmapStatement {
    /// node.
    Node(Box<MindmapNode>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for mindmap node.
pub struct MindmapNode {
    /// label.
    pub label: Label,
    /// shape.
    pub shape: MindmapShape,
    /// icon.
    pub icon: Option<Spanned<String>>,
    /// classes.
    pub classes: Vec<Spanned<String>>,
    /// children.
    pub children: Vec<MindmapNode>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for mindmap shape.
pub enum MindmapShape {
    /// default.
    Default,
    /// square.
    Square,
    /// rounded.
    Rounded,
    /// circle.
    Circle,
    /// bang.
    Bang,
    /// cloud.
    Cloud,
    /// hexagon.
    Hexagon,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for journey ast.
pub struct JourneyAst {
    /// header.
    pub header: JourneyHeader,
    /// title.
    pub title: Option<Label>,
    /// statements.
    pub statements: Vec<JourneyStatement>,
    /// tasks.
    pub tasks: Vec<JourneyTask>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for journey header.
pub struct JourneyHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for journey statement.
pub enum JourneyStatement {
    /// title.
    Title(Label),
    /// section.
    Section(Label),
    /// task.
    Task(Box<JourneyTask>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for journey task.
pub struct JourneyTask {
    /// label.
    pub label: Label,
    /// section.
    pub section: Option<Label>,
    /// score.
    pub score: Spanned<u8>,
    /// actors.
    pub actors: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for git graph ast.
pub struct GitGraphAst {
    /// header.
    pub header: GitGraphHeader,
    /// statements.
    pub statements: Vec<GitGraphStatement>,
    /// commits.
    pub commits: Vec<GitGraphCommit>,
    /// branches.
    pub branches: Vec<GitGraphBranch>,
    /// merges.
    pub merges: Vec<GitGraphMerge>,
    /// cherry_picks.
    pub cherry_picks: Vec<GitGraphCherryPick>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for git graph header.
pub struct GitGraphHeader {
    /// orientation.
    pub orientation: Spanned<GitGraphOrientation>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for git graph orientation.
pub enum GitGraphOrientation {
    /// left right.
    LeftRight,
    /// top bottom.
    TopBottom,
    /// bottom top.
    BottomTop,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for git graph statement.
pub enum GitGraphStatement {
    /// commit.
    Commit(Box<GitGraphCommit>),
    /// branch.
    Branch(Box<GitGraphBranch>),
    /// checkout.
    Checkout(Spanned<String>),
    /// merge.
    Merge(Box<GitGraphMerge>),
    /// cherry pick.
    CherryPick(Box<GitGraphCherryPick>),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for git graph commit kind.
pub enum GitGraphCommitKind {
    /// normal.
    Normal,
    /// reverse.
    Reverse,
    /// highlight.
    Highlight,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for git graph commit.
pub struct GitGraphCommit {
    /// id.
    pub id: Option<Spanned<String>>,
    /// tag.
    pub tag: Option<Spanned<String>>,
    /// kind.
    pub kind: Spanned<GitGraphCommitKind>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for git graph branch.
pub struct GitGraphBranch {
    /// name.
    pub name: Spanned<String>,
    /// order.
    pub order: Option<Spanned<i32>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for git graph merge.
pub struct GitGraphMerge {
    /// branch.
    pub branch: Spanned<String>,
    /// id.
    pub id: Option<Spanned<String>>,
    /// tag.
    pub tag: Option<Spanned<String>>,
    /// kind.
    pub kind: Spanned<GitGraphCommitKind>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for git graph cherry pick.
pub struct GitGraphCherryPick {
    /// id.
    pub id: Spanned<String>,
    /// parent.
    pub parent: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for timeline ast.
pub struct TimelineAst {
    /// header.
    pub header: TimelineHeader,
    /// title.
    pub title: Option<Label>,
    /// statements.
    pub statements: Vec<TimelineStatement>,
    /// periods.
    pub periods: Vec<TimelinePeriod>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for timeline header.
pub struct TimelineHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for timeline statement.
pub enum TimelineStatement {
    /// title.
    Title(Label),
    /// section.
    Section(Label),
    /// period.
    Period(Box<TimelinePeriod>),
    /// event.
    Event(Label),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for timeline period.
pub struct TimelinePeriod {
    /// label.
    pub label: Label,
    /// section.
    pub section: Option<Label>,
    /// events.
    pub events: Vec<Label>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for requirement ast.
pub struct RequirementAst {
    /// header.
    pub header: RequirementHeader,
    /// direction.
    pub direction: Option<Spanned<Direction>>,
    /// statements.
    pub statements: Vec<RequirementStatement>,
    /// requirements.
    pub requirements: Vec<RequirementNode>,
    /// elements.
    pub elements: Vec<RequirementElement>,
    /// relationships.
    pub relationships: Vec<RequirementRelationship>,
    /// classes.
    pub classes: Vec<FlowClassDef>,
    /// styles.
    pub styles: Vec<RequirementStyle>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Parsed data for requirement header.
pub struct RequirementHeader {
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for requirement statement.
pub enum RequirementStatement {
    /// requirement.
    Requirement(Box<RequirementNode>),
    /// element.
    Element(Box<RequirementElement>),
    /// relationship.
    Relationship(Box<RequirementRelationship>),
    /// direction.
    Direction(Spanned<Direction>),
    /// style.
    Style(RequirementStyle),
    /// class def.
    ClassDef(FlowClassDef),
    /// class apply.
    ClassApply(FlowClassApply),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for requirement kind.
pub enum RequirementKind {
    /// requirement.
    Requirement,
    /// functional.
    Functional,
    /// interface.
    Interface,
    /// performance.
    Performance,
    /// physical.
    Physical,
    /// design constraint.
    DesignConstraint,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for requirement risk.
pub enum RequirementRisk {
    /// low.
    Low,
    /// medium.
    Medium,
    /// high.
    High,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for requirement verify method.
pub enum RequirementVerifyMethod {
    /// analysis.
    Analysis,
    /// inspection.
    Inspection,
    /// test.
    Test,
    /// demonstration.
    Demonstration,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for requirement node.
pub struct RequirementNode {
    /// name.
    pub name: Spanned<String>,
    /// kind.
    pub kind: Spanned<RequirementKind>,
    /// requirement_id.
    pub requirement_id: Option<Label>,
    /// text.
    pub text: Option<Label>,
    /// risk.
    pub risk: Option<Spanned<RequirementRisk>>,
    /// verify_method.
    pub verify_method: Option<Spanned<RequirementVerifyMethod>>,
    /// classes.
    pub classes: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for requirement element.
pub struct RequirementElement {
    /// name.
    pub name: Spanned<String>,
    /// ty.
    pub ty: Option<Label>,
    /// doc_ref.
    pub doc_ref: Option<Label>,
    /// classes.
    pub classes: Vec<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for requirement relationship kind.
pub enum RequirementRelationshipKind {
    /// contains.
    Contains,
    /// copies.
    Copies,
    /// derives.
    Derives,
    /// satisfies.
    Satisfies,
    /// verifies.
    Verifies,
    /// refines.
    Refines,
    /// traces.
    Traces,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for requirement relationship.
pub struct RequirementRelationship {
    /// from.
    pub from: Spanned<String>,
    /// to.
    pub to: Spanned<String>,
    /// kind.
    pub kind: Spanned<RequirementRelationshipKind>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for requirement style.
pub struct RequirementStyle {
    /// node_ids.
    pub node_ids: Vec<Spanned<String>>,
    /// styles.
    pub styles: Vec<FlowStyleDeclaration>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for c4 ast.
pub struct C4Ast {
    /// header.
    pub header: C4Header,
    /// title.
    pub title: Option<Label>,
    /// statements.
    pub statements: Vec<C4Statement>,
    /// elements.
    pub elements: Vec<C4Element>,
    /// relationships.
    pub relationships: Vec<C4Relationship>,
    /// boundaries.
    pub boundaries: Vec<C4Boundary>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for c4 header.
pub struct C4Header {
    /// diagram_type.
    pub diagram_type: Spanned<C4DiagramType>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for c4 diagram type.
pub enum C4DiagramType {
    /// context.
    Context,
    /// container.
    Container,
    /// component.
    Component,
    /// dynamic.
    Dynamic,
    /// deployment.
    Deployment,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Variants for c4 statement.
pub enum C4Statement {
    /// title.
    Title(Label),
    /// element.
    Element(Box<C4Element>),
    /// relationship.
    Relationship(Box<C4Relationship>),
    /// boundary.
    Boundary(Box<C4Boundary>),
    /// style.
    Style(C4StyleUpdate),
    /// layout.
    Layout(C4LayoutConfig),
    /// comment.
    Comment(MermaidComment),
    /// directive.
    Directive(MermaidDirective),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for c4 element kind.
pub enum C4ElementKind {
    /// person.
    Person,
    /// person external.
    PersonExternal,
    /// system.
    System,
    /// system external.
    SystemExternal,
    /// system db.
    SystemDb,
    /// system db external.
    SystemDbExternal,
    /// system queue.
    SystemQueue,
    /// system queue external.
    SystemQueueExternal,
    /// container.
    Container,
    /// container external.
    ContainerExternal,
    /// container db.
    ContainerDb,
    /// container db external.
    ContainerDbExternal,
    /// container queue.
    ContainerQueue,
    /// container queue external.
    ContainerQueueExternal,
    /// component.
    Component,
    /// component external.
    ComponentExternal,
    /// component db.
    ComponentDb,
    /// component db external.
    ComponentDbExternal,
    /// component queue.
    ComponentQueue,
    /// component queue external.
    ComponentQueueExternal,
    /// deployment node.
    DeploymentNode,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for c4 element.
pub struct C4Element {
    /// alias.
    pub alias: Spanned<String>,
    /// label.
    pub label: Label,
    /// kind.
    pub kind: Spanned<C4ElementKind>,
    /// technology.
    pub technology: Option<Label>,
    /// description.
    pub description: Option<Label>,
    /// parent.
    pub parent: Option<Spanned<String>>,
    /// external.
    pub external: bool,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for c4 boundary kind.
pub enum C4BoundaryKind {
    /// boundary.
    Boundary,
    /// enterprise.
    Enterprise,
    /// system.
    System,
    /// container.
    Container,
    /// deployment node.
    DeploymentNode,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for c4 boundary.
pub struct C4Boundary {
    /// alias.
    pub alias: Spanned<String>,
    /// label.
    pub label: Label,
    /// kind.
    pub kind: Spanned<C4BoundaryKind>,
    /// ty.
    pub ty: Option<Label>,
    /// parent.
    pub parent: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Variants for c4 relationship kind.
pub enum C4RelationshipKind {
    /// directed.
    Directed,
    /// bidirectional.
    Bidirectional,
    /// up.
    Up,
    /// down.
    Down,
    /// left.
    Left,
    /// right.
    Right,
    /// back.
    Back,
    /// indexed.
    Indexed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for c4 relationship.
pub struct C4Relationship {
    /// from.
    pub from: Spanned<String>,
    /// to.
    pub to: Spanned<String>,
    /// label.
    pub label: Label,
    /// technology.
    pub technology: Option<Label>,
    /// kind.
    pub kind: Spanned<C4RelationshipKind>,
    /// index.
    pub index: Option<Spanned<String>>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for c4 style update.
pub struct C4StyleUpdate {
    /// target_ids.
    pub target_ids: Vec<Spanned<String>>,
    /// fields.
    pub fields: Vec<C4CallArg>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for c4 layout config.
pub struct C4LayoutConfig {
    /// name.
    pub name: Spanned<String>,
    /// fields.
    pub fields: Vec<C4CallArg>,
    /// span.
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed data for c4 call arg.
pub struct C4CallArg {
    /// name.
    pub name: Option<Spanned<String>>,
    /// value.
    pub value: Label,
    /// span.
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
