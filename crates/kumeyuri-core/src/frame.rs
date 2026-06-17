use crate::ast::{
    ArrowHead, C4Ast, C4RelationshipKind, ClassAst, ClassRelationshipLine,
    ClassRelationshipMarker, Diagram, DiagramKind, ErAst, FlowShape, FlowchartAst, GanttAst,
    GanttTaskTag, GitGraphAst, GitGraphCommitKind, JourneyAst, MindmapAst, MindmapShape, PieAst,
    RequirementAst, RequirementRelationshipKind, SequenceAst, SequenceControlKind, StateAst,
    TimelineAst,
};
use crate::layout::{
    C4Layout, C4LayoutEngine, ClassLayout, ClassLayoutEngine, ErLayoutEngine, FlowLayout,
    FlowLayoutEngine, GanttLayout, GanttLayoutEngine, GitGraphLayout, GitGraphLayoutEngine,
    JourneyLayout, JourneyLayoutEngine, MindmapLayout, MindmapLayoutEngine, PieLayout,
    PieLayoutEngine, Point, PositionedC4Boundary, PositionedC4Element, PositionedC4Relationship,
    PositionedClassNode, PositionedClassRelationship, PositionedFlowEdge, PositionedFlowNode,
    PositionedFlowSubgraph, PositionedGanttTask, PositionedGitGraphCommit, PositionedJourneyTask,
    PositionedMindmapNode, PositionedPieSlice, PositionedRequirementNode,
    PositionedRequirementRelationship, PositionedSequenceActivation, PositionedSequenceBox,
    PositionedSequenceDestroy, PositionedSequenceMessage, PositionedSequenceNote, Rect,
    RequirementLayout, RequirementLayoutEngine, SequenceLayout, SequenceLayoutEngine,
    StateLayoutEngine, TimelineLayout, TimelineLayoutEngine,
};
use crate::theme::{Theme, ThemeRole};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    width: usize,
    height: usize,
    cells: Vec<GlyphCell>,
    markers: Vec<KeyFrameMarker>,
}

impl Frame {
    #[must_use]
    pub fn new(width: usize, height: usize) -> Self {
        Self {
            width,
            height,
            cells: vec![GlyphCell::default(); width.saturating_mul(height)],
            markers: Vec::new(),
        }
    }

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

    #[must_use]
    pub const fn width(&self) -> usize {
        self.width
    }

    #[must_use]
    pub const fn height(&self) -> usize {
        self.height
    }

    #[must_use]
    pub fn cells(&self) -> &[GlyphCell] {
        &self.cells
    }

    #[must_use]
    pub fn markers(&self) -> &[KeyFrameMarker] {
        &self.markers
    }

    pub fn cell(&self, x: usize, y: usize) -> Result<&GlyphCell, FrameError> {
        let index = self.index(x, y)?;
        Ok(&self.cells[index])
    }

    pub fn set_cell(&mut self, x: usize, y: usize, cell: GlyphCell) -> Result<(), FrameError> {
        let index = self.index(x, y)?;
        self.cells[index] = cell;
        Ok(())
    }

    pub fn put_glyph(&mut self, x: usize, y: usize, glyph: char) -> Result<(), FrameError> {
        let index = self.index(x, y)?;
        self.cells[index].glyph = glyph;
        Ok(())
    }

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

