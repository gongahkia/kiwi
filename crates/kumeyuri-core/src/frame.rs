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

#[cfg(test)]
mod tests {
    use super::{
        CellStyle, Color, Frame, FrameError, FrameRegion, GlyphCell, KeyFrameMarker,
        KeyFrameMarkerKind,
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
}
