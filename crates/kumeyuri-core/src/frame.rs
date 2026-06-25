//! Fixed-cell frame model and static diagram rendering.

use crate::ast::{
    ArrowHead, BlockArrowDirection, BlockDiagramAst, BlockShape, C4Ast, C4RelationshipKind,
    ClassAst, ClassRelationshipLine, ClassRelationshipMarker, CynefinAst, CynefinDomain,
    CynefinDomainKind, Diagram, DiagramKind, ErAst, EventModelingAst, EventModelingEntityType,
    EventModelingFrameKind, FlowShape, FlowchartAst, GanttAst, GanttTaskTag, GitGraphAst,
    GitGraphCommitKind, IshikawaAst, JourneyAst, KanbanAst, MindmapAst, MindmapShape, PacketAst,
    PieAst, QuadrantAst, RadarAst, RailroadAst, RequirementAst, RequirementRelationshipKind,
    SankeyAst, SequenceAst, SequenceControlKind, StateAst, SwimlanesAst, TimelineAst, TreeViewAst,
    TreemapAst, VennAst, WardleyAst, WardleyComponentKind, WardleyDecorator, WardleyLinkKind,
    XyChartAst, XyChartSeriesKind, ZenUmlAst, ZenUmlMessageKind,
};
use crate::layout::{
    ArchitectureLayout, ArchitectureLayoutEngine, ArchitectureNodeKind, BlockLayout,
    BlockLayoutEngine, C4Layout, C4LayoutEngine, ClassLayout, ClassLayoutEngine, ErLayoutEngine,
    EventModelingLayout, EventModelingLayoutEngine, FlowLayout, FlowLayoutConfig, FlowLayoutEngine,
    GanttLayout, GanttLayoutEngine, GitGraphLayout, GitGraphLayoutEngine, IshikawaLayout,
    IshikawaLayoutEngine, JourneyLayout, JourneyLayoutEngine, KanbanLayout, KanbanLayoutEngine,
    MindmapLayout, MindmapLayoutEngine, PacketLayout, PacketLayoutEngine, PieLayout,
    PieLayoutEngine, Point, PositionedArchitectureEdge, PositionedArchitectureNode,
    PositionedBlockEdge, PositionedBlockNode, PositionedC4Boundary, PositionedC4Element,
    PositionedC4Relationship, PositionedClassNode, PositionedClassRelationship,
    PositionedEventModelingDataBlock, PositionedEventModelingFrame,
    PositionedEventModelingRelation, PositionedFlowEdge, PositionedFlowNode,
    PositionedFlowSubgraph, PositionedGanttTask, PositionedGitGraphCommit, PositionedIshikawaEdge,
    PositionedIshikawaNode, PositionedJourneyTask, PositionedKanbanTask, PositionedMindmapNode,
    PositionedPacketField, PositionedPieSlice, PositionedQuadrantPoint, PositionedRadarCurve,
    PositionedRequirementNode, PositionedRequirementRelationship, PositionedSankeyLink,
    PositionedSequenceActivation, PositionedSequenceBox, PositionedSequenceDestroy,
    PositionedSequenceMessage, PositionedSequenceNote, PositionedTreeViewNode,
    PositionedTreemapNode, PositionedVennSet, PositionedVennStyle, PositionedVennUnion,
    PositionedWardleyComponent, PositionedWardleyEvolve, PositionedWardleyLink,
    PositionedWardleyText, PositionedXyChartSeries, PositionedZenUmlMessage, QuadrantLayout,
    QuadrantLayoutEngine, RadarLayout, RadarLayoutEngine, Rect, RequirementLayout,
    RequirementLayoutEngine, SankeyLayout, SankeyLayoutEngine, SequenceLayout,
    SequenceLayoutEngine, Size, StateLayoutEngine, TimelineLayout, TimelineLayoutEngine,
    TreeViewLayout, TreeViewLayoutEngine, TreemapLayout, TreemapLayoutEngine, VennLayout,
    VennLayoutEngine, WardleyLayout, WardleyLayoutEngine, WardleyTextKind, XyChartLayout,
    XyChartLayoutEngine, ZenUmlLayout, ZenUmlLayoutEngine,
};
use crate::theme::{Theme, ThemeRole};
use crate::unicode::{bidi_visual_order_line, truncate_display_width};

/// Rectangular grid of styled glyph cells plus animation markers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    width: usize,
    height: usize,
    cells: Vec<GlyphCell>,
    markers: Vec<KeyFrameMarker>,
}

impl Frame {
    /// Create a blank frame with default cell styles.
    #[must_use]
    pub fn new(width: usize, height: usize) -> Self {
        Self {
            width,
            height,
            cells: vec![GlyphCell::default(); width.saturating_mul(height)],
            markers: Vec::new(),
        }
    }

    /// Create a blank frame where every cell starts with the supplied style.
    #[must_use]
    pub fn new_styled(width: usize, height: usize, style: CellStyle) -> Self {
        Self {
            width,
            height,
            cells: vec![
                GlyphCell {
                    glyph: ' ',
                    style,
                    marker: None,
                };
                width.saturating_mul(height)
            ],
            markers: Vec::new(),
        }
    }

    /// Return frame width in cells.
    #[must_use]
    pub const fn width(&self) -> usize {
        self.width
    }

    /// Return frame height in cells.
    #[must_use]
    pub const fn height(&self) -> usize {
        self.height
    }

    /// Return cells in row-major order.
    #[must_use]
    pub fn cells(&self) -> &[GlyphCell] {
        &self.cells
    }

    /// Return keyframe markers associated with this frame.
    #[must_use]
    pub fn markers(&self) -> &[KeyFrameMarker] {
        &self.markers
    }

    /// Return a cell by coordinate.
    pub fn cell(&self, x: usize, y: usize) -> Result<&GlyphCell, FrameError> {
        let index = self.index(x, y)?;
        Ok(&self.cells[index])
    }

    /// Replace a cell by coordinate.
    pub fn set_cell(&mut self, x: usize, y: usize, cell: GlyphCell) -> Result<(), FrameError> {
        let index = self.index(x, y)?;
        self.cells[index] = cell;
        Ok(())
    }

    /// Write one glyph at a coordinate while preserving existing style/marker.
    pub fn put_glyph(&mut self, x: usize, y: usize, glyph: char) -> Result<(), FrameError> {
        let index = self.index(x, y)?;
        self.cells[index].glyph = glyph;
        Ok(())
    }

    /// Write one glyph and style at a coordinate.
    pub fn put_styled_glyph(
        &mut self,
        x: usize,
        y: usize,
        glyph: char,
        style: CellStyle,
    ) -> Result<(), FrameError> {
        let index = self.index(x, y)?;
        self.cells[index].glyph = glyph;
        self.cells[index].style = style;
        Ok(())
    }

    /// Write one line of text and return the number of glyphs written.
    pub fn write_text(
        &mut self,
        x: usize,
        y: usize,
        text: &str,
        style: CellStyle,
    ) -> Result<usize, FrameError> {
        if y >= self.height || x >= self.width {
            return Err(FrameError::OutOfBounds { x, y });
        }
        let text = bidi_visual_order_line(text);
        let mut written = 0usize;
        for (offset, glyph) in text.chars().enumerate() {
            let column = x + offset;
            if column >= self.width {
                break;
            }
            self.set_cell(
                column,
                y,
                GlyphCell {
                    glyph,
                    style: style.clone(),
                    marker: None,
                },
            )?;
            written += 1;
        }
        Ok(written)
    }

    /// Add a keyframe marker region.
    pub fn add_marker(&mut self, marker: KeyFrameMarker) {
        self.markers.push(marker);
    }

    /// Attach a marker id to one cell.
    pub fn mark_cell(
        &mut self,
        x: usize,
        y: usize,
        marker_id: impl Into<String>,
    ) -> Result<(), FrameError> {
        let index = self.index(x, y)?;
        self.cells[index].marker = Some(marker_id.into());
        Ok(())
    }

    fn index(&self, x: usize, y: usize) -> Result<usize, FrameError> {
        if x >= self.width || y >= self.height {
            return Err(FrameError::OutOfBounds { x, y });
        }
        Ok(y * self.width + x)
    }

    /// Return frame glyphs as one string per row.
    #[must_use]
    pub fn to_lines(&self) -> Vec<String> {
        if self.width == 0 {
            return vec![String::new(); self.height];
        }
        self.cells
            .chunks(self.width)
            .map(|row| row.iter().map(|cell| cell.glyph).collect())
            .collect()
    }

    /// Return a copy padded to at least `min_width` cells.
    #[must_use]
    pub fn with_min_width(&self, min_width: usize) -> Self {
        if min_width <= self.width {
            return self.clone();
        }
        let style = self
            .cells
            .first()
            .map(|cell| cell.style.clone())
            .unwrap_or_default();
        let mut frame = Self::new_styled(min_width, self.height, style);
        for y in 0..self.height {
            for x in 0..self.width {
                let source = y * self.width + x;
                let target = y * min_width + x;
                frame.cells[target] = self.cells[source].clone();
            }
        }
        frame.markers = self.markers.clone();
        frame
    }
}

/// One cell in a frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GlyphCell {
    /// Display glyph.
    pub glyph: char,
    /// Style applied to the glyph.
    pub style: CellStyle,
    /// Optional marker id attached to this cell.
    pub marker: Option<String>,
}

impl Default for GlyphCell {
    fn default() -> Self {
        Self {
            glyph: ' ',
            style: CellStyle::default(),
            marker: None,
        }
    }
}

/// Style metadata for a frame cell.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct CellStyle {
    /// Optional foreground color.
    pub foreground: Option<Color>,
    /// Optional background color.
    pub background: Option<Color>,
    /// Whether the glyph should be rendered bold.
    pub bold: bool,
    /// Whether the glyph should be rendered italic.
    pub italic: bool,
    /// Whether the glyph should be rendered underlined.
    pub underline: bool,
}

/// Cell color reference.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Color {
    /// ANSI 8-bit color index.
    Ansi(u8),
    /// Explicit RGB color.
    Rgb {
        /// Red channel.
        red: u8,
        /// Green channel.
        green: u8,
        /// Blue channel.
        blue: u8,
    },
    /// Theme role or named color reference.
    Theme(String),
}

/// Marker region emitted into animation frames.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyFrameMarker {
    /// Stable marker id.
    pub id: String,
    /// Marker lifecycle kind.
    pub kind: KeyFrameMarkerKind,
    /// Cell region covered by this marker.
    pub region: FrameRegion,
}

/// Marker lifecycle kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyFrameMarkerKind {
    /// Region enters the active animation set.
    Enter,
    /// Region is currently active.
    Active,
    /// Region exits the active animation set.
    Exit,
    /// Region remains visible without emphasis.
    Hold,
}

/// Rectangular region in frame coordinates.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameRegion {
    /// Left cell coordinate.
    pub x: usize,
    /// Top cell coordinate.
    pub y: usize,
    /// Region width in cells.
    pub width: usize,
    /// Region height in cells.
    pub height: usize,
}

/// Error returned by frame coordinate operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrameError {
    /// Coordinate is outside the frame.
    OutOfBounds {
        /// X coordinate.
        x: usize,
        /// Y coordinate.
        y: usize,
    },
}

/// Glyph set used for diagram drawing.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum Charset {
    /// ASCII-only glyphs.
    #[default]
    Ascii,
    /// Unicode box-drawing and block glyphs.
    Unicode,
}

/// Concrete glyph palette for boxes, edges, arrows, and fills.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GlyphPalette {
    /// Horizontal edge glyph.
    pub horizontal: char,
    /// Vertical edge glyph.
    pub vertical: char,
    /// Top-left corner glyph.
    pub top_left: char,
    /// Top-right corner glyph.
    pub top_right: char,
    /// Bottom-left corner glyph.
    pub bottom_left: char,
    /// Bottom-right corner glyph.
    pub bottom_right: char,
    /// Crossing/intersection glyph.
    pub crossing: char,
    /// Left arrow glyph.
    pub arrow_left: char,
    /// Right arrow glyph.
    pub arrow_right: char,
    /// Up arrow glyph.
    pub arrow_up: char,
    /// Down arrow glyph.
    pub arrow_down: char,
    /// Filled block glyph.
    pub block: char,
}

impl GlyphPalette {
    /// Return the ASCII glyph palette.
    #[must_use]
    pub const fn ascii() -> Self {
        Self {
            horizontal: '-',
            vertical: '|',
            top_left: '+',
            top_right: '+',
            bottom_left: '+',
            bottom_right: '+',
            crossing: '+',
            arrow_left: '<',
            arrow_right: '>',
            arrow_up: '^',
            arrow_down: 'v',
            block: '#',
        }
    }

    /// Return the Unicode glyph palette.
    #[must_use]
    pub const fn unicode() -> Self {
        Self {
            horizontal: '─',
            vertical: '│',
            top_left: '┌',
            top_right: '┐',
            bottom_left: '└',
            bottom_right: '┘',
            crossing: '┼',
            arrow_left: '◀',
            arrow_right: '▶',
            arrow_up: '▲',
            arrow_down: '▼',
            block: '█',
        }
    }

    /// Return the palette for a charset.
    #[must_use]
    pub const fn for_charset(charset: Charset) -> Self {
        match charset {
            Charset::Ascii => Self::ascii(),
            Charset::Unicode => Self::unicode(),
        }
    }
}

impl Default for GlyphPalette {
    fn default() -> Self {
        Self::ascii()
    }
}

/// Renderer that converts parsed diagrams into static frames.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct StaticFrameRenderer {
    flow: FlowLayoutEngine,
    sequence: SequenceLayoutEngine,
    state: StateLayoutEngine,
    class: ClassLayoutEngine,
    er: ErLayoutEngine,
    gantt: GanttLayoutEngine,
    pie: PieLayoutEngine,
    quadrant: QuadrantLayoutEngine,
    zenuml: ZenUmlLayoutEngine,
    sankey: SankeyLayoutEngine,
    xy_chart: XyChartLayoutEngine,
    block: BlockLayoutEngine,
    packet: PacketLayoutEngine,
    kanban: KanbanLayoutEngine,
    architecture: ArchitectureLayoutEngine,
    radar: RadarLayoutEngine,
    event_modeling: EventModelingLayoutEngine,
    treemap: TreemapLayoutEngine,
    venn: VennLayoutEngine,
    ishikawa: IshikawaLayoutEngine,
    wardley: WardleyLayoutEngine,
    tree_view: TreeViewLayoutEngine,
    mindmap: MindmapLayoutEngine,
    journey: JourneyLayoutEngine,
    gitgraph: GitGraphLayoutEngine,
    timeline: TimelineLayoutEngine,
    requirement: RequirementLayoutEngine,
    c4: C4LayoutEngine,
    palette: GlyphPalette,
    theme: Theme,
}

impl StaticFrameRenderer {
    /// Create a renderer with explicit engines for the three original roots.
    #[must_use]
    pub const fn new(
        flow: FlowLayoutEngine,
        sequence: SequenceLayoutEngine,
        state: StateLayoutEngine,
    ) -> Self {
        Self {
            flow,
            sequence,
            state,
            class: ClassLayoutEngine::default_values(),
            er: ErLayoutEngine::default_values(),
            gantt: GanttLayoutEngine::default_values(),
            pie: PieLayoutEngine::default_values(),
            quadrant: QuadrantLayoutEngine::default_values(),
            zenuml: ZenUmlLayoutEngine::default_values(),
            sankey: SankeyLayoutEngine::default_values(),
            xy_chart: XyChartLayoutEngine::default_values(),
            block: BlockLayoutEngine::default_values(),
            packet: PacketLayoutEngine::default_values(),
            kanban: KanbanLayoutEngine::default_values(),
            architecture: ArchitectureLayoutEngine::default_values(),
            radar: RadarLayoutEngine::default_values(),
            event_modeling: EventModelingLayoutEngine::default_values(),
            treemap: TreemapLayoutEngine::default_values(),
            venn: VennLayoutEngine::default_values(),
            ishikawa: IshikawaLayoutEngine::default_values(),
            wardley: WardleyLayoutEngine::default_values(),
            tree_view: TreeViewLayoutEngine::default_values(),
            mindmap: MindmapLayoutEngine::default_values(),
            journey: JourneyLayoutEngine::default_values(),
            gitgraph: GitGraphLayoutEngine::default_values(),
            timeline: TimelineLayoutEngine::default_values(),
            requirement: RequirementLayoutEngine::default_values(),
            c4: C4LayoutEngine::default_values(),
            palette: GlyphPalette::ascii(),
            theme: Theme::default_theme(),
        }
    }

    /// Create a renderer with explicit engines and glyph palette.
    #[must_use]
    pub const fn with_palette(
        flow: FlowLayoutEngine,
        sequence: SequenceLayoutEngine,
        state: StateLayoutEngine,
        palette: GlyphPalette,
    ) -> Self {
        Self {
            flow,
            sequence,
            state,
            class: ClassLayoutEngine::default_values(),
            er: ErLayoutEngine::default_values(),
            gantt: GanttLayoutEngine::default_values(),
            pie: PieLayoutEngine::default_values(),
            quadrant: QuadrantLayoutEngine::default_values(),
            zenuml: ZenUmlLayoutEngine::default_values(),
            sankey: SankeyLayoutEngine::default_values(),
            xy_chart: XyChartLayoutEngine::default_values(),
            block: BlockLayoutEngine::default_values(),
            packet: PacketLayoutEngine::default_values(),
            kanban: KanbanLayoutEngine::default_values(),
            architecture: ArchitectureLayoutEngine::default_values(),
            radar: RadarLayoutEngine::default_values(),
            event_modeling: EventModelingLayoutEngine::default_values(),
            treemap: TreemapLayoutEngine::default_values(),
            venn: VennLayoutEngine::default_values(),
            ishikawa: IshikawaLayoutEngine::default_values(),
            wardley: WardleyLayoutEngine::default_values(),
            tree_view: TreeViewLayoutEngine::default_values(),
            mindmap: MindmapLayoutEngine::default_values(),
            journey: JourneyLayoutEngine::default_values(),
            gitgraph: GitGraphLayoutEngine::default_values(),
            timeline: TimelineLayoutEngine::default_values(),
            requirement: RequirementLayoutEngine::default_values(),
            c4: C4LayoutEngine::default_values(),
            palette,
            theme: Theme::default_theme(),
        }
    }

