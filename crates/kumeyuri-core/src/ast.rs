#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagram;

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
