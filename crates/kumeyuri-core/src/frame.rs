use crate::ast::{ArrowHead, Diagram, DiagramKind, FlowchartAst, SequenceAst, StateAst};
use crate::layout::{
    FlowLayout, FlowLayoutEngine, Point, PositionedFlowEdge, PositionedFlowSubgraph,
    PositionedSequenceMessage, PositionedSequenceNote, Rect, SequenceLayout, SequenceLayoutEngine,
    StateLayoutEngine,
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
        draw_box(&mut frame, node.rect, palette, node_style.clone());
        write_centered(&mut frame, node.rect, &node.label, text_style.clone());
    }
    frame
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
    for control in &layout.controls {
        draw_box(&mut frame, control.rect, palette, muted_style.clone());
        if let Some(label) = &control.label {
            write_text_safe(
                &mut frame,
                control.rect.origin.x + 1,
                control.y,
                label,
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
    for message in &layout.messages {
        draw_sequence_message(
            &mut frame,
            message,
            palette,
            edge_style.clone(),
            text_style.clone(),
        );
    }
    frame
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

fn draw_sequence_message(
    frame: &mut Frame,
    message: &PositionedSequenceMessage,
    palette: GlyphPalette,
    edge_style: CellStyle,
    text_style: CellStyle,
) {
    draw_polyline(frame, &message.points, palette, edge_style.clone());
    if let Some(label) = &message.label {
        let first = message.points.first().copied();
        let last = message.points.last().copied();
        if let (Some(first), Some(last)) = (first, last) {
            let x = first.x.min(last.x) + 1;
            write_text_safe(frame, x, message.y.saturating_sub(1), label, text_style);
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

fn draw_box(frame: &mut Frame, rect: Rect, palette: GlyphPalette, style: CellStyle) {
    let left = rect.origin.x;
    let right = rect.right().saturating_sub(1);
    let top = rect.origin.y;
    let bottom = rect.bottom().saturating_sub(1);
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