    /// Create a renderer with explicit engines and theme.
    #[must_use]
    pub const fn new_with_theme(
        flow: FlowLayoutEngine,
        sequence: SequenceLayoutEngine,
        state: StateLayoutEngine,
        theme: Theme,
    ) -> Self {
        Self {
            flow,
            sequence,
            state,
            class: ClassLayoutEngine::default_values(),
            er: ErLayoutEngine::default_values(),
            gantt: GanttLayoutEngine::default_values(),
            pie: PieLayoutEngine::default_values(),
            quadrant: QuadrantLayoutEngine::default_values(),
            zenuml: ZenUmlLayoutEngine::default_values(),
            sankey: SankeyLayoutEngine::default_values(),
            xy_chart: XyChartLayoutEngine::default_values(),
            block: BlockLayoutEngine::default_values(),
            packet: PacketLayoutEngine::default_values(),
            kanban: KanbanLayoutEngine::default_values(),
            architecture: ArchitectureLayoutEngine::default_values(),
            radar: RadarLayoutEngine::default_values(),
            event_modeling: EventModelingLayoutEngine::default_values(),
            treemap: TreemapLayoutEngine::default_values(),
            venn: VennLayoutEngine::default_values(),
            ishikawa: IshikawaLayoutEngine::default_values(),
            wardley: WardleyLayoutEngine::default_values(),
            tree_view: TreeViewLayoutEngine::default_values(),
            mindmap: MindmapLayoutEngine::default_values(),
            journey: JourneyLayoutEngine::default_values(),
            gitgraph: GitGraphLayoutEngine::default_values(),
            timeline: TimelineLayoutEngine::default_values(),
            requirement: RequirementLayoutEngine::default_values(),
            c4: C4LayoutEngine::default_values(),
            palette: GlyphPalette::for_charset(theme.charset),
            theme,
        }
    }

    /// Return a copy using a different glyph palette.
    #[must_use]
    pub const fn with_glyph_palette(mut self, palette: GlyphPalette) -> Self {
        self.palette = palette;
        self
    }

    /// Return a copy using the palette for a charset.
    #[must_use]
    pub const fn with_glyph_charset(self, charset: Charset) -> Self {
        self.with_glyph_palette(GlyphPalette::for_charset(charset))
    }

    /// Return a copy using a different theme and matching glyph palette.
    #[must_use]
    pub const fn with_theme(mut self, theme: Theme) -> Self {
        self.palette = GlyphPalette::for_charset(theme.charset);
        self.theme = theme;
        self
    }

    /// Return a copy using a different flowchart layout config.
    #[must_use]
    pub const fn with_flow_layout_config(mut self, config: FlowLayoutConfig) -> Self {
        self.flow = FlowLayoutEngine::new(config);
        self
    }

    /// Return the renderer glyph palette.
    #[must_use]
    pub const fn palette(&self) -> GlyphPalette {
        self.palette
    }

    /// Return the renderer theme.
    #[must_use]
    pub const fn theme(&self) -> Theme {
        self.theme
    }

    /// Render any supported diagram kind.
    #[must_use]
    pub fn render_diagram(&self, diagram: &Diagram) -> Frame {
        match &diagram.kind {
            DiagramKind::Flowchart(ast) => self.render_flowchart(ast),
            DiagramKind::Sequence(ast) => self.render_sequence(ast),
            DiagramKind::State(ast) => self.render_state(ast),
            DiagramKind::Class(ast) => self.render_class(ast),
            DiagramKind::Er(ast) => self.render_er(ast),
            DiagramKind::Gantt(ast) => self.render_gantt(ast),
            DiagramKind::Pie(ast) => self.render_pie(ast),
            DiagramKind::Quadrant(ast) => self.render_quadrant(ast),
            DiagramKind::ZenUml(ast) => self.render_zenuml(ast),
            DiagramKind::Sankey(ast) => self.render_sankey(ast),
            DiagramKind::XyChart(ast) => self.render_xy_chart(ast),
            DiagramKind::Block(ast) => self.render_block_diagram(ast),
            DiagramKind::Packet(ast) => self.render_packet(ast),
            DiagramKind::Kanban(ast) => self.render_kanban(ast),
            DiagramKind::Architecture(ast) => self.render_architecture(ast),
            DiagramKind::Radar(ast) => self.render_radar(ast),
            DiagramKind::EventModeling(ast) => self.render_event_modeling(ast),
            DiagramKind::Treemap(ast) => self.render_treemap(ast),
            DiagramKind::Venn(ast) => self.render_venn(ast),
            DiagramKind::Ishikawa(ast) => self.render_ishikawa(ast),
            DiagramKind::Wardley(ast) => self.render_wardley(ast),
            DiagramKind::TreeView(ast) => self.render_tree_view(ast),
            DiagramKind::Mindmap(ast) => self.render_mindmap(ast),
            DiagramKind::Journey(ast) => self.render_journey(ast),
            DiagramKind::GitGraph(ast) => self.render_gitgraph(ast),
            DiagramKind::Timeline(ast) => self.render_timeline(ast),
            DiagramKind::Requirement(ast) => self.render_requirement(ast),
            DiagramKind::C4(ast) => self.render_c4(ast),
            DiagramKind::Cynefin(ast) => self.render_cynefin(ast),
            DiagramKind::Railroad(ast) => self.render_railroad(ast),
            DiagramKind::Swimlanes(ast) => self.render_swimlanes(ast),
        }
    }

    /// Render a flowchart diagram.
    #[must_use]
    pub fn render_flowchart(&self, ast: &FlowchartAst) -> Frame {
        render_flow_layout(&self.flow.layout(ast), self.palette, self.theme)
    }

    /// Render a sequence diagram.
    #[must_use]
    pub fn render_sequence(&self, ast: &SequenceAst) -> Frame {
        render_sequence_layout(&self.sequence.layout(ast), self.palette, self.theme)
    }

    /// Render a state diagram.
    #[must_use]
    pub fn render_state(&self, ast: &StateAst) -> Frame {
        render_flow_layout(&self.state.layout(ast).graph, self.palette, self.theme)
    }

    /// Render a class diagram.
    #[must_use]
    pub fn render_class(&self, ast: &ClassAst) -> Frame {
        render_class_layout(&self.class.layout(ast), self.palette, self.theme)
    }

    /// Render an ER diagram.
    #[must_use]
    pub fn render_er(&self, ast: &ErAst) -> Frame {
        render_class_layout(&self.er.layout(ast), self.palette, self.theme)
    }

    /// Render a requirement diagram.
    #[must_use]
    pub fn render_requirement(&self, ast: &RequirementAst) -> Frame {
        render_requirement_layout(&self.requirement.layout(ast), self.palette, self.theme)
    }

    /// Render a C4 diagram.
    #[must_use]
    pub fn render_c4(&self, ast: &C4Ast) -> Frame {
        render_c4_layout(&self.c4.layout(ast), self.palette, self.theme)
    }

    /// Render a Cynefin framework diagram.
    #[must_use]
    pub fn render_cynefin(&self, ast: &CynefinAst) -> Frame {
        render_cynefin_diagram(ast, self.palette, self.theme)
    }

    /// Render a railroad diagram.
    #[must_use]
    pub fn render_railroad(&self, ast: &RailroadAst) -> Frame {
        render_railroad_diagram(ast, self.palette, self.theme)
    }

    /// Render a swimlanes diagram.
    #[must_use]
    pub fn render_swimlanes(&self, ast: &SwimlanesAst) -> Frame {
        render_flow_layout(&self.flow.layout(&ast.graph), self.palette, self.theme)
    }

    /// Render a Gantt diagram.
    #[must_use]
    pub fn render_gantt(&self, ast: &GanttAst) -> Frame {
        render_gantt_layout(&self.gantt.layout(ast), self.palette, self.theme)
    }

    /// Render a pie chart with all slices visible.
    #[must_use]
    pub fn render_pie(&self, ast: &PieAst) -> Frame {
        self.render_pie_progress(ast, ast.slices.len())
    }

    /// Render a pie chart with only the first `visible_slices` slices visible.
    #[must_use]
    pub fn render_pie_progress(&self, ast: &PieAst, visible_slices: usize) -> Frame {
        render_pie_layout(
            &self.pie.layout(ast),
            self.palette,
            self.theme,
            visible_slices,
        )
    }

    /// Render a quadrant chart.
    #[must_use]
    pub fn render_quadrant(&self, ast: &QuadrantAst) -> Frame {
        render_quadrant_layout(&self.quadrant.layout(ast), self.palette, self.theme)
    }

    /// Render a ZenUML diagram.
    #[must_use]
    pub fn render_zenuml(&self, ast: &ZenUmlAst) -> Frame {
        render_zenuml_layout(&self.zenuml.layout(ast), self.palette, self.theme)
    }

    /// Render a Sankey diagram.
    #[must_use]
    pub fn render_sankey(&self, ast: &SankeyAst) -> Frame {
        render_sankey_layout(&self.sankey.layout(ast), self.palette, self.theme)
    }

    /// Render an XY chart.
    #[must_use]
    pub fn render_xy_chart(&self, ast: &XyChartAst) -> Frame {
        render_xy_chart_layout(&self.xy_chart.layout(ast), self.palette, self.theme)
    }

    /// Render a block diagram.
    #[must_use]
    pub fn render_block_diagram(&self, ast: &BlockDiagramAst) -> Frame {
        render_block_layout(&self.block.layout(ast), self.palette, self.theme)
    }

    /// Render a packet diagram.
    #[must_use]
    pub fn render_packet(&self, ast: &PacketAst) -> Frame {
        render_packet_layout(&self.packet.layout(ast), self.palette, self.theme)
    }

    /// Render a Kanban diagram.
    #[must_use]
    pub fn render_kanban(&self, ast: &KanbanAst) -> Frame {
        render_kanban_layout(&self.kanban.layout(ast), self.palette, self.theme)
    }

    /// Render an architecture diagram.
    #[must_use]
    pub fn render_architecture(&self, ast: &crate::ast::ArchitectureAst) -> Frame {
        render_architecture_layout(&self.architecture.layout(ast), self.palette, self.theme)
    }

    /// Render a radar chart.
    #[must_use]
    pub fn render_radar(&self, ast: &RadarAst) -> Frame {
        render_radar_layout(&self.radar.layout(ast), self.palette, self.theme)
    }

    /// Render an event modeling diagram.
    #[must_use]
    pub fn render_event_modeling(&self, ast: &EventModelingAst) -> Frame {
        render_event_modeling_layout(&self.event_modeling.layout(ast), self.palette, self.theme)
    }

    /// Render a treemap diagram.
    #[must_use]
    pub fn render_treemap(&self, ast: &TreemapAst) -> Frame {
        render_treemap_layout(&self.treemap.layout(ast), self.palette, self.theme)
    }

    /// Render a Venn diagram.
    #[must_use]
    pub fn render_venn(&self, ast: &VennAst) -> Frame {
        render_venn_layout(&self.venn.layout(ast), self.palette, self.theme)
    }

    /// Render an Ishikawa diagram.
    #[must_use]
    pub fn render_ishikawa(&self, ast: &IshikawaAst) -> Frame {
        render_ishikawa_layout(&self.ishikawa.layout(ast), self.palette, self.theme)
    }

    /// Render a Wardley map.
    #[must_use]
    pub fn render_wardley(&self, ast: &WardleyAst) -> Frame {
        render_wardley_layout(&self.wardley.layout(ast), self.palette, self.theme)
    }

    /// Render a tree view diagram.
    #[must_use]
    pub fn render_tree_view(&self, ast: &TreeViewAst) -> Frame {
        render_tree_view_layout(&self.tree_view.layout(ast), self.theme)
    }

    /// Render a mindmap with all depths visible.
    #[must_use]
    pub fn render_mindmap(&self, ast: &MindmapAst) -> Frame {
        self.render_mindmap_progress(ast, usize::MAX)
    }

    /// Render a mindmap with nodes visible through `visible_depth`.
    #[must_use]
    pub fn render_mindmap_progress(&self, ast: &MindmapAst, visible_depth: usize) -> Frame {
        render_mindmap_layout(
            &self.mindmap.layout(ast),
            self.palette,
            self.theme,
            visible_depth,
        )
    }

    /// Render a journey diagram with all tasks visible.
    #[must_use]
    pub fn render_journey(&self, ast: &JourneyAst) -> Frame {
        self.render_journey_progress(ast, ast.tasks.len())
    }

    /// Render a journey diagram with the first `visible_tasks` tasks visible.
    #[must_use]
    pub fn render_journey_progress(&self, ast: &JourneyAst, visible_tasks: usize) -> Frame {
        render_journey_layout(
            &self.journey.layout(ast),
            self.palette,
            self.theme,
            visible_tasks,
        )
    }

    /// Render a git graph with all commits visible.
    #[must_use]
    pub fn render_gitgraph(&self, ast: &GitGraphAst) -> Frame {
        self.render_gitgraph_progress(
            ast,
            ast.commits.len() + ast.merges.len() + ast.cherry_picks.len(),
        )
    }

    /// Render a git graph with the first `visible_commits` commits visible.
    #[must_use]
    pub fn render_gitgraph_progress(&self, ast: &GitGraphAst, visible_commits: usize) -> Frame {
        render_gitgraph_layout(
            &self.gitgraph.layout(ast),
            self.palette,
            self.theme,
            visible_commits,
        )
    }

    /// Render a timeline diagram with all periods visible.
    #[must_use]
    pub fn render_timeline(&self, ast: &TimelineAst) -> Frame {
        self.render_timeline_progress(ast, ast.periods.len())
    }

    /// Render a timeline diagram with the first `visible_periods` periods visible.
    #[must_use]
    pub fn render_timeline_progress(&self, ast: &TimelineAst, visible_periods: usize) -> Frame {
        render_timeline_layout(
            &self.timeline.layout(ast),
            self.palette,
            self.theme,
            visible_periods,
        )
    }
}

fn render_flow_layout(layout: &FlowLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    for subgraph in &layout.subgraphs {
        draw_flow_subgraph(
            &mut frame,
            subgraph,
            palette,
            node_style.clone(),
            text_style.clone(),
        );
    }
    for edge in &layout.edges {
        if edge.points.len() >= 2 {
            draw_flow_edge(&mut frame, edge, palette, edge_style.clone());
        }
    }
    for node in &layout.nodes {
        draw_flow_node(
            &mut frame,
            node,
            palette,
            node_style.clone(),
            text_style.clone(),
        );
    }
    frame
}

fn draw_flow_node(
    frame: &mut Frame,
    node: &PositionedFlowNode,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
) {
    draw_box(frame, node.rect, palette, node_style.clone());
    decorate_flow_shape(frame, node, node_style);
    write_centered(frame, node.rect, &node.label, text_style);
}

fn decorate_flow_shape(frame: &mut Frame, node: &PositionedFlowNode, style: CellStyle) {
    let rect = node.rect;
    let left = rect.origin.x;
    let right = rect.right().saturating_sub(1);
    let top = rect.origin.y;
    let bottom = rect.bottom().saturating_sub(1);
    let middle_y = rect.center().y;
    match &node.shape {
        FlowShape::Rectangle | FlowShape::Named(_) => {}
        FlowShape::Round | FlowShape::Circle => {
            put_safe(frame, left, middle_y, '(', style.clone());
            put_safe(frame, right, middle_y, ')', style);
        }
        FlowShape::Stadium => {
            put_safe(frame, left, top + 1, '(', style.clone());
            put_safe(frame, left, bottom.saturating_sub(1), '(', style.clone());
            put_safe(frame, right, top + 1, ')', style.clone());
            put_safe(frame, right, bottom.saturating_sub(1), ')', style);
        }
        FlowShape::Subroutine => {
            draw_vertical(frame, left + 1, top, bottom, '|', style.clone());
            draw_vertical(frame, right.saturating_sub(1), top, bottom, '|', style);
        }
        FlowShape::Cylinder => {
            put_safe(frame, left + 1, top, '(', style.clone());
            put_safe(frame, right.saturating_sub(1), top, ')', style.clone());
            put_safe(frame, left + 1, bottom, '(', style.clone());
            put_safe(frame, right.saturating_sub(1), bottom, ')', style);
        }
        FlowShape::Asymmetric => {
            put_safe(frame, left, middle_y, '>', style.clone());
            put_safe(frame, right, middle_y, ']', style);
        }
        FlowShape::Rhombus => {
            put_safe(frame, left, middle_y, '<', style.clone());
            put_safe(frame, right, middle_y, '>', style);
        }
        FlowShape::Hexagon => {
            put_safe(frame, left, top + 1, '<', style.clone());
            put_safe(frame, right, top + 1, '>', style.clone());
            put_safe(frame, left, bottom.saturating_sub(1), '<', style.clone());
            put_safe(frame, right, bottom.saturating_sub(1), '>', style);
        }
        FlowShape::Parallelogram => {
            put_safe(frame, left, top, '/', style.clone());
            put_safe(frame, right, bottom, '/', style);
        }
        FlowShape::ParallelogramAlt => {
            put_safe(frame, right, top, '\\', style.clone());
            put_safe(frame, left, bottom, '\\', style);
        }
        FlowShape::Trapezoid => {
            put_safe(frame, left, top, '/', style.clone());
            put_safe(frame, right, top, '\\', style);
        }
        FlowShape::TrapezoidAlt => {
            put_safe(frame, left, bottom, '\\', style.clone());
            put_safe(frame, right, bottom, '/', style);
        }
        FlowShape::DoubleCircle => {
            put_safe(frame, left, middle_y, '(', style.clone());
            put_safe(frame, left + 1, middle_y, '(', style.clone());
            put_safe(frame, right.saturating_sub(1), middle_y, ')', style.clone());
            put_safe(frame, right, middle_y, ')', style);
        }
    }
}