    pub fn add_marker(&mut self, marker: KeyFrameMarker) {
        self.markers.push(marker);
    }

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GlyphCell {
    pub glyph: char,
    pub style: CellStyle,
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

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct CellStyle {
    pub foreground: Option<Color>,
    pub background: Option<Color>,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Color {
    Ansi(u8),
    Rgb { red: u8, green: u8, blue: u8 },
    Theme(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyFrameMarker {
    pub id: String,
    pub kind: KeyFrameMarkerKind,
    pub region: FrameRegion,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyFrameMarkerKind {
    Enter,
    Active,
    Exit,
    Hold,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameRegion {
    pub x: usize,
    pub y: usize,
    pub width: usize,
    pub height: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrameError {
    OutOfBounds { x: usize, y: usize },
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum Charset {
    #[default]
    Ascii,
    Unicode,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GlyphPalette {
    pub horizontal: char,
    pub vertical: char,
    pub top_left: char,
    pub top_right: char,
    pub bottom_left: char,
    pub bottom_right: char,
    pub crossing: char,
    pub arrow_left: char,
    pub arrow_right: char,
    pub arrow_up: char,
    pub arrow_down: char,
    pub block: char,
}

impl GlyphPalette {
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

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct StaticFrameRenderer {
    flow: FlowLayoutEngine,
    sequence: SequenceLayoutEngine,
    state: StateLayoutEngine,
    class: ClassLayoutEngine,
    er: ErLayoutEngine,
    gantt: GanttLayoutEngine,
    pie: PieLayoutEngine,
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

    #[must_use]
    pub const fn with_glyph_palette(mut self, palette: GlyphPalette) -> Self {
        self.palette = palette;
        self
    }

    #[must_use]
    pub const fn with_glyph_charset(self, charset: Charset) -> Self {
        self.with_glyph_palette(GlyphPalette::for_charset(charset))
    }

    #[must_use]
    pub const fn with_theme(mut self, theme: Theme) -> Self {
        self.palette = GlyphPalette::for_charset(theme.charset);
        self.theme = theme;
        self
    }

    #[must_use]
    pub const fn palette(&self) -> GlyphPalette {
        self.palette
    }

    #[must_use]
    pub const fn theme(&self) -> Theme {
        self.theme
    }

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
            DiagramKind::Mindmap(ast) => self.render_mindmap(ast),
            DiagramKind::Journey(ast) => self.render_journey(ast),
            DiagramKind::GitGraph(ast) => self.render_gitgraph(ast),
            DiagramKind::Timeline(ast) => self.render_timeline(ast),
            DiagramKind::Requirement(ast) => self.render_requirement(ast),
            DiagramKind::C4(ast) => self.render_c4(ast),
        }
    }

    #[must_use]
    pub fn render_flowchart(&self, ast: &FlowchartAst) -> Frame {
        render_flow_layout(&self.flow.layout(ast), self.palette, self.theme)
    }

    #[must_use]
    pub fn render_sequence(&self, ast: &SequenceAst) -> Frame {
        render_sequence_layout(&self.sequence.layout(ast), self.palette, self.theme)
    }

    #[must_use]
    pub fn render_state(&self, ast: &StateAst) -> Frame {
        render_flow_layout(&self.state.layout(ast).graph, self.palette, self.theme)
    }

    #[must_use]
    pub fn render_class(&self, ast: &ClassAst) -> Frame {
        render_class_layout(&self.class.layout(ast), self.palette, self.theme)
    }

    #[must_use]
    pub fn render_er(&self, ast: &ErAst) -> Frame {
        render_class_layout(&self.er.layout(ast), self.palette, self.theme)
    }

    #[must_use]
    pub fn render_requirement(&self, ast: &RequirementAst) -> Frame {
        render_requirement_layout(&self.requirement.layout(ast), self.palette, self.theme)
    }

    #[must_use]
    pub fn render_c4(&self, ast: &C4Ast) -> Frame {
        render_c4_layout(&self.c4.layout(ast), self.palette, self.theme)
    }

    #[must_use]
    pub fn render_gantt(&self, ast: &GanttAst) -> Frame {
        render_gantt_layout(&self.gantt.layout(ast), self.palette, self.theme)
    }

    #[must_use]
    pub fn render_pie(&self, ast: &PieAst) -> Frame {
        self.render_pie_progress(ast, ast.slices.len())
    }

    #[must_use]
    pub fn render_pie_progress(&self, ast: &PieAst, visible_slices: usize) -> Frame {
        render_pie_layout(
            &self.pie.layout(ast),
            self.palette,
            self.theme,
            visible_slices,
        )
    }

    #[must_use]
    pub fn render_mindmap(&self, ast: &MindmapAst) -> Frame {
        self.render_mindmap_progress(ast, usize::MAX)
    }

    #[must_use]
    pub fn render_mindmap_progress(&self, ast: &MindmapAst, visible_depth: usize) -> Frame {
        render_mindmap_layout(
            &self.mindmap.layout(ast),
            self.palette,
            self.theme,
            visible_depth,
        )
    }

    #[must_use]
    pub fn render_journey(&self, ast: &JourneyAst) -> Frame {
        self.render_journey_progress(ast, ast.tasks.len())
    }

    #[must_use]
    pub fn render_journey_progress(&self, ast: &JourneyAst, visible_tasks: usize) -> Frame {
        render_journey_layout(
            &self.journey.layout(ast),
            self.palette,
            self.theme,
            visible_tasks,
        )
    }

    #[must_use]
    pub fn render_gitgraph(&self, ast: &GitGraphAst) -> Frame {
        self.render_gitgraph_progress(
            ast,
            ast.commits.len() + ast.merges.len() + ast.cherry_picks.len(),
        )
    }

    #[must_use]
    pub fn render_gitgraph_progress(&self, ast: &GitGraphAst, visible_commits: usize) -> Frame {
        render_gitgraph_layout(
            &self.gitgraph.layout(ast),
            self.palette,
            self.theme,
            visible_commits,
        )
    }

    #[must_use]
    pub fn render_timeline(&self, ast: &TimelineAst) -> Frame {
        self.render_timeline_progress(ast, ast.periods.len())
    }

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
    let width = text.chars().count() as i32;
    let x = rect.origin.x + (rect.size.width - width).max(0) / 2;
    let y = rect.origin.y + rect.size.height / 2;
    write_text_safe(frame, x, y, text, style);
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
