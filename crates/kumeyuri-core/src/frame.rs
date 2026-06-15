use crate::ast::{Diagram, DiagramKind, FlowchartAst, SequenceAst, StateAst};
use crate::layout::{
    FlowLayout, FlowLayoutEngine, PositionedSequenceMessage, PositionedSequenceNote, Rect,
    SequenceLayout, SequenceLayoutEngine, StateLayoutEngine,
};

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
pub struct StaticFrameRenderer {
    flow: FlowLayoutEngine,
    sequence: SequenceLayoutEngine,
    state: StateLayoutEngine,
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
        }
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
        render_flow_layout(&self.flow.layout(ast))
    }

    #[must_use]
    pub fn render_sequence(&self, ast: &SequenceAst) -> Frame {
        render_sequence_layout(&self.sequence.layout(ast))
    }

    #[must_use]
    pub fn render_state(&self, ast: &StateAst) -> Frame {
        render_flow_layout(&self.state.layout(ast).graph)
    }
}

fn render_flow_layout(layout: &FlowLayout) -> Frame {
    let mut frame = Frame::new(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
    );
    for edge in &layout.edges {
        if edge.points.len() >= 2 {
            draw_polyline(&mut frame, &edge.points, '-');
        }
    }
    for node in &layout.nodes {
        draw_box(&mut frame, node.rect);
        write_centered(&mut frame, node.rect, &node.label);
    }
    frame
}

fn render_sequence_layout(layout: &SequenceLayout) -> Frame {
    let mut frame = Frame::new(
        layout.size.width as usize + 1,
        layout.size.height as usize + 1,
    );
    for participant in &layout.participants {
        draw_box(&mut frame, participant.header);
        write_centered(&mut frame, participant.header, &participant.label);
        draw_vertical(
            &mut frame,
            participant.lane_x,
            participant.header.bottom(),
            layout.size.height,
            '|',
        );
    }
    for control in &layout.controls {
        draw_box(&mut frame, control.rect);
        if let Some(label) = &control.label {
            write_text_safe(&mut frame, control.rect.origin.x + 1, control.y, label);
        }
    }
    for note in &layout.notes {
        draw_sequence_note(&mut frame, note);
    }
    for message in &layout.messages {
        draw_sequence_message(&mut frame, message);
    }
    frame
}

fn draw_sequence_note(frame: &mut Frame, note: &PositionedSequenceNote) {
    draw_box(frame, note.rect);
    write_text_safe(frame, note.rect.origin.x + 1, note.y, &note.label);
}

fn draw_sequence_message(frame: &mut Frame, message: &PositionedSequenceMessage) {
    draw_polyline(frame, &message.points, '-');
    if let Some(label) = &message.label {
        let first = message.points.first().copied();
        let last = message.points.last().copied();
        if let (Some(first), Some(last)) = (first, last) {
            let x = first.x.min(last.x) + 1;
            write_text_safe(frame, x, message.y.saturating_sub(1), label);
        }
    }
    if let Some(last) = message.points.last() {
        put_safe(frame, last.x, last.y, '>');
    }
}

fn draw_box(frame: &mut Frame, rect: Rect) {
    let left = rect.origin.x;
    let right = rect.right().saturating_sub(1);
    let top = rect.origin.y;
    let bottom = rect.bottom().saturating_sub(1);
    draw_horizontal(frame, left, right, top, '-');
    draw_horizontal(frame, left, right, bottom, '-');
    draw_vertical(frame, left, top, bottom, '|');
    draw_vertical(frame, right, top, bottom, '|');
    put_safe(frame, left, top, '+');
    put_safe(frame, right, top, '+');
    put_safe(frame, left, bottom, '+');
    put_safe(frame, right, bottom, '+');
}

fn draw_polyline(frame: &mut Frame, points: &[crate::layout::Point], glyph: char) {
    for pair in points.windows(2) {
        let start = pair[0];
        let end = pair[1];
        if start.x == end.x {
            draw_vertical(frame, start.x, start.y.min(end.y), start.y.max(end.y), '|');
        } else if start.y == end.y {
            draw_horizontal(
                frame,
                start.x.min(end.x),
                start.x.max(end.x),
                start.y,
                glyph,
            );
        } else {
            draw_horizontal(
                frame,
                start.x.min(end.x),
                start.x.max(end.x),
                start.y,
                glyph,
            );
            draw_vertical(frame, end.x, start.y.min(end.y), start.y.max(end.y), '|');
        }
    }
}

fn draw_horizontal(frame: &mut Frame, start_x: i32, end_x: i32, y: i32, glyph: char) {
    for x in start_x..=end_x {
        put_safe(frame, x, y, glyph);
    }
}

fn draw_vertical(frame: &mut Frame, x: i32, start_y: i32, end_y: i32, glyph: char) {
    for y in start_y..=end_y {
        put_safe(frame, x, y, glyph);
    }
}

fn write_centered(frame: &mut Frame, rect: Rect, text: &str) {
    let width = text.chars().count() as i32;
    let x = rect.origin.x + (rect.size.width - width).max(0) / 2;
    let y = rect.origin.y + rect.size.height / 2;
    write_text_safe(frame, x, y, text);
}

fn write_text_safe(frame: &mut Frame, x: i32, y: i32, text: &str) {
    if let (Ok(x), Ok(y)) = (usize::try_from(x), usize::try_from(y)) {
        let _ = frame.write_text(x, y, text, CellStyle::default());
    }
}

fn put_safe(frame: &mut Frame, x: i32, y: i32, glyph: char) {
    if let (Ok(x), Ok(y)) = (usize::try_from(x), usize::try_from(y)) {
        let _ = frame.put_glyph(x, y, glyph);
    }
}

#[cfg(test)]
mod tests {
    use super::{
        CellStyle, Color, Frame, FrameError, FrameRegion, GlyphCell, KeyFrameMarker,
        KeyFrameMarkerKind, StaticFrameRenderer,
    };
    use crate::ast::{
        ArrowHead, Diagram, DiagramKind, DiagramMetadata, Direction, FlowEdge, FlowEdgeLink,
        FlowEdgeStroke, FlowNode, FlowShape, FlowStatement, FlowchartAst, FlowchartDirective,
        FlowchartHeader, Label, LabelKind, SequenceArrow, SequenceAst, SequenceHeader,
        SequenceMessage, SequenceStatement, Span, Spanned, StateAst, StateDirective, StateHeader,
        StateStatement, StateTransition,
    };

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