fn draw_flow_subgraph(
    frame: &mut Frame,
    subgraph: &PositionedFlowSubgraph,
    palette: GlyphPalette,
    box_style: CellStyle,
    text_style: CellStyle,
) {
    draw_box(frame, subgraph.rect, palette, box_style);
    let label_width = subgraph.label.chars().count() as i32;
    let x = subgraph.rect.origin.x + (subgraph.rect.size.width - label_width).max(0) / 2;
    write_text_safe(
        frame,
        x,
        subgraph.rect.origin.y + 1,
        &subgraph.label,
        text_style,
    );
}

fn draw_flow_edge(
    frame: &mut Frame,
    edge: &PositionedFlowEdge,
    palette: GlyphPalette,
    edge_style: CellStyle,
) {
    draw_polyline(frame, &edge.points, palette, edge_style.clone());
    if let Some(first) = edge.points.first().copied()
        && let Some(glyph) = start_arrowhead_for_points(edge.arrow_start, &edge.points, palette)
    {
        put_safe(frame, first.x, first.y, glyph, edge_style.clone());
    }
    if let Some(last) = edge.points.last().copied()
        && let Some(glyph) = end_arrowhead_for_points(edge.arrow_end, &edge.points, palette)
    {
        put_safe(frame, last.x, last.y, glyph, edge_style);
    }
}

fn render_sequence_layout(layout: &SequenceLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    for participant in &layout.participants {
        draw_box(&mut frame, participant.header, palette, node_style.clone());
        write_centered(
            &mut frame,
            participant.header,
            &participant.label,
            text_style.clone(),
        );
        draw_vertical(
            &mut frame,
            participant.lane_x,
            participant.header.bottom(),
            layout.size.height,
            palette.vertical,
            muted_style.clone(),
        );
    }
    for sequence_box in &layout.boxes {
        draw_sequence_box(
            &mut frame,
            sequence_box,
            palette,
            muted_style.clone(),
            text_style.clone(),
        );
    }
    for control in &layout.controls {
        draw_box(&mut frame, control.rect, palette, muted_style.clone());
        if let Some(label) = sequence_control_label(control.kind, control.label.as_deref()) {
            write_text_safe(
                &mut frame,
                control.rect.origin.x + 1,
                control.y,
                &label,
                text_style.clone(),
            );
        }
    }
    for note in &layout.notes {
        draw_sequence_note(
            &mut frame,
            note,
            palette,
            node_style.clone(),
            text_style.clone(),
        );
    }
    for activation in &layout.activations {
        draw_sequence_activation(&mut frame, activation, palette, node_style.clone());
    }
    for message in &layout.messages {
        draw_sequence_message(
            &mut frame,
            message,
            palette,
            edge_style.clone(),
            text_style.clone(),
        );
    }
    for destroy in &layout.destroys {
        draw_sequence_destroy(&mut frame, destroy, text_style.clone());
    }
    frame
}

fn render_zenuml_layout(layout: &ZenUmlLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_text_safe(&mut frame, 0, 0, title, text_style.clone());
    }
    for participant in &layout.participants {
        draw_box(&mut frame, participant.header, palette, node_style.clone());
        if let Some(annotator) = &participant.annotator {
            write_centered(
                &mut frame,
                Rect {
                    origin: Point {
                        x: participant.header.origin.x,
                        y: participant.header.origin.y + 1,
                    },
                    size: Size {
                        width: participant.header.size.width,
                        height: 1,
                    },
                },
                &format!("@{annotator}"),
                muted_style.clone(),
            );
            write_text_safe(
                &mut frame,
                participant.header.origin.x + 1,
                participant.header.origin.y + 2,
                &participant.label,
                text_style.clone(),
            );
        } else {
            write_centered(
                &mut frame,
                participant.header,
                &participant.label,
                text_style.clone(),
            );
        }
        draw_vertical(
            &mut frame,
            participant.lane_x,
            participant.header.bottom(),
            layout.size.height,
            palette.vertical,
            muted_style.clone(),
        );
    }
    for fragment in &layout.fragments {
        write_text_safe(
            &mut frame,
            i32::from(fragment.depth) * 2,
            fragment.y,
            &format!("[{}]", fragment.label),
            muted_style.clone(),
        );
    }
    for message in &layout.messages {
        draw_zenuml_message(
            &mut frame,
            message,
            palette,
            edge_style.clone(),
            text_style.clone(),
        );
    }
    frame
}

fn draw_zenuml_message(
    frame: &mut Frame,
    message: &PositionedZenUmlMessage,
    palette: GlyphPalette,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    draw_polyline(frame, &message.points, palette, edge_style.clone());
    if let Some(last) = message.points.last() {
        put_safe(
            frame,
            last.x,
            last.y,
            zenuml_message_arrowhead(message, palette),
            edge_style,
        );
    }
    let Some((first, last)) = message.points.first().zip(message.points.last()) else {
        return;
    };
    let x = first.x.min(last.x) + 1 + i32::from(message.depth) * 2;
    let label = match message.kind {
        ZenUmlMessageKind::Create => format!("new {}", message.to),
        ZenUmlMessageKind::Reply => {
            if message.label.is_empty() {
                "return".to_owned()
            } else {
                format!("return {}", message.label)
            }
        }
        ZenUmlMessageKind::Sync | ZenUmlMessageKind::Async => message.label.clone(),
    };
    if !label.is_empty() {
        write_text_safe(frame, x, message.y.saturating_sub(1), &label, text_style);
    }
}

fn zenuml_message_arrowhead(message: &PositionedZenUmlMessage, palette: GlyphPalette) -> char {
    match message.kind {
        ZenUmlMessageKind::Reply => '<',
        ZenUmlMessageKind::Create => 'o',
        ZenUmlMessageKind::Sync | ZenUmlMessageKind::Async => {
            arrowhead_for_points(&message.points, palette)
        }
    }
}

fn render_sankey_layout(layout: &SankeyLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    for link in &layout.links {
        draw_sankey_link(&mut frame, link, palette, edge_style.clone());
    }
    for node in &layout.nodes {
        draw_box(&mut frame, node.rect, palette, node_style.clone());
        write_centered(&mut frame, node.rect, &node.label, text_style.clone());
    }
    for link in &layout.links {
        draw_sankey_link_label(&mut frame, link, text_style.clone());
    }
    frame
}

fn draw_sankey_link(
    frame: &mut Frame,
    link: &PositionedSankeyLink,
    palette: GlyphPalette,
    edge_style: CellStyle,
) {
    draw_polyline(frame, &link.points, palette, edge_style.clone());
    if let Some(last) = link.points.last() {
        put_safe(
            frame,
            last.x,
            last.y,
            arrowhead_for_points(&link.points, palette),
            edge_style,
        );
    }
}

fn draw_sankey_link_label(frame: &mut Frame, link: &PositionedSankeyLink, text_style: CellStyle) {
    if let Some(point) = sankey_frame_link_label_point(link) {
        write_text_safe(frame, point.x, point.y, &link.value_text, text_style);
    }
}

fn sankey_frame_link_label_point(link: &PositionedSankeyLink) -> Option<Point> {
    let first = link.points.first()?;
    let last = link.points.last()?;
    Some(Point {
        x: (first.x + last.x) / 2 + 1,
        y: (first.y + last.y) / 2,
    })
}

fn render_xy_chart_layout(layout: &XyChartLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_text_safe(&mut frame, 0, 0, title, text_style.clone());
    }
    if let Some(y_title) = &layout.y_title {
        write_text_safe(
            &mut frame,
            0,
            layout.plot.origin.y.saturating_sub(1),
            y_title,
            text_style.clone(),
        );
    }
    draw_box(&mut frame, layout.plot, palette, node_style.clone());
    write_text_safe(
        &mut frame,
        0,
        layout.plot.origin.y,
        &layout.y_max_label,
        text_style.clone(),
    );
    write_text_safe(
        &mut frame,
        0,
        layout.plot.bottom().saturating_sub(1),
        &layout.y_min_label,
        text_style.clone(),
    );
    for series in &layout.series {
        draw_xy_chart_series(
            &mut frame,
            series,
            layout.plot,
            palette,
            edge_style.clone(),
            node_style.clone(),
        );
    }
    let x_label_y = layout.plot.bottom() + 1;
    for (index, label) in layout.x_labels.iter().enumerate() {
        let x = xy_chart_frame_label_x(layout.plot, index, layout.x_labels.len(), label);
        write_text_safe(&mut frame, x, x_label_y, label, muted_style.clone());
    }
    if let Some(x_title) = &layout.x_title {
        write_text_safe(
            &mut frame,
            layout.plot.origin.x,
            x_label_y + 1,
            x_title,
            text_style,
        );
    }
    frame
}

fn draw_xy_chart_series(
    frame: &mut Frame,
    series: &PositionedXyChartSeries,
    plot: Rect,
    palette: GlyphPalette,
    edge_style: CellStyle,
    node_style: CellStyle,
) {
    match series.kind {
        XyChartSeriesKind::Bar => {
            let baseline = plot.bottom().saturating_sub(2);
            for point in &series.points {
                draw_vertical(
                    frame,
                    point.x,
                    point.y.min(baseline),
                    point.y.max(baseline),
                    palette.block,
                    node_style.clone(),
                );
            }
        }
        XyChartSeriesKind::Line => {
            draw_polyline(frame, &series.points, palette, edge_style.clone());
            for point in &series.points {
                put_safe(frame, point.x, point.y, 'o', edge_style.clone());
            }
        }
    }
}

fn xy_chart_frame_label_x(plot: Rect, index: usize, len: usize, label: &str) -> i32 {
    let inner_width = (plot.size.width - 3).max(1);
    let x = if len <= 1 {
        plot.origin.x + 1 + inner_width / 2
    } else {
        plot.origin.x + 1 + index as i32 * inner_width / (len as i32 - 1)
    };
    (x - label.chars().count() as i32 / 2).max(0)
}

fn render_block_layout(layout: &BlockLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    for edge in &layout.edges {
        draw_block_edge(
            &mut frame,
            edge,
            palette,
            edge_style.clone(),
            text_style.clone(),
        );
    }
    for container in &layout.containers {
        draw_box(&mut frame, container.rect, palette, muted_style.clone());
        if !container.label.is_empty() {
            write_text_safe(
                &mut frame,
                container.rect.origin.x + 1,
                container.rect.origin.y,
                &container.label,
                text_style.clone(),
            );
        }
    }
    for node in &layout.nodes {
        draw_block_node(
            &mut frame,
            node,
            palette,
            node_style.clone(),
            text_style.clone(),
            edge_style.clone(),
        );
    }
    frame
}

fn draw_block_node(
    frame: &mut Frame,
    node: &PositionedBlockNode,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
    edge_style: CellStyle,
) {
    match &node.shape {
        BlockShape::Flow(shape) => {
            draw_flow_node(
                frame,
                &PositionedFlowNode {
                    id: node.id.clone(),
                    label: node.label.clone(),
                    shape: shape.clone(),
                    rect: node.rect,
                    layer: node.row,
                    order: node.column,
                },
                palette,
                node_style,
                text_style,
            );
        }
        BlockShape::Arrow(directions) => {
            draw_box(frame, node.rect, palette, node_style);
            write_centered(frame, node.rect, &node.label, text_style);
            draw_block_arrow_directions(frame, node.rect, directions, palette, edge_style);
        }
    }
}

fn draw_block_arrow_directions(
    frame: &mut Frame,
    rect: Rect,
    directions: &[crate::ast::Spanned<BlockArrowDirection>],
    palette: GlyphPalette,
    style: CellStyle,
) {
    for direction in directions {
        let center = rect.center();
        match direction.value {
            BlockArrowDirection::Left => {
                put_safe(
                    frame,
                    rect.origin.x,
                    center.y,
                    palette.arrow_left,
                    style.clone(),
                );
            }
            BlockArrowDirection::Right => {
                put_safe(
                    frame,
                    rect.right().saturating_sub(1),
                    center.y,
                    palette.arrow_right,
                    style.clone(),
                );
            }
            BlockArrowDirection::Up => {
                put_safe(
                    frame,
                    center.x,
                    rect.origin.y,
                    palette.arrow_up,
                    style.clone(),
                );
            }
            BlockArrowDirection::Down => {
                put_safe(
                    frame,
                    center.x,
                    rect.bottom().saturating_sub(1),
                    palette.arrow_down,
                    style.clone(),
                );
            }
            BlockArrowDirection::X => {
                draw_horizontal(
                    frame,
                    rect.origin.x,
                    rect.right().saturating_sub(1),
                    center.y,
                    palette.horizontal,
                    style.clone(),
                );
                put_safe(
                    frame,
                    rect.origin.x,
                    center.y,
                    palette.arrow_left,
                    style.clone(),
                );
                put_safe(
                    frame,
                    rect.right().saturating_sub(1),
                    center.y,
                    palette.arrow_right,
                    style.clone(),
                );
            }
            BlockArrowDirection::Y => {
                draw_vertical(
                    frame,
                    center.x,
                    rect.origin.y,
                    rect.bottom().saturating_sub(1),
                    palette.vertical,
                    style.clone(),
                );
                put_safe(
                    frame,
                    center.x,
                    rect.origin.y,
                    palette.arrow_up,
                    style.clone(),
                );
                put_safe(
                    frame,
                    center.x,
                    rect.bottom().saturating_sub(1),
                    palette.arrow_down,
                    style.clone(),
                );
            }
        }
    }
}

fn draw_block_edge(
    frame: &mut Frame,
    edge: &PositionedBlockEdge,
    palette: GlyphPalette,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    draw_polyline(frame, &edge.points, palette, edge_style.clone());
    if let Some(first) = edge.points.first()
        && let Some(glyph) = start_arrowhead_for_points(edge.arrow_start, &edge.points, palette)
    {
        put_safe(frame, first.x, first.y, glyph, edge_style.clone());
    }
    if let Some(last) = edge.points.last()
        && let Some(glyph) = end_arrowhead_for_points(edge.arrow_end, &edge.points, palette)
    {
        put_safe(frame, last.x, last.y, glyph, edge_style);
    }
    if let Some(label) = &edge.label
        && let Some(point) = block_frame_edge_label_point(edge)
    {
        write_text_safe(frame, point.x, point.y, label, text_style);
    }
}

fn block_frame_edge_label_point(edge: &PositionedBlockEdge) -> Option<Point> {
    let first = edge.points.first()?;
    let last = edge.points.last()?;
    Some(Point {
        x: (first.x + last.x) / 2 + 1,
        y: (first.y + last.y) / 2,
    })
}

fn render_packet_layout(layout: &PacketLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_text_safe(&mut frame, 0, 0, title, text_style.clone());
    }
    for row in &layout.rows {
        let first = row.first_bit.to_string();
        let last = row.last_bit.to_string();
        write_text_safe(&mut frame, 0, row.label_y, &first, muted_style.clone());
        write_text_safe(
            &mut frame,
            layout
                .size
                .width
                .saturating_sub(last.chars().count() as i32 + 1),
            row.label_y,
            &last,
            muted_style.clone(),
        );
    }
    for field in &layout.fields {
        draw_packet_field(
            &mut frame,
            field,
            palette,
            node_style.clone(),
            text_style.clone(),
            muted_style.clone(),
        );
    }
    frame
}

fn draw_packet_field(
    frame: &mut Frame,
    field: &PositionedPacketField,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
    muted_style: CellStyle,
) {
    draw_box(frame, field.rect, palette, node_style);
    write_centered(frame, field.rect, &field.label, text_style);
    write_text_safe(
        frame,
        field.rect.origin.x + 1,
        field.rect.bottom(),
        &field.range_label,
        muted_style,
    );
}

fn render_kanban_layout(layout: &KanbanLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    for column in &layout.columns {
        draw_box(&mut frame, column.rect, palette, node_style.clone());
        write_centered(&mut frame, column.header, &column.title, text_style.clone());
        draw_horizontal(
            &mut frame,
            column.rect.origin.x,
            column.rect.right().saturating_sub(1),
            column.header.bottom().saturating_sub(1),
            palette.horizontal,
            node_style.clone(),
        );
    }
    for task in &layout.tasks {
        draw_kanban_task(
            &mut frame,
            task,
            palette,
            node_style.clone(),
            text_style.clone(),
            muted_style.clone(),
        );
    }
    frame
}

fn draw_kanban_task(
    frame: &mut Frame,
    task: &PositionedKanbanTask,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
    muted_style: CellStyle,
) {
    draw_box(frame, task.rect, palette, node_style);
    write_text_safe(
        frame,
        task.rect.origin.x + 1,
        task.rect.origin.y + 1,
        &task.label,
        text_style,
    );
    for (index, (key, value)) in task.metadata.iter().enumerate() {
        write_text_safe(
            frame,
            task.rect.origin.x + 1,
            task.rect.origin.y + 2 + index as i32,
            &format!("{key}: {value}"),
            muted_style.clone(),
        );
    }
}

fn render_architecture_layout(
    layout: &ArchitectureLayout,
    palette: GlyphPalette,
    theme: Theme,
) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let boundary_style = theme.style_for(ThemeRole::EdgeAlt);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    for group in &layout.groups {
        draw_box(&mut frame, group.rect, palette, boundary_style.clone());
        let title = group.icon.as_ref().map_or_else(
            || group.label.clone(),
            |icon| format!("{icon} {}", group.label),
        );
        write_centered(&mut frame, group.header, &title, text_style.clone());
        draw_horizontal(
            &mut frame,
            group.rect.origin.x,
            group.rect.right().saturating_sub(1),
            group.header.bottom().saturating_sub(1),
            palette.horizontal,
            boundary_style.clone(),
        );
    }
    for edge in &layout.edges {
        draw_architecture_edge(&mut frame, edge, palette, edge_style.clone());
    }
    for node in &layout.nodes {
        draw_architecture_node(
            &mut frame,
            node,
            palette,
            node_style.clone(),
            text_style.clone(),
            muted_style.clone(),
        );
    }
    for edge in &layout.edges {
        draw_architecture_arrowheads(&mut frame, edge, palette, edge_style.clone());
    }
    frame
}

fn draw_architecture_node(
    frame: &mut Frame,
    node: &PositionedArchitectureNode,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
    muted_style: CellStyle,
) {
    draw_box(frame, node.rect, palette, node_style);
    match node.kind {
        ArchitectureNodeKind::Service => {
            if let Some(icon) = &node.icon {
                write_centered(
                    frame,
                    Rect {
                        origin: Point {
                            x: node.rect.origin.x,
                            y: node.rect.origin.y + 1,
                        },
                        size: Size {
                            width: node.rect.size.width,
                            height: 1,
                        },
                    },
                    icon,
                    muted_style,
                );
            }
            write_centered(frame, node.rect, &node.label, text_style);
        }
        ArchitectureNodeKind::Junction => {
            write_centered(frame, node.rect, &format!("+ {}", node.label), text_style);
        }
    }
}

fn draw_architecture_edge(
    frame: &mut Frame,
    edge: &PositionedArchitectureEdge,
    palette: GlyphPalette,
    style: CellStyle,
) {
    draw_polyline(frame, &edge.points, palette, style);
}

fn draw_architecture_arrowheads(
    frame: &mut Frame,
    edge: &PositionedArchitectureEdge,
    palette: GlyphPalette,
    style: CellStyle,
) {
    if edge.arrow_start
        && let [first, next, ..] = edge.points.as_slice()
    {
        put_safe(
            frame,
            first.x,
            first.y,
            arrowhead_for_segment(*next, *first, palette),
            style.clone(),
        );
    }
    if edge.arrow_end
        && let [.., previous, last] = edge.points.as_slice()
    {
        put_safe(
            frame,
            last.x,
            last.y,
            arrowhead_for_segment(*previous, *last, palette),
            style,
        );
    }
}

fn render_radar_layout(layout: &RadarLayout, _palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let alt_style = theme.style_for(ThemeRole::EdgeAlt);
    let text_style = theme.style_for(ThemeRole::Text);
    let highlight_style = theme.style_for(ThemeRole::Highlight);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_centered(
            &mut frame,
            Rect {
                origin: Point { x: 0, y: 0 },
                size: Size {
                    width: layout.size.width,
                    height: 1,
                },
            },
            title,
            text_style.clone(),
        );
    }
    for ring in &layout.rings {
        draw_closed_radar_path(&mut frame, ring, '.', muted_style.clone());
    }
    for axis in &layout.axes {
        draw_straight_line(&mut frame, layout.center, axis.end, '+', edge_style.clone());
        write_text_safe(
            &mut frame,
            axis.label_origin.x,
            axis.label_origin.y,
            &axis.label,
            text_style.clone(),
        );
    }
    put_safe(
        &mut frame,
        layout.center.x,
        layout.center.y,
        '+',
        edge_style.clone(),
    );
    for curve in &layout.curves {
        draw_radar_curve(&mut frame, curve, alt_style.clone());
    }
    if layout.show_legend {
        for curve in &layout.curves {
            if let Some(origin) = curve.legend_origin {
                write_text_safe(
                    &mut frame,
                    origin.x,
                    origin.y,
                    &radar_frame_legend_label(curve),
                    highlight_style.clone(),
                );
            }
        }
    }
    write_text_safe(
        &mut frame,
        layout.center.x + 1,
        layout.center.y,
        &layout.min_value,
        muted_style.clone(),
    );
    write_text_safe(
        &mut frame,
        layout.center.x + 1,
        layout.center.y.saturating_sub(
            layout.center.y.saturating_sub(
                layout
                    .axes
                    .first()
                    .map_or(layout.center.y, |axis| axis.end.y),
            ),
        ),
        &layout.max_value,
        muted_style,
    );
    frame
}

fn draw_radar_curve(frame: &mut Frame, curve: &PositionedRadarCurve, style: CellStyle) {
    let points = curve
        .points
        .iter()
        .map(|point| point.point)
        .collect::<Vec<_>>();
    draw_closed_radar_path(frame, &points, curve.marker, style.clone());
    for point in &points {
        put_safe(frame, point.x, point.y, curve.marker, style.clone());
    }
}

fn draw_closed_radar_path(frame: &mut Frame, points: &[Point], glyph: char, style: CellStyle) {
    for pair in points.windows(2) {
        draw_straight_line(frame, pair[0], pair[1], glyph, style.clone());
    }
    if points.len() > 2 {
        draw_straight_line(frame, *points.last().unwrap(), points[0], glyph, style);
    }
}

fn radar_frame_legend_label(curve: &PositionedRadarCurve) -> String {
    let values = curve
        .points
        .iter()
        .map(|point| point.value.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    format!("{} {}: {}", curve.marker, curve.label, values)
}

fn render_event_modeling_layout(
    layout: &EventModelingLayout,
    palette: GlyphPalette,
    theme: Theme,
) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let explicit_edge_style = theme.style_for(ThemeRole::EdgeAlt);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    for lane in &layout.lanes {
        write_text_safe(
            &mut frame,
            0,
            lane.y + lane.height / 2,
            &lane.title,
            muted_style.clone(),
        );
        draw_horizontal(
            &mut frame,
            0,
            layout.size.width,
            lane.y + lane.height,
            palette.horizontal,
            muted_style.clone(),
        );
    }
    for relation in &layout.relations {
        draw_event_modeling_relation(
            &mut frame,
            relation,
            palette,
            if relation.explicit {
                explicit_edge_style.clone()
            } else {
                edge_style.clone()
            },
            false,
        );
    }
    for event_frame in &layout.frames {
        draw_event_modeling_frame(
            &mut frame,
            event_frame,
            palette,
            node_style.clone(),
            text_style.clone(),
            muted_style.clone(),
        );
    }
    for relation in &layout.relations {
        draw_event_modeling_relation(
            &mut frame,
            relation,
            palette,
            if relation.explicit {
                explicit_edge_style.clone()
            } else {
                edge_style.clone()
            },
            true,
        );
    }
    for block in &layout.data_blocks {
        write_text_safe(
            &mut frame,
            block.origin.x,
            block.origin.y,
            &event_modeling_data_block_label(block),
            muted_style.clone(),
        );
    }
    frame
}

fn draw_event_modeling_relation(
    frame: &mut Frame,
    relation: &PositionedEventModelingRelation,
    palette: GlyphPalette,
    style: CellStyle,
    arrow_only: bool,
) {
    if !arrow_only {
        draw_polyline(frame, &relation.points, palette, style.clone());
    }
    if let Some(last) = relation.points.last() {
        put_safe(
            frame,
            last.x,
            last.y,
            arrowhead_for_points(&relation.points, palette),
            style,
        );
    }
}

fn draw_event_modeling_frame(
    frame: &mut Frame,
    event_frame: &PositionedEventModelingFrame,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
    muted_style: CellStyle,
) {
    draw_box(frame, event_frame.rect, palette, node_style.clone());
    let inner_width = event_frame.rect.size.width.saturating_sub(2) as usize;
    let header = match event_frame.frame_kind {
        EventModelingFrameKind::TimeFrame => format!(
            "{} {}",
            event_frame.number,
            event_modeling_entity_type_label(event_frame.entity_type)
        ),
        EventModelingFrameKind::ResetFrame => format!("{} reset", event_frame.number),
    };
    let data = event_frame
        .data_ref
        .as_ref()
        .map(|value| format!("[[{value}]]"))
        .or_else(|| event_frame.data_summary.clone())
        .unwrap_or_default();
    write_text_safe(
        frame,
        event_frame.rect.origin.x + 1,
        event_frame.rect.origin.y + 1,
        &event_modeling_fit(&header, inner_width),
        muted_style.clone(),
    );
    write_text_safe(
        frame,
        event_frame.rect.origin.x + 1,
        event_frame.rect.origin.y + 2,
        &event_modeling_fit(&event_frame.entity, inner_width),
        text_style,
    );
    if !data.is_empty() {
        write_text_safe(
            frame,
            event_frame.rect.origin.x + 1,
            event_frame.rect.origin.y + 3,
            &event_modeling_fit(&data, inner_width),
            muted_style,
        );
    }
    if event_frame.frame_kind == EventModelingFrameKind::ResetFrame {
        put_safe(
            frame,
            event_frame.rect.origin.x + 1,
            event_frame.rect.origin.y,
            '!',
            node_style,
        );
    }
}

fn event_modeling_entity_type_label(entity_type: EventModelingEntityType) -> &'static str {
    match entity_type {
        EventModelingEntityType::Ui => "ui",
        EventModelingEntityType::Processor => "pcr",
        EventModelingEntityType::Command => "cmd",
        EventModelingEntityType::ReadModel => "rmo",
        EventModelingEntityType::Event => "evt",
    }
}

fn event_modeling_fit(value: &str, width: usize) -> String {
    if value.chars().count() <= width {
        return value.to_owned();
    }
    if width <= 3 {
        return value.chars().take(width).collect();
    }
    let mut output = value.chars().take(width - 3).collect::<String>();
    output.push_str("...");
    output
}

fn event_modeling_data_block_label(block: &PositionedEventModelingDataBlock) -> String {
    match &block.ty {
        Some(ty) => format!("data {}({ty}): {}", block.id, block.summary),
        None => format!("data {}: {}", block.id, block.summary),
    }
}

fn render_treemap_layout(layout: &TreemapLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    for node in &layout.nodes {
        draw_treemap_node(
            &mut frame,
            node,
            palette,
            node_style.clone(),
            text_style.clone(),
            muted_style.clone(),
        );
    }
    frame
}

fn draw_treemap_node(
    frame: &mut Frame,
    node: &PositionedTreemapNode,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
    muted_style: CellStyle,
) {
    if node.rect.size.width < 2 || node.rect.size.height < 2 {
        return;
    }
    draw_box(frame, node.rect, palette, node_style);
    let inner_width = node.rect.size.width.saturating_sub(2) as usize;
    let label = treemap_node_label(node);
    write_text_safe(
        frame,
        node.rect.origin.x + 1,
        node.rect.origin.y + 1,
        &event_modeling_fit(&label, inner_width),
        text_style,
    );
    if node.rect.size.height > 3 {
        let value = node.value.as_ref().map_or_else(
            || format!("sum {}", node.aggregate_value),
            |value| value.clone(),
        );
        write_text_safe(
            frame,
            node.rect.origin.x + 1,
            node.rect.bottom().saturating_sub(2),
            &event_modeling_fit(&value, inner_width),
            muted_style,
        );
    }
}

fn treemap_node_label(node: &PositionedTreemapNode) -> String {
    if node.classes.is_empty() {
        return node.label.clone();
    }
    format!("{} [{}]", node.label, node.classes.join(","))
}

fn render_venn_layout(layout: &VennLayout, _palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_centered_row(&mut frame, 0, title, text_style.clone());
    }
    for set in &layout.sets {
        draw_venn_set(
            &mut frame,
            set,
            node_style.clone(),
            text_style.clone(),
            muted_style.clone(),
        );
    }
    for union in &layout.unions {
        draw_venn_union(&mut frame, union, text_style.clone(), muted_style.clone());
    }
    for style in &layout.styles {
        write_text_safe(
            &mut frame,
            style.origin.x,
            style.origin.y,
            &venn_style_frame_label(style),
            muted_style.clone(),
        );
    }
    frame
}

fn draw_venn_set(
    frame: &mut Frame,
    set: &PositionedVennSet,
    node_style: CellStyle,
    text_style: CellStyle,
    muted_style: CellStyle,
) {
    draw_venn_ellipse(
        frame,
        set.center,
        set.radius_x,
        set.radius_y,
        node_style.clone(),
    );
    let inner_width = (set.radius_x.saturating_mul(2).saturating_sub(3)).max(1) as usize;
    let frame_center = frame.width as i32 / 2;
    let label_x = if set.center.x < frame_center {
        set.center.x - set.radius_x / 2
    } else if set.center.x > frame_center {
        set.center.x + set.radius_x / 2
    } else {
        set.center.x
    };
    write_centered_point(
        frame,
        label_x,
        set.center.y - 1,
        &event_modeling_fit(&venn_set_frame_label(set), inner_width),
        text_style,
    );
    for (index, text) in set.texts.iter().enumerate() {
        write_centered_point(
            frame,
            label_x,
            set.center.y + index as i32,
            &event_modeling_fit(text, inner_width),
            muted_style.clone(),
        );
    }
}

fn draw_venn_union(
    frame: &mut Frame,
    union: &PositionedVennUnion,
    text_style: CellStyle,
    muted_style: CellStyle,
) {
    let label = venn_union_frame_label(union);
    write_centered_point(frame, union.point.x, union.point.y, &label, text_style);
    for (index, text) in union.texts.iter().enumerate() {
        write_centered_point(
            frame,
            union.point.x,
            union.point.y + 1 + index as i32,
            text,
            muted_style.clone(),
        );
    }
}

fn draw_venn_ellipse(
    frame: &mut Frame,
    center: Point,
    radius_x: i32,
    radius_y: i32,
    style: CellStyle,
) {
    if radius_x <= 0 || radius_y <= 0 {
        return;
    }
    for y in center.y - radius_y..=center.y + radius_y {
        for x in center.x - radius_x..=center.x + radius_x {
            let dx = f64::from(x - center.x) / f64::from(radius_x);
            let dy = f64::from(y - center.y) / f64::from(radius_y);
            let distance = dx.mul_add(dx, dy * dy);
            if (0.82..=1.16).contains(&distance) {
                put_safe(frame, x, y, 'o', style.clone());
            }
        }
    }
}

fn write_centered_row(frame: &mut Frame, y: i32, text: &str, style: CellStyle) {
    let x = (frame.width as i32 - text.chars().count() as i32).max(0) / 2;
    write_text_safe(frame, x, y, text, style);
}

fn write_centered_point(frame: &mut Frame, x: i32, y: i32, text: &str, style: CellStyle) {
    let padded = format!(" {text} ");
    let start_x = x - padded.chars().count() as i32 / 2;
    write_text_safe(frame, start_x, y, &padded, style);
}

fn venn_set_frame_label(set: &PositionedVennSet) -> String {
    set.size.as_ref().map_or_else(
        || set.label.clone(),
        |size| format!("{} ({size})", set.label),
    )
}

fn venn_union_frame_label(union: &PositionedVennUnion) -> String {
    let label = union
        .label
        .clone()
        .unwrap_or_else(|| union.members.join("&"));
    union
        .size
        .as_ref()
        .map_or(label.clone(), |size| format!("{label} ({size})"))
}

fn venn_style_frame_label(style: &PositionedVennStyle) -> String {
    format!(
        "style {}: {}",
        style.targets.join(","),
        style.declarations.join(", ")
    )
}

fn render_ishikawa_layout(layout: &IshikawaLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    draw_horizontal(
        &mut frame,
        layout.spine_start.x,
        layout.spine_end.x,
        layout.spine_start.y,
        palette.horizontal,
        edge_style.clone(),
    );
    put_safe(
        &mut frame,
        layout.spine_end.x,
        layout.spine_end.y,
        palette.arrow_right,
        edge_style.clone(),
    );
    for edge in &layout.edges {
        draw_ishikawa_edge(&mut frame, *edge, edge_style.clone());
    }
    draw_box(&mut frame, layout.event_rect, palette, node_style.clone());
    write_centered(
        &mut frame,
        layout.event_rect,
        &layout.event,
        text_style.clone(),
    );
    for node in &layout.nodes {
        draw_ishikawa_node(
            &mut frame,
            node,
            palette,
            node_style.clone(),
            text_style.clone(),
        );
    }
    frame
}

fn draw_ishikawa_edge(frame: &mut Frame, edge: PositionedIshikawaEdge, style: CellStyle) {
    let glyph = if edge.to.y < edge.from.y { '/' } else { '\\' };
    draw_straight_line(frame, edge.from, edge.to, glyph, style);
}

fn draw_ishikawa_node(
    frame: &mut Frame,
    node: &PositionedIshikawaNode,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
) {
    draw_box(frame, node.rect, palette, node_style);
    write_centered(frame, node.rect, &node.label, text_style);
}

fn render_wardley_layout(layout: &WardleyLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_centered_row(&mut frame, 0, title, text_style.clone());
    }
    draw_wardley_axes(
        &mut frame,
        layout,
        palette,
        edge_style.clone(),
        muted_style.clone(),
    );
    for link in &layout.links {
        draw_wardley_link(&mut frame, link, edge_style.clone());
    }
    for evolve in &layout.evolves {
        draw_wardley_evolve(&mut frame, evolve, edge_style.clone(), muted_style.clone());
    }
    for component in &layout.components {
        draw_wardley_component(
            &mut frame,
            component,
            node_style.clone(),
            text_style.clone(),
            muted_style.clone(),
        );
    }
    for text in &layout.texts {
        draw_wardley_text(&mut frame, text, muted_style.clone());
    }
    if let Some(origin) = layout.annotations_origin {
        write_text_safe(&mut frame, origin.x, origin.y, "annotations", muted_style);
    }
    frame
}

fn draw_wardley_axes(
    frame: &mut Frame,
    layout: &WardleyLayout,
    palette: GlyphPalette,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    draw_box(frame, layout.plot, palette, edge_style.clone());
    let stage_count = layout.stages.len().max(1);
    for (index, stage) in layout.stages.iter().enumerate() {
        let x = layout.plot.origin.x
            + ((index as i32 * layout.plot.size.width) / stage_count as i32)
                .min(layout.plot.size.width - 1);
        draw_vertical(
            frame,
            x,
            layout.plot.origin.y,
            layout.plot.bottom().saturating_sub(1),
            ':',
            edge_style.clone(),
        );
        write_text_safe(
            frame,
            x,
            layout.plot.bottom() + 1,
            &event_modeling_fit(stage, 14),
            text_style.clone(),
        );
    }
    write_text_safe(
        frame,
        layout.plot.origin.x,
        layout.plot.origin.y.saturating_sub(1),
        "visible",
        text_style.clone(),
    );
    write_text_safe(
        frame,
        layout.plot.right().saturating_sub(9),
        layout.plot.bottom() + 2,
        "evolved",
        text_style,
    );
}

fn draw_wardley_link(frame: &mut Frame, link: &PositionedWardleyLink, style: CellStyle) {
    let glyph = match link.kind {
        WardleyLinkKind::Dashed => '.',
        WardleyLinkKind::Flow
        | WardleyLinkKind::ReverseFlow
        | WardleyLinkKind::BidirectionalFlow => '=',
        WardleyLinkKind::Dependency => '-',
    };
    draw_straight_line(frame, link.from, link.to, glyph, style.clone());
    put_safe(frame, link.to.x, link.to.y, '>', style.clone());
    if matches!(
        link.kind,
        WardleyLinkKind::ReverseFlow | WardleyLinkKind::BidirectionalFlow
    ) {
        put_safe(frame, link.from.x, link.from.y, '<', style.clone());
    }
    if let Some(label) = &link.label {
        let midpoint = Point {
            x: (link.from.x + link.to.x) / 2,
            y: (link.from.y + link.to.y) / 2,
        };
        write_text_safe(frame, midpoint.x + 1, midpoint.y, label, style);
    }
}

fn draw_wardley_evolve(
    frame: &mut Frame,
    evolve: &PositionedWardleyEvolve,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    draw_straight_line(frame, evolve.from, evolve.to, '.', edge_style.clone());
    put_safe(frame, evolve.to.x, evolve.to.y, '>', edge_style);
    write_text_safe(
        frame,
        evolve.to.x + 1,
        evolve.to.y,
        &evolve.name,
        text_style,
    );
}

fn draw_wardley_text(frame: &mut Frame, text: &PositionedWardleyText, style: CellStyle) {
    let prefix = match text.kind {
        WardleyTextKind::Note => "note",
        WardleyTextKind::Annotation => "#",
        WardleyTextKind::Accelerator => "accel",
        WardleyTextKind::Deaccelerator => "decel",
    };
    write_text_safe(
        frame,
        text.point.x + 1,
        text.point.y,
        &format!("{prefix}: {}", text.text),
        style,
    );
}

fn draw_wardley_component(
    frame: &mut Frame,
    component: &PositionedWardleyComponent,
    node_style: CellStyle,
    text_style: CellStyle,
    muted_style: CellStyle,
) {
    let glyph = match component.kind {
        WardleyComponentKind::Anchor => '@',
        WardleyComponentKind::Component => wardley_component_glyph(&component.decorators),
    };
    put_safe(
        frame,
        component.point.x,
        component.point.y,
        glyph,
        node_style,
    );
    let mut label = component.name.clone();
    if let Some(pipeline) = &component.pipeline {
        label = format!("{pipeline}/{label}");
    }
    if !component.decorators.is_empty() {
        label.push_str(" [");
        label.push_str(
            &component
                .decorators
                .iter()
                .map(wardley_decorator_label)
                .collect::<Vec<_>>()
                .join(","),
        );
        label.push(']');
    }
    write_text_safe(
        frame,
        component.label_origin.x,
        component.label_origin.y,
        &label,
        if component.kind == WardleyComponentKind::Anchor {
            text_style
        } else {
            muted_style
        },
    );
}

fn wardley_component_glyph(decorators: &[WardleyDecorator]) -> char {
    if decorators.contains(&WardleyDecorator::Build) {
        '^'
    } else if decorators.contains(&WardleyDecorator::Buy) {
        '<'
    } else if decorators.contains(&WardleyDecorator::Outsource) {
        '#'
    } else if decorators.contains(&WardleyDecorator::Market) {
        'o'
    } else if decorators.contains(&WardleyDecorator::Inertia) {
        '!'
    } else {
        '*'
    }
}

fn wardley_decorator_label(decorator: &WardleyDecorator) -> &'static str {
    match decorator {
        WardleyDecorator::Inertia => "inertia",
        WardleyDecorator::Build => "build",
        WardleyDecorator::Buy => "buy",
        WardleyDecorator::Outsource => "outsource",
        WardleyDecorator::Market => "market",
    }
}

fn render_tree_view_layout(layout: &TreeViewLayout, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    let node_style = theme.style_for(ThemeRole::Node);
    for node in &layout.nodes {
        draw_tree_view_node(
            &mut frame,
            node,
            text_style.clone(),
            muted_style.clone(),
            node_style.clone(),
        );
    }
    frame
}

fn draw_tree_view_node(
    frame: &mut Frame,
    node: &PositionedTreeViewNode,
    text_style: CellStyle,
    muted_style: CellStyle,
    node_style: CellStyle,
) {
    let mut x = node.point.x;
    write_text_safe(frame, x, node.point.y, &node.prefix, muted_style.clone());
    x += node.prefix.chars().count() as i32;
    let icon = format!("[{}]", node.icon);
    write_text_safe(frame, x, node.point.y, &icon, muted_style.clone());
    x += icon.chars().count() as i32 + 1;
    let label = if node.directory {
        format!("{}/", node.label)
    } else {
        node.label.clone()
    };
    let label_style = if node.directory || node.classes.iter().any(|class| class == "highlight") {
        node_style
    } else {
        text_style
    };
    write_text_safe(frame, x, node.point.y, &label, label_style);
    x += label.chars().count() as i32;
    if !node.classes.is_empty() {
        let classes = format!(" [{}]", node.classes.join(","));
        write_text_safe(frame, x, node.point.y, &classes, muted_style.clone());
        x += classes.chars().count() as i32;
    }
    if let Some(description) = &node.description {
        let description = format!(" ## {description}");
        write_text_safe(frame, x, node.point.y, &description, muted_style);
    }
}

fn render_cynefin_diagram(ast: &CynefinAst, palette: GlyphPalette, theme: Theme) -> Frame {
    let transition_rows = ast.transitions.len().min(6) as i32;
    let mut frame = Frame::new_styled(
        80,
        (24 + transition_rows) as usize,
        theme.style_for(ThemeRole::Background),
    );
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    let node_style = theme.style_for(ThemeRole::Node);
    if let Some(title) = &ast.title {
        write_text_safe(&mut frame, 1, 0, &title.text, text_style.clone());
    }

    let domains = [
        (CynefinDomainKind::Complex, Rect {
            origin: Point { x: 1, y: 2 },
            size: Size { width: 38, height: 8 },
        }),
        (CynefinDomainKind::Complicated, Rect {
            origin: Point { x: 41, y: 2 },
            size: Size { width: 38, height: 8 },
        }),
        (CynefinDomainKind::Chaotic, Rect {
            origin: Point { x: 1, y: 12 },
            size: Size { width: 38, height: 8 },
        }),
        (CynefinDomainKind::Clear, Rect {
            origin: Point { x: 41, y: 12 },
            size: Size { width: 38, height: 8 },
        }),
    ];
    for (kind, rect) in domains {
        draw_cynefin_domain(
            &mut frame,
            cynefin_domain(ast, kind),
            kind,
            rect,
            palette,
            text_style.clone(),
            muted_style.clone(),
            node_style.clone(),
        );
    }

    let confusion = Rect {
        origin: Point { x: 29, y: 8 },
        size: Size { width: 22, height: 6 },
    };
    draw_cynefin_domain(
        &mut frame,
        cynefin_domain(ast, CynefinDomainKind::Confusion),
        CynefinDomainKind::Confusion,
        confusion,
        palette,
        text_style.clone(),
        muted_style.clone(),
        node_style,
    );

    if !ast.transitions.is_empty() {
        write_text_safe(&mut frame, 1, 21, "transitions", muted_style.clone());
        for (index, transition) in ast.transitions.iter().take(6).enumerate() {
            let label = transition
                .label
                .as_ref()
                .map(|label| format!(" : {}", label.text))
                .unwrap_or_default();
            let text = format!(
                "{} -> {}{}",
                cynefin_domain_label(transition.from.value),
                cynefin_domain_label(transition.to.value),
                label
            );
            write_text_safe(
                &mut frame,
                15,
                21 + index as i32,
                &truncate_display_width(&text, 63),
                text_style.clone(),
            );
        }
    }

    frame
}

fn draw_cynefin_domain(
    frame: &mut Frame,
    domain: Option<&CynefinDomain>,
    kind: CynefinDomainKind,
    rect: Rect,
    palette: GlyphPalette,
    text_style: CellStyle,
    muted_style: CellStyle,
    node_style: CellStyle,
) {
    draw_box(frame, rect, palette, node_style);
    write_text_safe(
        frame,
        rect.origin.x + 2,
        rect.origin.y,
        cynefin_domain_label(kind),
        text_style.clone(),
    );
    let Some(domain) = domain else {
        write_text_safe(frame, rect.origin.x + 2, rect.origin.y + 2, "empty", muted_style);
        return;
    };
    for (index, item) in domain.items.iter().take((rect.size.height - 3) as usize).enumerate() {
        let text = format!("- {}", item.label.text);
        write_text_safe(
            frame,
            rect.origin.x + 2,
            rect.origin.y + 2 + index as i32,
            &truncate_display_width(&text, (rect.size.width - 4) as usize),
            text_style.clone(),
        );
    }
    if domain.items.len() > (rect.size.height - 3) as usize {
        let more = format!("+{} more", domain.items.len() - (rect.size.height - 3) as usize);
        write_text_safe(
            frame,
            rect.origin.x + 2,
            rect.bottom() - 2,
            &more,
            muted_style,
        );
    }
}

fn cynefin_domain<'ast>(
    ast: &'ast CynefinAst,
    kind: CynefinDomainKind,
) -> Option<&'ast CynefinDomain> {
    ast.domains.iter().find(|domain| domain.kind.value == kind)
}

fn cynefin_domain_label(kind: CynefinDomainKind) -> &'static str {
    match kind {
        CynefinDomainKind::Complex => "complex",
        CynefinDomainKind::Complicated => "complicated",
        CynefinDomainKind::Clear => "clear",
        CynefinDomainKind::Chaotic => "chaotic",
        CynefinDomainKind::Confusion => "confusion",
    }
}

fn render_railroad_diagram(ast: &RailroadAst, palette: GlyphPalette, theme: Theme) -> Frame {
    let rule_width = ast
        .rules
        .iter()
        .map(|rule| rule.name.value.chars().count() + rule.expression.text.chars().count() + 12)
        .max()
        .unwrap_or(40)
        .clamp(40, 100);
    let width = rule_width + 2;
    let title_rows = usize::from(ast.title.is_some());
    let height = 1 + title_rows + ast.rules.len().max(1) * 4;
    let mut frame = Frame::new_styled(width, height, theme.style_for(ThemeRole::Background));
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    let node_style = theme.style_for(ThemeRole::Node);

    let mut y = 0i32;
    if let Some(title) = &ast.title {
        write_text_safe(&mut frame, 0, y, &title.text, text_style.clone());
        y += 2;
    }
    if ast.rules.is_empty() {
        write_text_safe(&mut frame, 0, y, "no rules", muted_style);
        return frame;
    }
    for rule in &ast.rules {
        let rect = Rect {
            origin: Point { x: 0, y },
            size: Size {
                width: rule_width as i32,
                height: 3,
            },
        };
        draw_box(&mut frame, rect, palette, node_style.clone());
        write_text_safe(&mut frame, 2, y, &rule.name.value, text_style.clone());
        let expression_width = rule_width.saturating_sub(12 + rule.name.value.chars().count());
        let expression = truncate_display_width(&rule.expression.text, expression_width);
        let rule_line = format!("o-- {} --o", expression);
        write_text_safe(&mut frame, 4, y + 1, &rule_line, text_style.clone());
        y += 4;
    }
    frame
}

fn render_class_layout(layout: &ClassLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    for relationship in &layout.relationships {
        draw_class_relationship(
            &mut frame,
            relationship,
            palette,
            edge_style.clone(),
            text_style.clone(),
        );
    }
    for node in &layout.nodes {
        draw_class_node(
            &mut frame,
            node,
            palette,
            node_style.clone(),
            text_style.clone(),
        );
    }
    frame
}

fn render_requirement_layout(
    layout: &RequirementLayout,
    palette: GlyphPalette,
    theme: Theme,
) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    for relationship in &layout.relationships {
        draw_requirement_relationship(
            &mut frame,
            relationship,
            palette,
            edge_style.clone(),
            text_style.clone(),
        );
    }
    for node in &layout.nodes {
        draw_requirement_node(
            &mut frame,
            node,
            palette,
            node_style.clone(),
            text_style.clone(),
        );
    }
    frame
}

fn render_c4_layout(layout: &C4Layout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let boundary_style = theme.style_for(ThemeRole::Muted);
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    if let Some(title) = &layout.title {
        write_text_safe(&mut frame, 0, 0, title, text_style.clone());
    }
    for boundary in &layout.boundaries {
        draw_c4_boundary(
            &mut frame,
            boundary,
            palette,
            boundary_style.clone(),
            text_style.clone(),
        );
    }
    for relationship in &layout.relationships {
        draw_c4_relationship(
            &mut frame,
            relationship,
            palette,
            edge_style.clone(),
            text_style.clone(),
        );
    }
    for element in &layout.elements {
        draw_c4_element(
            &mut frame,
            element,
            palette,
            node_style.clone(),
            text_style.clone(),
        );
    }
    frame
}

fn render_gantt_layout(layout: &GanttLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let text_style = theme.style_for(ThemeRole::Text);
    let node_style = theme.style_for(ThemeRole::Node);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_text_safe(&mut frame, 0, 0, title, text_style.clone());
    }
    draw_gantt_axis(
        &mut frame,
        layout,
        palette,
        muted_style.clone(),
        text_style.clone(),
    );
    for section in &layout.sections {
        write_text_safe(
            &mut frame,
            0,
            section.y,
            &section.label,
            muted_style.clone(),
        );
    }
    for task in &layout.tasks {
        draw_gantt_task(
            &mut frame,
            task,
            palette,
            node_style.clone(),
            edge_style.clone(),
            text_style.clone(),
        );
    }
    draw_gantt_excluded_days(&mut frame, layout, muted_style.clone());
    frame
}

fn draw_gantt_axis(
    frame: &mut Frame,
    layout: &GanttLayout,
    palette: GlyphPalette,
    style: CellStyle,
    text_style: CellStyle,
) {
    let axis_y = 1;
    let left = gantt_chart_left(layout);
    let right = layout.size.width.saturating_sub(1);
    draw_horizontal(
        frame,
        left,
        right,
        axis_y,
        palette.horizontal,
        style.clone(),
    );
    put_safe(frame, left, axis_y, palette.crossing, style.clone());
    put_safe(frame, right, axis_y, palette.crossing, style.clone());
    for tick in &layout.ticks {
        put_safe(frame, tick.x, axis_y, palette.crossing, style.clone());
        let x = tick.x - (tick.label.chars().count() as i32 / 2);
        write_text_safe(frame, x.max(0), 0, &tick.label, text_style.clone());
    }
    if let Some(today_x) = layout.today_x {
        for y in axis_y + 1..layout.size.height {
            put_safe(frame, today_x, y, '!', style.clone());
        }
    }
}

fn draw_gantt_excluded_days(frame: &mut Frame, layout: &GanttLayout, style: CellStyle) {
    let left = gantt_chart_left(layout);
    for day in &layout.excluded_days {
        let x = left + (*day - layout.min_day) * layout.day_width;
        for y in 2..layout.size.height {
            put_safe(frame, x, y, ':', style.clone());
        }
    }
}

fn draw_gantt_task(
    frame: &mut Frame,
    task: &PositionedGanttTask,
    palette: GlyphPalette,
    node_style: CellStyle,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    write_text_safe(
        frame,
        task.label_origin.x,
        task.label_origin.y,
        &task.title,
        text_style.clone(),
    );
    let glyph = gantt_task_glyph(task, palette);
    let style = if task.tags.contains(&GanttTaskTag::Crit) {
        edge_style
    } else {
        node_style
    };
    if task.tags.contains(&GanttTaskTag::Milestone) {
        put_safe(
            frame,
            task.rect.origin.x,
            task.rect.origin.y,
            '<',
            style.clone(),
        );
        put_safe(
            frame,
            task.rect.origin.x + 1,
            task.rect.origin.y,
            '>',
            style,
        );
    } else {
        draw_horizontal(
            frame,
            task.rect.origin.x,
            task.rect.right().saturating_sub(1),
            task.rect.origin.y,
            glyph,
            style,
        );
    }
}

fn gantt_task_glyph(task: &PositionedGanttTask, palette: GlyphPalette) -> char {
    if task.tags.contains(&GanttTaskTag::Done) {
        palette.block
    } else if task.tags.contains(&GanttTaskTag::Active) {
        '='
    } else if task.tags.contains(&GanttTaskTag::Crit) {
        '!'
    } else {
        palette.horizontal
    }
}

fn gantt_chart_left(layout: &GanttLayout) -> i32 {
    layout
        .tasks
        .iter()
        .map(|task| task.rect.origin.x - (task.start - layout.min_day) * layout.day_width)
        .min()
        .unwrap_or(18)
}

fn render_pie_layout(
    layout: &PieLayout,
    palette: GlyphPalette,
    theme: Theme,
    visible_slices: usize,
) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    if let Some(title) = &layout.title {
        write_text_safe(&mut frame, 0, 0, title, text_style.clone());
    }
    for cell in &layout.cells {
        if cell.slice_index >= visible_slices {
            continue;
        }
        put_safe(
            &mut frame,
            cell.point.x,
            cell.point.y,
            pie_slice_glyph(cell.slice_index, palette),
            node_style.clone(),
        );
    }
    for (index, slice) in layout.slices.iter().enumerate() {
        if index >= visible_slices {
            continue;
        }
        write_text_safe(
            &mut frame,
            slice.label_origin.x,
            slice.label_origin.y,
            &pie_slice_percent_label(slice.percent_basis_points),
            text_style.clone(),
        );
    }
    for (index, slice) in layout.slices.iter().enumerate() {
        write_text_safe(
            &mut frame,
            slice.legend_origin.x,
            slice.legend_origin.y,
            &pie_legend_text(index, slice, layout.show_data, palette),
            text_style.clone(),
        );
    }
    frame
}

fn render_quadrant_layout(layout: &QuadrantLayout, palette: GlyphPalette, theme: Theme) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let node_style = theme.style_for(ThemeRole::Node);
    let edge_style = theme.style_for(ThemeRole::Edge);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_text_safe(&mut frame, 0, 0, title, text_style.clone());
    }
    draw_box(&mut frame, layout.plot, palette, node_style);
    let mid_x = layout.plot.origin.x + layout.plot.size.width / 2;
    let mid_y = layout.plot.origin.y + layout.plot.size.height / 2;
    draw_vertical(
        &mut frame,
        mid_x,
        layout.plot.origin.y + 1,
        layout.plot.bottom().saturating_sub(2),
        palette.vertical,
        edge_style.clone(),
    );
    draw_horizontal(
        &mut frame,
        layout.plot.origin.x + 1,
        layout.plot.right().saturating_sub(2),
        mid_y,
        palette.horizontal,
        edge_style.clone(),
    );
    put_safe(
        &mut frame,
        mid_x,
        mid_y,
        palette.crossing,
        edge_style.clone(),
    );
    for quadrant in &layout.quadrants {
        write_text_safe(
            &mut frame,
            quadrant.origin.x,
            quadrant.origin.y,
            &quadrant.label,
            muted_style.clone(),
        );
    }
    write_text_safe(
        &mut frame,
        0,
        layout.plot.origin.y,
        &layout.y_end,
        text_style.clone(),
    );
    write_text_safe(
        &mut frame,
        0,
        layout.plot.bottom().saturating_sub(1),
        &layout.y_start,
        text_style.clone(),
    );
    let x_axis_y = layout.plot.bottom() + 1;
    write_text_safe(
        &mut frame,
        layout.plot.origin.x,
        x_axis_y,
        &layout.x_start,
        text_style.clone(),
    );
    write_text_safe(
        &mut frame,
        (layout.plot.right() - layout.x_end.chars().count() as i32).max(0),
        x_axis_y,
        &layout.x_end,
        text_style.clone(),
    );
    for point in &layout.points {
        draw_quadrant_point(&mut frame, point, text_style.clone(), edge_style.clone());
    }
    frame
}

fn draw_quadrant_point(
    frame: &mut Frame,
    point: &PositionedQuadrantPoint,
    text_style: CellStyle,
    edge_style: CellStyle,
) {
    put_safe(frame, point.point.x, point.point.y, 'o', edge_style);
    write_text_safe(
        frame,
        point.label_origin.x,
        point.label_origin.y,
        &point.label,
        text_style,
    );
}

fn pie_legend_text(
    index: usize,
    slice: &PositionedPieSlice,
    show_data: bool,
    palette: GlyphPalette,
) -> String {
    let glyph = pie_slice_glyph(index, palette);
    if show_data {
        format!("{glyph} {} [{}]", slice.label, slice.value_text)
    } else {
        format!("{glyph} {}", slice.label)
    }
}

fn pie_slice_percent_label(basis_points: u16) -> String {
    format!("{}%", (basis_points + 50) / 100)
}

fn pie_slice_glyph(index: usize, palette: GlyphPalette) -> char {
    const GLYPHS: [char; 12] = ['#', '+', '=', '*', '%', '@', 'o', 'x', '~', ':', ';', '?'];
    if index == 0 {
        palette.block
    } else {
        GLYPHS[index % GLYPHS.len()]
    }
}

fn render_mindmap_layout(
    layout: &MindmapLayout,
    palette: GlyphPalette,
    theme: Theme,
    visible_depth: usize,
) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    for edge in &layout.edges {
        if layout.nodes[edge.from].depth >= visible_depth
            || layout.nodes[edge.to].depth > visible_depth
        {
            continue;
        }
        draw_polyline(&mut frame, &edge.points, palette, edge_style.clone());
    }
    for node in &layout.nodes {
        if node.depth > visible_depth {
            continue;
        }
        draw_mindmap_node(
            &mut frame,
            node,
            palette,
            node_style.clone(),
            text_style.clone(),
        );
    }
    frame
}

fn render_journey_layout(
    layout: &JourneyLayout,
    palette: GlyphPalette,
    theme: Theme,
    visible_tasks: usize,
) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let text_style = theme.style_for(ThemeRole::Text);
    let node_style = theme.style_for(ThemeRole::Node);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_text_safe(&mut frame, 0, 0, title, text_style.clone());
    }
    for section in &layout.sections {
        write_text_safe(
            &mut frame,
            0,
            section.y,
            &section.label,
            muted_style.clone(),
        );
    }
    for task in layout.tasks.iter().take(visible_tasks) {
        draw_journey_task(
            &mut frame,
            task,
            palette,
            node_style.clone(),
            muted_style.clone(),
            text_style.clone(),
        );
    }
    frame
}

fn draw_journey_task(
    frame: &mut Frame,
    task: &PositionedJourneyTask,
    palette: GlyphPalette,
    node_style: CellStyle,
    muted_style: CellStyle,
    text_style: CellStyle,
) {
    write_text_safe(
        frame,
        task.label_origin.x,
        task.label_origin.y,
        &task.label,
        text_style.clone(),
    );
    let filled =
        (task.bar_rect.size.width * i32::from(task.score) / 5).clamp(0, task.bar_rect.size.width);
    for offset in 0..task.bar_rect.size.width {
        let is_filled = offset < filled;
        put_safe(
            frame,
            task.bar_rect.origin.x + offset,
            task.bar_rect.origin.y,
            if is_filled {
                palette.block
            } else {
                palette.horizontal
            },
            if is_filled {
                node_style.clone()
            } else {
                muted_style.clone()
            },
        );
    }
    write_text_safe(
        frame,
        task.score_origin.x,
        task.score_origin.y,
        &format!("{}/5", task.score),
        text_style.clone(),
    );
    write_text_safe(
        frame,
        task.actors_origin.x,
        task.actors_origin.y,
        &journey_actor_text(task, palette),
        text_style,
    );
}

fn journey_actor_text(task: &PositionedJourneyTask, palette: GlyphPalette) -> String {
    task.actors
        .iter()
        .zip(&task.actor_style_indices)
        .map(|(actor, index)| format!("{} {actor}", journey_actor_glyph(*index, palette)))
        .collect::<Vec<_>>()
        .join(", ")
}

fn journey_actor_glyph(index: usize, palette: GlyphPalette) -> char {
    const GLYPHS: [char; 12] = ['#', '+', '=', '*', '%', '@', 'o', 'x', '~', ':', ';', '?'];
    if index == 0 {
        palette.block
    } else {
        GLYPHS[index % GLYPHS.len()]
    }
}

fn render_gitgraph_layout(
    layout: &GitGraphLayout,
    palette: GlyphPalette,
    theme: Theme,
    visible_commits: usize,
) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    for branch in &layout.branches {
        write_text_safe(
            &mut frame,
            branch.label_origin.x,
            branch.label_origin.y,
            &branch.name,
            muted_style.clone(),
        );
        draw_polyline(&mut frame, &branch.points, palette, muted_style.clone());
    }
    for edge in &layout.edges {
        if edge.to >= visible_commits {
            continue;
        }
        draw_polyline(&mut frame, &edge.points, palette, edge_style.clone());
    }
    for commit in layout.commits.iter().take(visible_commits) {
        draw_gitgraph_commit(&mut frame, commit, node_style.clone(), text_style.clone());
    }
    frame
}

fn draw_gitgraph_commit(
    frame: &mut Frame,
    commit: &PositionedGitGraphCommit,
    node_style: CellStyle,
    text_style: CellStyle,
) {
    put_safe(
        frame,
        commit.point.x,
        commit.point.y,
        gitgraph_commit_glyph(commit),
        node_style.clone(),
    );
    write_text_safe(
        frame,
        commit.label_origin.x,
        commit.label_origin.y,
        &commit.id,
        text_style.clone(),
    );
    if let (Some(tag), Some(origin)) = (&commit.tag, commit.tag_origin) {
        write_text_safe(frame, origin.x, origin.y, &format!("[{tag}]"), text_style);
    }
}

fn gitgraph_commit_glyph(commit: &PositionedGitGraphCommit) -> char {
    if commit.is_cherry_pick {
        '+'
    } else if commit.is_merge {
        '*'
    } else {
        match commit.kind {
            GitGraphCommitKind::Normal => 'o',
            GitGraphCommitKind::Reverse => 'x',
            GitGraphCommitKind::Highlight => '#',
        }
    }
}

fn render_timeline_layout(
    layout: &TimelineLayout,
    palette: GlyphPalette,
    theme: Theme,
    visible_periods: usize,
) -> Frame {
    let mut frame = Frame::new_styled(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
        theme.style_for(ThemeRole::Background),
    );
    let edge_style = theme.style_for(ThemeRole::Edge);
    let node_style = theme.style_for(ThemeRole::Node);
    let text_style = theme.style_for(ThemeRole::Text);
    let muted_style = theme.style_for(ThemeRole::Muted);
    if let Some(title) = &layout.title {
        write_text_safe(&mut frame, 0, 0, title, text_style.clone());
    }
    for section in &layout.sections {
        if let Some(label) = &section.label {
            write_text_safe(&mut frame, 0, section.y, label, muted_style.clone());
        }
        draw_horizontal(
            &mut frame,
            section.axis_start.x,
            section.axis_end.x,
            section.axis_start.y,
            palette.horizontal,
            edge_style.clone(),
        );
    }
    for period in layout.periods.iter().take(visible_periods) {
        draw_timeline_period(
            &mut frame,
            period,
            palette,
            node_style.clone(),
            text_style.clone(),
        );
    }
    frame
}

fn draw_timeline_period(
    frame: &mut Frame,
    period: &crate::layout::PositionedTimelinePeriod,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
) {
    put_safe(
        frame,
        period.point.x,
        period.point.y,
        'o',
        node_style.clone(),
    );
    if !period.events.is_empty() {
        draw_vertical(
            frame,
            period.point.x,
            period.point.y,
            period.point.y + period.events.len() as i32,
            palette.vertical,
            node_style,
        );
        put_safe(
            frame,
            period.point.x,
            period.point.y,
            'o',
            text_style.clone(),
        );
    }
    write_text_safe(
        frame,
        period.label_origin.x,
        period.label_origin.y,
        &period.label,
        text_style.clone(),
    );
    for (event, origin) in period.events.iter().zip(&period.event_origins) {
        write_text_safe(frame, origin.x, origin.y, event, text_style.clone());
    }
}

fn draw_mindmap_node(
    frame: &mut Frame,
    node: &PositionedMindmapNode,
    palette: GlyphPalette,
    node_style: CellStyle,
    text_style: CellStyle,
) {
    draw_box(frame, node.rect, palette, node_style.clone());
    decorate_mindmap_shape(frame, node, node_style);
    let label = mindmap_node_label(node);
    let x = node.rect.origin.x + ((node.rect.size.width - label.chars().count() as i32) / 2).max(1);
    write_text_safe(frame, x, node.rect.center().y, &label, text_style);
}

fn decorate_mindmap_shape(frame: &mut Frame, node: &PositionedMindmapNode, style: CellStyle) {
    let y = node.rect.center().y;
    let left = node.rect.origin.x;
    let right = node.rect.right().saturating_sub(1);
    match node.shape {
        MindmapShape::Default | MindmapShape::Square | MindmapShape::Rounded => {}
        MindmapShape::Circle => {
            put_safe(frame, left, y, '(', style.clone());
            put_safe(frame, right, y, ')', style);
        }
        MindmapShape::Bang => {
            put_safe(frame, left, y, '!', style.clone());
            put_safe(frame, right, y, '!', style);
        }
        MindmapShape::Cloud => {
            put_safe(frame, left, y, '~', style.clone());
            put_safe(frame, right, y, '~', style);
        }
        MindmapShape::Hexagon => {
            put_safe(frame, left, y, '<', style.clone());
            put_safe(frame, right, y, '>', style);
        }
    }
}

fn mindmap_node_label(node: &PositionedMindmapNode) -> String {
    node.icon.as_ref().map_or_else(
        || node.label.clone(),
        |icon| format!("{icon} {}", node.label),
    )
}

fn draw_class_node(
    frame: &mut Frame,
    node: &PositionedClassNode,
    palette: GlyphPalette,
    box_style: CellStyle,
    text_style: CellStyle,
) {
    fill_rect(frame, node.rect, ' ', box_style.clone());
    draw_vertical(
        frame,
        node.rect.origin.x,
        node.rect.origin.y,
        node.rect.bottom().saturating_sub(1),
        palette.vertical,
        box_style.clone(),
    );
    draw_vertical(
        frame,
        node.rect.right().saturating_sub(1),
        node.rect.origin.y,
        node.rect.bottom().saturating_sub(1),
        palette.vertical,
        box_style.clone(),
    );
    let mut y = node.rect.origin.y;
    draw_class_border(frame, node.rect, y, palette, box_style.clone());
    y += 1;
    for annotation in &node.annotations {
        write_text_safe(
            frame,
            node.rect.origin.x + 1,
            y,
            annotation,
            text_style.clone(),
        );
        y += 1;
    }
    write_text_safe(
        frame,
        node.rect.origin.x + 1,
        y,
        &node.id,
        text_style.clone(),
    );
    y += 1;
    draw_class_border(frame, node.rect, y, palette, box_style.clone());
    y += 1;

    let field_rows = if node.methods.is_empty() {
        node.fields.len()
    } else {
        node.fields.len().max(1)
    };
    for field in &node.fields {
        write_text_safe(frame, node.rect.origin.x + 1, y, field, text_style.clone());
        y += 1;
    }
    for _ in node.fields.len()..field_rows {
        y += 1;
    }
    if !node.fields.is_empty() || !node.methods.is_empty() {
        draw_class_border(frame, node.rect, y, palette, box_style.clone());
        y += 1;
    }
    for method in &node.methods {
        write_text_safe(frame, node.rect.origin.x + 1, y, method, text_style.clone());
        y += 1;
    }
    if !node.methods.is_empty() {
        draw_class_border(frame, node.rect, y, palette, box_style);
    }
}

fn draw_c4_element(
    frame: &mut Frame,
    element: &PositionedC4Element,
    palette: GlyphPalette,
    box_style: CellStyle,
    text_style: CellStyle,
) {
    fill_rect(frame, element.rect, ' ', box_style.clone());
    draw_vertical(
        frame,
        element.rect.origin.x,
        element.rect.origin.y,
        element.rect.bottom().saturating_sub(1),
        palette.vertical,
        box_style.clone(),
    );
    draw_vertical(
        frame,
        element.rect.right().saturating_sub(1),
        element.rect.origin.y,
        element.rect.bottom().saturating_sub(1),
        palette.vertical,
        box_style.clone(),
    );
    draw_class_border(
        frame,
        element.rect,
        element.rect.origin.y,
        palette,
        box_style.clone(),
    );
    write_c4_centered(
        frame,
        element.rect,
        element.rect.origin.y + 1,
        &element.label,
        text_style.clone(),
    );
    write_c4_centered(
        frame,
        element.rect,
        element.rect.origin.y + 2,
        &format!("[{}]", element.kind_label),
        text_style.clone(),
    );
    let rows = c4_element_rows(element);
    if !rows.is_empty() {
        draw_class_border(
            frame,
            element.rect,
            element.rect.origin.y + 3,
            palette,
            box_style.clone(),
        );
        for (index, row) in rows.iter().enumerate() {
            write_text_safe(
                frame,
                element.rect.origin.x + 1,
                element.rect.origin.y + 4 + index as i32,
                row,
                text_style.clone(),
            );
        }
    }
    draw_class_border(
        frame,
        element.rect,
        element.rect.bottom().saturating_sub(1),
        palette,
        box_style,
    );
}

fn draw_c4_boundary(
    frame: &mut Frame,
    boundary: &PositionedC4Boundary,
    palette: GlyphPalette,
    box_style: CellStyle,
    text_style: CellStyle,
) {
    fill_rect(frame, boundary.rect, ' ', box_style.clone());
    draw_vertical(
        frame,
        boundary.rect.origin.x,
        boundary.rect.origin.y,
        boundary.rect.bottom().saturating_sub(1),
        palette.vertical,
        box_style.clone(),
    );
    draw_vertical(
        frame,
        boundary.rect.right().saturating_sub(1),
        boundary.rect.origin.y,
        boundary.rect.bottom().saturating_sub(1),
        palette.vertical,
        box_style.clone(),
    );
    draw_class_border(
        frame,
        boundary.rect,
        boundary.rect.origin.y,
        palette,
        box_style.clone(),
    );
    write_c4_centered(
        frame,
        boundary.rect,
        boundary.rect.origin.y + 1,
        &boundary.label,
        text_style.clone(),
    );
    write_c4_centered(
        frame,
        boundary.rect,
        boundary.rect.origin.y + 2,
        &c4_boundary_secondary(boundary),
        text_style.clone(),
    );
    for (index, row) in boundary.style_rows.iter().enumerate() {
        write_c4_centered(
            frame,
            boundary.rect,
            boundary.rect.origin.y + 3 + index as i32,
            row,
            text_style.clone(),
        );
    }
    draw_class_border(
        frame,
        boundary.rect,
        boundary.rect.origin.y + boundary.header_height - 1,
        palette,
        box_style.clone(),
    );
    draw_class_border(
        frame,
        boundary.rect,
        boundary.rect.bottom().saturating_sub(1),
        palette,
        box_style,
    );
}

fn draw_c4_relationship(
    frame: &mut Frame,
    relationship: &PositionedC4Relationship,
    palette: GlyphPalette,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    let mut line_palette = palette;
    if relationship.kind == C4RelationshipKind::Back {
        line_palette.horizontal = ':';
        line_palette.vertical = ':';
    }
    draw_polyline(
        frame,
        &relationship.points,
        line_palette,
        edge_style.clone(),
    );
    if relationship.kind == C4RelationshipKind::Bidirectional
        && let Some(first) = relationship.points.first().copied()
    {
        put_safe(
            frame,
            first.x,
            first.y,
            dominant_start_arrowhead_for_points(&relationship.points, palette)
                .unwrap_or(palette.arrow_left),
            edge_style.clone(),
        );
    }
    if let Some(last) = relationship.points.last().copied() {
        put_safe(
            frame,
            last.x,
            last.y,
            dominant_end_arrowhead_for_points(&relationship.points, palette)
                .unwrap_or(palette.arrow_right),
            edge_style.clone(),
        );
    }
    if let Some(point) = c4_relationship_label_point(&relationship.points) {
        for (index, row) in c4_relationship_rows(relationship).iter().enumerate() {
            let width = row.chars().count() as i32;
            write_text_safe(
                frame,
                (point.x - width / 2).max(0),
                point.y + index as i32,
                row,
                text_style.clone(),
            );
        }
    }
}

fn c4_element_rows(element: &PositionedC4Element) -> Vec<String> {
    let mut rows = Vec::new();
    if let Some(technology) = &element.technology {
        rows.push(format!("technology: {technology}"));
    }
    if let Some(description) = &element.description {
        rows.push(description.clone());
    }
    rows.extend(element.style_rows.clone());
    rows
}

fn c4_boundary_secondary(boundary: &PositionedC4Boundary) -> String {
    match &boundary.ty {
        Some(ty) => format!("[{}] {ty}", boundary.kind_label),
        None => format!("[{}]", boundary.kind_label),
    }
}

fn c4_relationship_rows(relationship: &PositionedC4Relationship) -> Vec<String> {
    let mut rows = vec![relationship.label.clone()];
    rows.extend(relationship.style_rows.clone());
    rows
}

fn c4_relationship_label_point(points: &[Point]) -> Option<Point> {
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
    if let (Some(first), Some(last)) = (points.first(), points.last())
        && first.x == last.x
        && first.y != last.y
    {
        return Some(Point {
            x: first.x,
            y: first.y + (last.y - first.y).signum(),
        });
    }
    class_relationship_label_point(points)
}

fn write_c4_centered(frame: &mut Frame, rect: Rect, y: i32, text: &str, style: CellStyle) {
    let width = text.chars().count() as i32;
    let x = rect.origin.x + ((rect.size.width - width) / 2).max(1);
    write_text_safe(frame, x, y, text, style);
}

fn draw_requirement_node(
    frame: &mut Frame,
    node: &PositionedRequirementNode,
    palette: GlyphPalette,
    box_style: CellStyle,
    text_style: CellStyle,
) {
    fill_rect(frame, node.rect, ' ', box_style.clone());
    draw_vertical(
        frame,
        node.rect.origin.x,
        node.rect.origin.y,
        node.rect.bottom().saturating_sub(1),
        palette.vertical,
        box_style.clone(),
    );
    draw_vertical(
        frame,
        node.rect.right().saturating_sub(1),
        node.rect.origin.y,
        node.rect.bottom().saturating_sub(1),
        palette.vertical,
        box_style.clone(),
    );

    let mut y = node.rect.origin.y;
    draw_class_border(frame, node.rect, y, palette, box_style.clone());
    y += 1;
    write_requirement_centered(
        frame,
        node,
        y,
        &format!("<<{}>>", node.type_label),
        text_style.clone(),
    );
    y += 1;
    write_requirement_centered(frame, node, y, &node.name, text_style.clone());
    y += 1;
    if !node.rows.is_empty() {
        draw_class_border(frame, node.rect, y, palette, box_style.clone());
        y += 1;
        for row in &node.rows {
            write_text_safe(frame, node.rect.origin.x + 1, y, row, text_style.clone());
            y += 1;
        }
    }
    draw_class_border(
        frame,
        node.rect,
        node.rect.bottom().saturating_sub(1),
        palette,
        box_style,
    );
}

fn write_requirement_centered(
    frame: &mut Frame,
    node: &PositionedRequirementNode,
    y: i32,
    text: &str,
    style: CellStyle,
) {
    let width = text.chars().count() as i32;
    let x = node.rect.origin.x + ((node.rect.size.width - width) / 2).max(1);
    write_text_safe(frame, x, y, text, style);
}

fn fill_rect(frame: &mut Frame, rect: Rect, glyph: char, style: CellStyle) {
    for y in rect.origin.y..rect.bottom() {
        draw_horizontal(
            frame,
            rect.origin.x,
            rect.right() - 1,
            y,
            glyph,
            style.clone(),
        );
    }
}

fn draw_class_border(
    frame: &mut Frame,
    rect: Rect,
    y: i32,
    palette: GlyphPalette,
    style: CellStyle,
) {
    let left = rect.origin.x;
    let right = rect.right().saturating_sub(1);
    draw_horizontal(frame, left, right, y, palette.horizontal, style.clone());
    let (left_glyph, right_glyph) = if y == rect.origin.y {
        (palette.top_left, palette.top_right)
    } else if y == rect.bottom().saturating_sub(1) {
        (palette.bottom_left, palette.bottom_right)
    } else {
        (palette.crossing, palette.crossing)
    };
    put_safe(frame, left, y, left_glyph, style.clone());
    put_safe(frame, right, y, right_glyph, style);
}

fn draw_class_relationship(
    frame: &mut Frame,
    relationship: &PositionedClassRelationship,
    palette: GlyphPalette,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    let mut line_palette = palette;
    if relationship.line == ClassRelationshipLine::Dotted {
        line_palette.horizontal = ':';
        line_palette.vertical = ':';
    }
    draw_polyline(
        frame,
        &relationship.points,
        line_palette,
        edge_style.clone(),
    );
    if let Some(first) = relationship.points.first().copied()
        && let Some(glyph) =
            class_start_marker_for_points(relationship.start_marker, &relationship.points, palette)
    {
        put_safe(frame, first.x, first.y, glyph, edge_style.clone());
    }
    if let Some(last) = relationship.points.last().copied()
        && let Some(glyph) =
            class_end_marker_for_points(relationship.end_marker, &relationship.points, palette)
    {
        put_safe(frame, last.x, last.y, glyph, edge_style.clone());
    }
    if let Some(cardinality) = &relationship.start_cardinality
        && let Some([first, next, ..]) = relationship.points.first_chunk::<2>()
    {
        draw_class_cardinality(frame, cardinality, *first, *next, true, text_style.clone());
    }
    if let Some(cardinality) = &relationship.end_cardinality
        && let Some([.., previous, last]) = relationship.points.last_chunk::<2>()
    {
        draw_class_cardinality(
            frame,
            cardinality,
            *last,
            *previous,
            false,
            text_style.clone(),
        );
    }
    if let Some(label) = &relationship.label
        && let Some(point) = class_relationship_label_point(&relationship.points)
    {
        let x = point.x - (label.chars().count() as i32 / 2);
        write_text_safe(frame, x.max(0), point.y, label, text_style);
    }
}

fn draw_requirement_relationship(
    frame: &mut Frame,
    relationship: &PositionedRequirementRelationship,
    palette: GlyphPalette,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    let mut line_palette = palette;
    if relationship.kind != RequirementRelationshipKind::Contains {
        line_palette.horizontal = ':';
        line_palette.vertical = ':';
    }
    draw_polyline(
        frame,
        &relationship.points,
        line_palette,
        edge_style.clone(),
    );
    if let Some(point) = class_relationship_label_point(&relationship.points) {
        let width = relationship.label.chars().count() as i32;
        let mut x = point.x - width / 2;
        if let Some(first) = relationship.points.first()
            && relationship.kind == RequirementRelationshipKind::Contains
            && first.y == point.y
            && (x..x + width).contains(&first.x)
        {
            x = first.x + 2;
        }
        if let Some(last) = relationship.points.last()
            && relationship.kind != RequirementRelationshipKind::Contains
            && last.y == point.y
            && (x..x + width).contains(&last.x)
        {
            x = last.x - width - 2;
        }
        write_text_safe(frame, x.max(0), point.y, &relationship.label, text_style);
    }
    if let Some(first) = relationship.points.first().copied()
        && relationship.kind == RequirementRelationshipKind::Contains
    {
        put_safe(frame, first.x, first.y, '⊕', edge_style.clone());
    }
    if let Some(last) = relationship.points.last().copied()
        && relationship.kind != RequirementRelationshipKind::Contains
    {
        put_safe(
            frame,
            last.x,
            last.y,
            dominant_end_arrowhead_for_points(&relationship.points, palette)
                .unwrap_or(palette.arrow_right),
            edge_style.clone(),
        );
    }
}

fn draw_class_cardinality(
    frame: &mut Frame,
    cardinality: &str,
    endpoint: Point,
    adjacent: Point,
    is_start: bool,
    text_style: CellStyle,
) {
    let width = cardinality.chars().count() as i32;
    let dx = adjacent.x - endpoint.x;
    let dy = adjacent.y - endpoint.y;
    let (x, y) = if dx.abs() > dy.abs() {
        let y = endpoint.y.saturating_sub(1);
        let before_endpoint = if is_start { dx < 0 } else { dx >= 0 };
        if before_endpoint {
            (endpoint.x - width - 1, y)
        } else {
            (endpoint.x + 1, y)
        }
    } else {
        (endpoint.x + 2, endpoint.y)
    };

    write_text_safe(frame, x.max(0), y.max(0), cardinality, text_style);
}

fn class_relationship_label_point(points: &[Point]) -> Option<Point> {
    let first = points.first()?;
    let last = points.last()?;
    Some(Point {
        x: (first.x + last.x) / 2,
        y: (first.y + last.y) / 2,
    })
}

fn class_start_marker_for_points(
    marker: ClassRelationshipMarker,
    points: &[Point],
    palette: GlyphPalette,
) -> Option<char> {
    match marker {
        ClassRelationshipMarker::None => None,
        ClassRelationshipMarker::Arrow | ClassRelationshipMarker::Inheritance => {
            dominant_start_arrowhead_for_points(points, palette)
        }
        ClassRelationshipMarker::Aggregation => Some('o'),
        ClassRelationshipMarker::Composition => Some('*'),
        ClassRelationshipMarker::One => Some('|'),
        ClassRelationshipMarker::ZeroOrOne => Some('o'),
        ClassRelationshipMarker::Many | ClassRelationshipMarker::ZeroOrMany => Some('<'),
    }
}

fn class_end_marker_for_points(
    marker: ClassRelationshipMarker,
    points: &[Point],
    palette: GlyphPalette,
) -> Option<char> {
    match marker {
        ClassRelationshipMarker::None => None,
        ClassRelationshipMarker::Arrow | ClassRelationshipMarker::Inheritance => {
            dominant_end_arrowhead_for_points(points, palette)
        }
        ClassRelationshipMarker::Aggregation => Some('o'),
        ClassRelationshipMarker::Composition => Some('*'),
        ClassRelationshipMarker::One => Some('|'),
        ClassRelationshipMarker::ZeroOrOne => Some('o'),
        ClassRelationshipMarker::Many | ClassRelationshipMarker::ZeroOrMany => Some('<'),
    }
}

fn dominant_start_arrowhead_for_points(points: &[Point], palette: GlyphPalette) -> Option<char> {
    match points {
        [first, next, ..] => Some(dominant_arrowhead_for_segment(*next, *first, palette)),
        _ => Some(palette.arrow_left),
    }
}

fn dominant_end_arrowhead_for_points(points: &[Point], palette: GlyphPalette) -> Option<char> {
    match points {
        [.., previous, last] => Some(dominant_arrowhead_for_segment(*previous, *last, palette)),
        _ => Some(palette.arrow_right),
    }
}

fn dominant_arrowhead_for_segment(previous: Point, last: Point, palette: GlyphPalette) -> char {
    let dx = last.x - previous.x;
    let dy = last.y - previous.y;
    if dy.abs() >= dx.abs() {
        if dy < 0 {
            palette.arrow_up
        } else {
            palette.arrow_down
        }
    } else if dx < 0 {
        palette.arrow_left
    } else {
        palette.arrow_right
    }
}

fn draw_sequence_box(
    frame: &mut Frame,
    sequence_box: &PositionedSequenceBox,
    palette: GlyphPalette,
    box_style: CellStyle,
    text_style: CellStyle,
) {
    draw_box(frame, sequence_box.rect, palette, box_style);
    if let Some(label) = &sequence_box.label {
        write_text_safe(
            frame,
            sequence_box.rect.origin.x + 1,
            sequence_box.rect.origin.y,
            label,
            text_style,
        );
    }
}

fn sequence_control_label(kind: SequenceControlKind, label: Option<&str>) -> Option<String> {
    match kind {
        SequenceControlKind::Critical => Some(prefixed_sequence_label("critical", label)),
        SequenceControlKind::Break => Some(prefixed_sequence_label("break", label)),
        SequenceControlKind::Rect => Some(prefixed_sequence_label("rect", label)),
        SequenceControlKind::Loop
        | SequenceControlKind::Alt
        | SequenceControlKind::Opt
        | SequenceControlKind::Par => label.map(str::to_owned),
    }
}

fn prefixed_sequence_label(prefix: &str, label: Option<&str>) -> String {
    label.map_or_else(|| prefix.to_owned(), |label| format!("{prefix}: {label}"))
}

fn draw_sequence_note(
    frame: &mut Frame,
    note: &PositionedSequenceNote,
    palette: GlyphPalette,
    box_style: CellStyle,
    text_style: CellStyle,
) {
    draw_box(frame, note.rect, palette, box_style);
    write_text_safe(
        frame,
        note.rect.origin.x + 1,
        note.y,
        &note.label,
        text_style,
    );
}

fn draw_sequence_activation(
    frame: &mut Frame,
    activation: &PositionedSequenceActivation,
    palette: GlyphPalette,
    style: CellStyle,
) {
    draw_box(frame, activation.rect, palette, style);
}

fn draw_sequence_message(
    frame: &mut Frame,
    message: &PositionedSequenceMessage,
    palette: GlyphPalette,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    draw_polyline(frame, &message.points, palette, edge_style.clone());
    if let Some(label) = sequence_message_label(message) {
        let first = message.points.first().copied();
        let last = message.points.last().copied();
        if let (Some(first), Some(last)) = (first, last) {
            let x = first.x.min(last.x) + 1;
            write_text_safe(frame, x, message.y.saturating_sub(1), &label, text_style);
        }
    }
    if let Some(last) = message.points.last() {
        put_safe(
            frame,
            last.x,
            last.y,
            arrowhead_for_points(&message.points, palette),
            edge_style,
        );
    }
}

fn sequence_message_label(message: &PositionedSequenceMessage) -> Option<String> {
    match (&message.number, &message.label) {
        (Some(number), Some(label)) => Some(format!("{number}. {label}")),
        (Some(number), None) => Some(format!("{number}.")),
        (None, Some(label)) => Some(label.clone()),
        (None, None) => None,
    }
}

fn draw_sequence_destroy(frame: &mut Frame, destroy: &PositionedSequenceDestroy, style: CellStyle) {
    put_safe(frame, destroy.point.x, destroy.point.y, 'X', style.clone());
    put_safe(
        frame,
        destroy.point.x.saturating_sub(1),
        destroy.point.y,
        '-',
        style.clone(),
    );
    put_safe(frame, destroy.point.x + 1, destroy.point.y, '-', style);
}

fn draw_box(frame: &mut Frame, rect: Rect, palette: GlyphPalette, style: CellStyle) {
    let left = rect.origin.x;
    let right = rect.right().saturating_sub(1);
    let top = rect.origin.y;
    let bottom = rect.bottom().saturating_sub(1);
    for y in top + 1..bottom {
        draw_horizontal(frame, left + 1, right - 1, y, ' ', style.clone());
    }
    draw_horizontal(frame, left, right, top, palette.horizontal, style.clone());
    draw_horizontal(
        frame,
        left,
        right,
        bottom,
        palette.horizontal,
        style.clone(),
    );
    draw_vertical(frame, left, top, bottom, palette.vertical, style.clone());
    draw_vertical(frame, right, top, bottom, palette.vertical, style.clone());
    put_safe(frame, left, top, palette.top_left, style.clone());
    put_safe(frame, right, top, palette.top_right, style.clone());
    put_safe(frame, left, bottom, palette.bottom_left, style.clone());
    put_safe(frame, right, bottom, palette.bottom_right, style);
}

fn draw_polyline(frame: &mut Frame, points: &[Point], palette: GlyphPalette, style: CellStyle) {
    for pair in points.windows(2) {
        let start = pair[0];
        let end = pair[1];
        if start.x == end.x {
            draw_vertical(
                frame,
                start.x,
                start.y.min(end.y),
                start.y.max(end.y),
                palette.vertical,
                style.clone(),
            );
        } else if start.y == end.y {
            draw_horizontal(
                frame,
                start.x.min(end.x),
                start.x.max(end.x),
                start.y,
                palette.horizontal,
                style.clone(),
            );
        } else {
            draw_horizontal(
                frame,
                start.x.min(end.x),
                start.x.max(end.x),
                start.y,
                palette.horizontal,
                style.clone(),
            );
            draw_vertical(
                frame,
                end.x,
                start.y.min(end.y),
                start.y.max(end.y),
                palette.vertical,
                style.clone(),
            );
            put_safe(frame, end.x, start.y, palette.crossing, style.clone());
        }
    }
    for point in points.iter().skip(1).take(points.len().saturating_sub(2)) {
        put_safe(frame, point.x, point.y, palette.crossing, style.clone());
    }
}

fn arrowhead_for_points(points: &[Point], palette: GlyphPalette) -> char {
    match points {
        [.., previous, last] => arrowhead_for_segment(*previous, *last, palette),
        _ => palette.arrow_right,
    }
}

fn start_arrowhead_for_points(
    arrowhead: ArrowHead,
    points: &[Point],
    palette: GlyphPalette,
) -> Option<char> {
    match arrowhead {
        ArrowHead::None => None,
        ArrowHead::Arrow => match points {
            [first, next, ..] => Some(arrowhead_for_segment(*next, *first, palette)),
            _ => Some(palette.arrow_left),
        },
        ArrowHead::Circle => Some('o'),
        ArrowHead::Cross => Some('x'),
    }
}

fn end_arrowhead_for_points(
    arrowhead: ArrowHead,
    points: &[Point],
    palette: GlyphPalette,
) -> Option<char> {
    match arrowhead {
        ArrowHead::None => None,
        ArrowHead::Arrow => Some(arrowhead_for_points(points, palette)),
        ArrowHead::Circle => Some('o'),
        ArrowHead::Cross => Some('x'),
    }
}

fn arrowhead_for_segment(previous: Point, last: Point, palette: GlyphPalette) -> char {
    if last.x < previous.x {
        palette.arrow_left
    } else if last.x > previous.x {
        palette.arrow_right
    } else if last.y < previous.y {
        palette.arrow_up
    } else if last.y > previous.y {
        palette.arrow_down
    } else {
        palette.arrow_right
    }
}

fn draw_horizontal(
    frame: &mut Frame,
    start_x: i32,
    end_x: i32,
    y: i32,
    glyph: char,
    style: CellStyle,
) {
    for x in start_x..=end_x {
        put_safe(frame, x, y, glyph, style.clone());
    }
}

fn draw_straight_line(frame: &mut Frame, start: Point, end: Point, glyph: char, style: CellStyle) {
    let mut x = start.x;
    let mut y = start.y;
    let dx = (end.x - start.x).abs();
    let sx = if start.x < end.x { 1 } else { -1 };
    let dy = -(end.y - start.y).abs();
    let sy = if start.y < end.y { 1 } else { -1 };
    let mut error = dx + dy;
    loop {
        put_safe(frame, x, y, glyph, style.clone());
        if x == end.x && y == end.y {
            break;
        }
        let doubled = 2 * error;
        if doubled >= dy {
            error += dy;
            x += sx;
        }
        if doubled <= dx {
            error += dx;
            y += sy;
        }
    }
}

fn draw_vertical(
    frame: &mut Frame,
    x: i32,
    start_y: i32,
    end_y: i32,
    glyph: char,
    style: CellStyle,
) {
    for y in start_y..=end_y {
        put_safe(frame, x, y, glyph, style.clone());
    }
}

fn write_centered(frame: &mut Frame, rect: Rect, text: &str, style: CellStyle) {
    let lines = text.lines().collect::<Vec<_>>();
    let lines = if lines.is_empty() { vec![""] } else { lines };
    let start_y = rect.origin.y + rect.size.height / 2 - lines.len() as i32 / 2;
    for (offset, line) in lines.iter().enumerate() {
        let width = line.chars().count() as i32;
        let x = rect.origin.x + (rect.size.width - width).max(0) / 2;
        write_text_safe(frame, x, start_y + offset as i32, line, style.clone());
    }
}

fn write_text_safe(frame: &mut Frame, x: i32, y: i32, text: &str, style: CellStyle) {
    if let (Ok(x), Ok(y)) = (usize::try_from(x), usize::try_from(y)) {
        let _ = frame.write_text(x, y, text, style);
    }
}

fn put_safe(frame: &mut Frame, x: i32, y: i32, glyph: char, style: CellStyle) {
    if let (Ok(x), Ok(y)) = (usize::try_from(x), usize::try_from(y)) {
        let _ = frame.put_styled_glyph(x, y, glyph, style);
    }
}

#[cfg(test)]
mod tests {
    use super::{
        CellStyle, Charset, Color, Frame, FrameError, FrameRegion, GlyphCell, GlyphPalette,
        KeyFrameMarker, KeyFrameMarkerKind, StaticFrameRenderer,
    };
    use crate::ast::{
        ArrowHead, Diagram, DiagramKind, DiagramMetadata, Direction, FlowEdge, FlowEdgeLink,
        FlowEdgeStroke, FlowNode, FlowShape, FlowStatement, FlowSubgraph, FlowchartAst,
        FlowchartDirective, FlowchartHeader, Label, LabelKind, SequenceArrow, SequenceAst,
        SequenceHeader, SequenceMessage, SequenceStatement, Span, Spanned, StateAst,
        StateDirective, StateHeader, StateStatement, StateTransition,
    };
    use crate::parser::Parser;
    use crate::theme::Theme;

    #[test]
    fn creates_blank_frame_grid() {
        let frame = Frame::new(3, 2);

        assert_eq!(frame.width(), 3);
        assert_eq!(frame.height(), 2);
        assert_eq!(frame.cells().len(), 6);
        assert_eq!(frame.cell(2, 1).unwrap().glyph, ' ');
    }

    #[test]
    fn sets_cells_and_rejects_out_of_bounds_coordinates() {
        let mut frame = Frame::new(2, 1);

        frame
            .set_cell(
                1,
                0,
                GlyphCell {
                    glyph: 'A',
                    style: CellStyle {
                        foreground: Some(Color::Ansi(2)),
                        ..CellStyle::default()
                    },
                    marker: None,
                },
            )
            .unwrap();

        assert_eq!(frame.cell(1, 0).unwrap().glyph, 'A');
        assert_eq!(
            frame.put_glyph(2, 0, 'B').unwrap_err(),
            FrameError::OutOfBounds { x: 2, y: 0 },
        );
    }

    #[test]
    fn creates_styled_frame_grid() {
        let style = CellStyle {
            background: Some(Color::Rgb {
                red: 1,
                green: 2,
                blue: 3,
            }),
            ..CellStyle::default()
        };
        let frame = Frame::new_styled(2, 1, style.clone());

        assert_eq!(frame.cell(0, 0).unwrap().style, style);
        assert_eq!(frame.cell(1, 0).unwrap().glyph, ' ');
    }

    #[test]
    fn writes_text_until_frame_edge() {
        let mut frame = Frame::new(4, 1);
        let written = frame
            .write_text(
                1,
                0,
                "abcd",
                CellStyle {
                    bold: true,
                    ..CellStyle::default()
                },
            )
            .unwrap();

        assert_eq!(written, 3);
        assert_eq!(frame.cell(1, 0).unwrap().glyph, 'a');
        assert!(frame.cell(3, 0).unwrap().style.bold);
    }

    #[test]
    fn write_text_applies_bidi_visual_order() {
        let mut frame = Frame::new(6, 1);
        frame
            .write_text(0, 0, "A אבג", CellStyle::default())
            .unwrap();

        assert_eq!(frame.to_lines(), vec!["A גבא "]);
    }

    #[test]
    fn can_extend_frame_width_without_moving_content() {
        let mut frame = Frame::new(2, 1);
        frame.write_text(0, 0, "AB", CellStyle::default()).unwrap();
        frame.add_marker(KeyFrameMarker {
            id: "active".to_owned(),
            kind: KeyFrameMarkerKind::Active,
            region: FrameRegion {
                x: 0,
                y: 0,
                width: 2,
                height: 1,
            },
        });

        let widened = frame.with_min_width(4);

        assert_eq!(widened.width(), 4);
        assert_eq!(widened.to_lines(), vec!["AB  "]);
        assert_eq!(widened.markers(), frame.markers());
        assert_eq!(frame.with_min_width(1), frame);
    }

    #[test]
    fn stores_keyframe_markers_and_cell_marker_refs() {
        let mut frame = Frame::new(2, 2);
        frame.add_marker(KeyFrameMarker {
            id: "msg-1".to_owned(),
            kind: KeyFrameMarkerKind::Active,
            region: FrameRegion {
                x: 0,
                y: 0,
                width: 2,
                height: 1,
            },
        });
        frame.mark_cell(1, 1, "msg-1").unwrap();

        assert_eq!(frame.markers().len(), 1);
        assert_eq!(frame.cell(1, 1).unwrap().marker.as_deref(), Some("msg-1"));
    }

    #[test]
    fn exposes_ascii_and_unicode_glyph_palettes() {
        assert_eq!(GlyphPalette::ascii().horizontal, '-');
        assert_eq!(GlyphPalette::ascii().arrow_right, '>');
        assert_eq!(GlyphPalette::unicode().top_left, '┌');
        assert_eq!(GlyphPalette::unicode().arrow_right, '▶');
        assert_eq!(GlyphPalette::for_charset(Charset::Unicode).block, '█');
    }

    #[test]
    fn renders_flowchart_ast_to_single_frame() {
        let frame =
            StaticFrameRenderer::default().render_flowchart(&flowchart(vec![FlowStatement::Edge(
                Box::new(flow_edge("A", "B")),
            )]));
        let output = frame.to_lines().join("\n");

        assert!(output.contains('A'));
        assert!(output.contains('B'));
        assert!(output.contains('+'));
        assert!(output.contains('-'));
        assert!(output.contains('v'));
    }

    #[test]
    fn renders_flowchart_with_unicode_box_drawing_palette() {
        let frame = StaticFrameRenderer::default()
            .with_glyph_charset(Charset::Unicode)
            .render_flowchart(&flowchart(vec![FlowStatement::Edge(Box::new(flow_edge(
                "A", "B",
            )))]));
        let output = frame.to_lines().join("\n");

        assert!(output.contains('┌'));
        assert!(output.contains('─'));
        assert!(output.contains('│'));
    }

    #[test]
    fn renders_flowchart_subgraph_box() {
        let frame = StaticFrameRenderer::default().render_flowchart(&flowchart(vec![
            FlowStatement::Subgraph(FlowSubgraph {
                id: Spanned::new("group".to_owned(), Span::new(0, 0)),
                label: None,
                direction: None,
                statements: vec![FlowStatement::Edge(Box::new(flow_edge("A", "B")))],
                span: Span::new(0, 0),
            }),
        ]));
        let output = frame.to_lines().join("\n");

        assert!(output.contains("group"));
        assert!(output.contains("| +---+ |"));
    }

    #[test]
    fn renders_flowchart_with_theme_styles() {
        let theme = Theme::tokyo_night();
        let renderer = StaticFrameRenderer::default().with_theme(theme);
        let frame = renderer.render_flowchart(&flowchart(vec![FlowStatement::Edge(Box::new(
            flow_edge("A", "B"),
        ))]));
        let output = frame.to_lines().join("\n");

        assert_eq!(renderer.theme(), theme);
        assert_eq!(renderer.palette(), GlyphPalette::unicode());
        assert!(output.contains('┌'));
        assert!(frame.cells().iter().any(|cell| {
            cell.style.background == Some(Color::from(theme.colors.background))
                && cell.style.foreground == Some(Color::from(theme.colors.accent))
                && cell.style.bold
        }));
    }

    #[test]
    fn renders_sequence_ast_to_single_frame() {
        let frame = StaticFrameRenderer::default().render_sequence(&SequenceAst {
            header: SequenceHeader {
                span: Span::new(0, 15),
            },
            statements: vec![SequenceStatement::Message(Box::new(SequenceMessage {
                from: Spanned::new("Alice".to_owned(), Span::new(0, 0)),
                to: Spanned::new("Bob".to_owned(), Span::new(0, 0)),
                arrow: SequenceArrow::SolidArrow,
                activation: None,
                label: Some(label("hello")),
                span: Span::new(0, 0),
            }))],
            participants: Vec::new(),
            boxes: Vec::new(),
            span: Span::new(0, 0),
        });
        let output = frame.to_lines().join("\n");

        assert!(output.contains("Alice"));
        assert!(output.contains("Bob"));
        assert!(output.contains("hello"));
    }

    #[test]
    fn renders_sequence_with_unicode_arrow_palette() {
        let frame = StaticFrameRenderer::default()
            .with_glyph_charset(Charset::Unicode)
            .render_sequence(&SequenceAst {
                header: SequenceHeader {
                    span: Span::new(0, 15),
                },
                statements: vec![SequenceStatement::Message(Box::new(SequenceMessage {
                    from: Spanned::new("Alice".to_owned(), Span::new(0, 0)),
                    to: Spanned::new("Bob".to_owned(), Span::new(0, 0)),
                    arrow: SequenceArrow::SolidArrow,
                    activation: None,
                    label: Some(label("hello")),
                    span: Span::new(0, 0),
                }))],
                participants: Vec::new(),
                boxes: Vec::new(),
                span: Span::new(0, 0),
            });
        let output = frame.to_lines().join("\n");

        assert!(output.contains('▶'));
        assert!(output.contains('─'));
    }

    #[test]
    fn renders_state_ast_to_single_frame_through_diagram_root() {
        let state = StateAst {
            header: StateHeader {
                directive: StateDirective::StateDiagramV2,
                span: Span::new(0, 15),
            },
            direction: Some(Spanned::new(Direction::LeftRight, Span::new(0, 0))),
            statements: vec![StateStatement::Transition(Box::new(StateTransition {
                from: Spanned::new("[*]".to_owned(), Span::new(0, 0)),
                to: Spanned::new("Idle".to_owned(), Span::new(0, 0)),
                label: Some(label("boot")),
                span: Span::new(0, 0),
            }))],
            states: Vec::new(),
            transitions: Vec::new(),
            classes: Vec::new(),
            span: Span::new(0, 0),
        };
        let frame = StaticFrameRenderer::default().render_diagram(&Diagram {
            metadata: DiagramMetadata {
                title: None,
                accessibility_title: None,
                accessibility_description: None,
                span: Span::new(0, 0),
            },
            directives: Vec::new(),
            kind: DiagramKind::State(Box::new(state)),
            span: Span::new(0, 0),
        });
        let output = frame.to_lines().join("\n");

        assert!(output.contains("[*]"));
        assert!(output.contains("Idle"));
    }

    #[test]
    fn renders_class_ast_to_single_frame_through_diagram_root() {
        let diagram = Parser::parse_diagram(
            "classDiagram\nclass Animal {\n+String name\n+eat() void\n}\nAnimal <|-- Dog",
        )
        .unwrap();
        let frame = StaticFrameRenderer::default().render_diagram(&diagram);
        let output = frame.to_lines().join("\n");

        assert!(output.contains("Animal"));
        assert!(output.contains("+name: String"));
        assert!(output.contains("+eat: void"));
        assert!(output.contains("Dog"));
    }

    #[test]
    fn renders_er_ast_to_single_frame_through_diagram_root() {
        let diagram = Parser::parse_diagram(
            "erDiagram\nCUSTOMER {\nstring name PK\n}\nCUSTOMER ||--o{ ORDER : places",
        )
        .unwrap();
        let frame = StaticFrameRenderer::default().render_diagram(&diagram);
        let output = frame.to_lines().join("\n");

        assert!(output.contains("CUSTOMER"));
        assert!(output.contains("PK string name"));
        assert!(output.contains("ORDER"));
        assert!(output.contains("places"));
    }

    #[test]
    fn renders_gantt_ast_to_single_frame_through_diagram_root() {
        let diagram = Parser::parse_diagram(
            "gantt\ntitle Release Plan\nsection Build\nDesign API :done, api, 2026-01-01, 3d\nImplement core :active, core, after api, 5d",
        )
        .unwrap();
        let frame = StaticFrameRenderer::default().render_diagram(&diagram);
        let output = frame.to_lines().join("\n");

        assert!(output.contains("Release Plan"));
        assert!(output.contains("Build"));
        assert!(output.contains("Design API"));
        assert!(output.contains("Implement core"));
    }

    #[test]
    fn renders_pie_ast_to_single_frame_through_diagram_root() {
        let diagram =
            Parser::parse_diagram("pie showData title Pets\n\"Dogs\" : 386\n\"Cats\" : 85.50")
                .unwrap();
        let frame = StaticFrameRenderer::default().render_diagram(&diagram);
        let output = frame.to_lines().join("\n");

        assert!(output.contains("Pets"));
        assert!(output.contains("Dogs"));
        assert!(output.contains("386"));
        assert!(output.contains("Cats"));
        assert!(output.contains("85.50"));
    }

    #[test]
    fn renders_mindmap_ast_to_single_frame_through_diagram_root() {
        let diagram = Parser::parse_diagram(
            "mindmap\n  Root\n    Branch A\n      Leaf A1\n    Branch B\n      ::icon(fa fa-code)",
        )
        .unwrap();
        let frame = StaticFrameRenderer::default().render_diagram(&diagram);
        let output = frame.to_lines().join("\n");

        assert!(output.contains("Root"));
        assert!(output.contains("Branch A"));
        assert!(output.contains("Leaf A1"));
        assert!(output.contains("fa fa-code Branch B"));
    }

    #[test]
    fn renders_journey_ast_to_single_frame_through_diagram_root() {
        let diagram = Parser::parse_diagram(
            "journey\ntitle Working Day\nsection Go to work\nMake tea: 5: Me\nDo work: 1: Me",
        )
        .unwrap();
        let frame = StaticFrameRenderer::default().render_diagram(&diagram);
        let output = frame.to_lines().join("\n");

        assert!(output.contains("Working Day"));
        assert!(output.contains("Go to work"));
        assert!(output.contains("Make tea"));
        assert!(output.contains("5/5"));
        assert!(output.contains("Do work"));
        assert!(output.contains("1/5"));
    }

    #[test]
    fn renders_gitgraph_ast_to_single_frame_through_diagram_root() {
        let diagram = Parser::parse_diagram(
            r#"gitGraph
commit id: "base"
branch develop
commit id: "feat" type: HIGHLIGHT tag: "v1"
checkout main
merge develop id: "merge""#,
        )
        .unwrap();
        let frame = StaticFrameRenderer::default().render_diagram(&diagram);
        let output = frame.to_lines().join("\n");

        assert!(output.contains("main"));
        assert!(output.contains("develop"));
        assert!(output.contains("base"));
        assert!(output.contains("feat"));
        assert!(output.contains("[v1]"));
        assert!(output.contains("merge"));
    }

    #[test]
    fn renders_timeline_ast_to_single_frame_through_diagram_root() {
        let diagram = Parser::parse_diagram(
            "timeline\ntitle Release Train\nsection Alpha\n2024 Q1 : Design : Prototype\n        : Validate",
        )
        .unwrap();
        let frame = StaticFrameRenderer::default().render_diagram(&diagram);
        let output = frame.to_lines().join("\n");

        assert!(output.contains("Release Train"));
        assert!(output.contains("Alpha"));
        assert!(output.contains("2024 Q1"));
        assert!(output.contains("Design"));
        assert!(output.contains("Prototype"));
        assert!(output.contains("Validate"));
    }

    fn flowchart(statements: Vec<FlowStatement>) -> FlowchartAst {
        FlowchartAst {
            header: FlowchartHeader {
                directive: Spanned::new(FlowchartDirective::Graph, Span::new(0, 5)),
                direction: Spanned::new(Direction::TopDown, Span::new(6, 8)),
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

    fn flow_edge(from: &str, to: &str) -> FlowEdge {
        FlowEdge {
            from: flow_node(from),
            to: flow_node(to),
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

    fn flow_node(id: &str) -> FlowNode {
        FlowNode {
            id: Spanned::new(id.to_owned(), Span::new(0, 0)),
            label: Some(label(id)),
            shape: Spanned::new(FlowShape::Rectangle, Span::new(0, 0)),
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
}
