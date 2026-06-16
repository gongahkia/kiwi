use font8x8::{BASIC_FONTS, BLOCK_FONTS, BOX_FONTS, MISC_FONTS, UnicodeFonts};
use gif::{Encoder as GifEncoder, Frame as GifFrame, Repeat};
use kumeyuri_core::{animator::Timeline, frame::Frame};
use tiny_skia::{Color, Paint, Pixmap, Rect, Transform};

const GLYPH_SIZE: u32 = 8;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RasterRenderConfig {
    pub scale: u32,
    pub padding: u32,
    pub foreground: RgbaColor,
    pub background: RgbaColor,
}

impl Default for RasterRenderConfig {
    fn default() -> Self {
        Self {
            scale: 2,
            padding: 8,
            foreground: RgbaColor::rgb(17, 24, 39),
            background: RgbaColor::rgb(255, 255, 255),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RgbaColor {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
    pub alpha: u8,
}

impl RgbaColor {
    #[must_use]
    pub const fn rgb(red: u8, green: u8, blue: u8) -> Self {
        Self {
            red,
            green,
            blue,
            alpha: u8::MAX,
        }
    }

    #[must_use]
    pub const fn rgba(red: u8, green: u8, blue: u8, alpha: u8) -> Self {
        Self {
            red,
            green,
            blue,
            alpha,
        }
    }

    fn to_skia(self) -> Color {
        Color::from_rgba8(self.red, self.green, self.blue, self.alpha)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RasterRenderer {
    config: RasterRenderConfig,
}

impl Default for RasterRenderer {
    fn default() -> Self {
        Self::new(RasterRenderConfig::default()).expect("default raster config is valid")
    }
}

impl RasterRenderer {
    pub fn new(config: RasterRenderConfig) -> Result<Self, RasterRenderError> {
        if config.scale == 0 {
            return Err(RasterRenderError::InvalidScale);
        }
        Ok(Self { config })
    }

    #[must_use]
    pub const fn config(&self) -> RasterRenderConfig {
        self.config
    }

    pub fn render_frame(&self, frame: &Frame) -> Result<Vec<u8>, RasterRenderError> {
        let pixmap = self.frame_pixmap(frame)?;
        pixmap
            .encode_png()
            .map_err(|error| RasterRenderError::PngEncode(error.to_string()))
    }

    pub fn render_timeline_frames(
        &self,
        timeline: &Timeline,
    ) -> Result<Vec<Vec<u8>>, RasterRenderError> {
        timeline
            .keyframes()
            .iter()
            .map(|keyframe| self.render_frame(keyframe.frame()))
            .collect()
    }

    pub fn render_gif(&self, timeline: &Timeline) -> Result<Vec<u8>, RasterRenderError> {
        let (width, height) = timeline_canvas_size(timeline, self.config)?;
        let width_u16 = u16::try_from(width).map_err(|_| RasterRenderError::ImageTooLarge)?;
        let height_u16 = u16::try_from(height).map_err(|_| RasterRenderError::ImageTooLarge)?;
        let mut output = Vec::new();
        {
            let mut encoder = GifEncoder::new(&mut output, width_u16, height_u16, &[])
                .map_err(|error| RasterRenderError::GifEncode(error.to_string()))?;
            if timeline.repeat() {
                encoder
                    .set_repeat(Repeat::Infinite)
                    .map_err(|error| RasterRenderError::GifEncode(error.to_string()))?;
            }
            for keyframe in timeline.keyframes() {
                let pixmap = self.frame_pixmap_with_canvas(keyframe.frame(), width, height)?;
                let mut pixels = pixmap.data().to_vec();
                let mut frame = GifFrame::from_rgba_speed(width_u16, height_u16, &mut pixels, 10);
                frame.delay = gif_delay(keyframe.duration());
                encoder
                    .write_frame(&frame)
                    .map_err(|error| RasterRenderError::GifEncode(error.to_string()))?;
            }
        }
        Ok(output)
    }

    fn frame_pixmap(&self, frame: &Frame) -> Result<Pixmap, RasterRenderError> {
        let width = raster_extent(frame.width(), self.config.scale, self.config.padding)?;
        let height = raster_extent(frame.height(), self.config.scale, self.config.padding)?;
        self.frame_pixmap_with_canvas(frame, width, height)
    }

    fn frame_pixmap_with_canvas(
        &self,
        frame: &Frame,
        width: u32,
        height: u32,
    ) -> Result<Pixmap, RasterRenderError> {
        let mut pixmap = Pixmap::new(width, height).ok_or(RasterRenderError::ImageTooLarge)?;
        pixmap.fill(self.config.background.to_skia());

        let mut paint = Paint::default();
        paint.set_color(self.config.foreground.to_skia());
        for (row, line) in frame.to_lines().iter().enumerate() {
            for (column, glyph) in line.chars().enumerate() {
                self.draw_glyph(&mut pixmap, &paint, column, row, glyph)?;
            }
        }
        Ok(pixmap)
    }

    fn draw_glyph(
        &self,
        pixmap: &mut Pixmap,
        paint: &Paint,
        column: usize,
        row: usize,
        glyph: char,
    ) -> Result<(), RasterRenderError> {
        if glyph == ' ' {
            return Ok(());
        }
        let Some(bitmap) = glyph_bitmap(glyph) else {
            return Ok(());
        };
        let origin_x = self.config.padding + usize_to_u32(column)? * GLYPH_SIZE * self.config.scale;
        let origin_y = self.config.padding + usize_to_u32(row)? * GLYPH_SIZE * self.config.scale;
        for (bitmap_y, bits) in bitmap.iter().enumerate() {
            for bitmap_x in 0..GLYPH_SIZE {
                if bits & (1 << bitmap_x) == 0 {
                    continue;
                }
                let x = origin_x + bitmap_x * self.config.scale;
                let y = origin_y + usize_to_u32(bitmap_y)? * self.config.scale;
                let rect = Rect::from_xywh(
                    x as f32,
                    y as f32,
                    self.config.scale as f32,
                    self.config.scale as f32,
                )
                .ok_or(RasterRenderError::InvalidRect)?;
                pixmap.fill_rect(rect, paint, Transform::identity(), None);
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RasterRenderError {
    InvalidScale,
    EmptyTimeline,
    ImageTooLarge,
    InvalidRect,
    GifEncode(String),
    PngEncode(String),
}

fn timeline_canvas_size(
    timeline: &Timeline,
    config: RasterRenderConfig,
) -> Result<(u32, u32), RasterRenderError> {
    let Some(first) = timeline.keyframes().first() else {
        return Err(RasterRenderError::EmptyTimeline);
    };
    let (mut max_width, mut max_height) = (first.frame().width(), first.frame().height());
    for keyframe in timeline.keyframes().iter().skip(1) {
        max_width = max_width.max(keyframe.frame().width());
        max_height = max_height.max(keyframe.frame().height());
    }
    Ok((
        raster_extent(max_width, config.scale, config.padding)?,
        raster_extent(max_height, config.scale, config.padding)?,
    ))
}

fn gif_delay(duration: std::time::Duration) -> u16 {
    let centiseconds = duration
        .as_millis()
        .div_ceil(10)
        .clamp(1, u128::from(u16::MAX));
    centiseconds as u16
}

fn raster_extent(cells: usize, scale: u32, padding: u32) -> Result<u32, RasterRenderError> {
    let cells = usize_to_u32(cells)?;
    cells
        .checked_mul(GLYPH_SIZE)
        .and_then(|value| value.checked_mul(scale))
        .and_then(|value| value.checked_add(padding.saturating_mul(2)))
        .filter(|value| *value > 0)
        .ok_or(RasterRenderError::ImageTooLarge)
}

fn usize_to_u32(value: usize) -> Result<u32, RasterRenderError> {
    u32::try_from(value).map_err(|_| RasterRenderError::ImageTooLarge)
}

fn glyph_bitmap(glyph: char) -> Option<[u8; 8]> {
    BASIC_FONTS
        .get(glyph)
        .or_else(|| BOX_FONTS.get(glyph))
        .or_else(|| BLOCK_FONTS.get(glyph))
        .or_else(|| MISC_FONTS.get(glyph))
        .or_else(|| BASIC_FONTS.get('?'))
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use gif::DecodeOptions;
    use kumeyuri_core::{
        animator::{KeyFrame, Timeline},
        frame::Frame,
    };
    use tiny_skia::Pixmap;

    use super::{RasterRenderConfig, RasterRenderError, RasterRenderer};

    #[test]
    fn renders_frame_to_png_bytes() {
        let mut frame = Frame::new(2, 1);
        frame.write_text(0, 0, "AB", Default::default()).unwrap();

        let png = RasterRenderer::default().render_frame(&frame).unwrap();
        let pixmap = Pixmap::decode_png(&png).unwrap();

        assert!(png.starts_with(b"\x89PNG\r\n\x1a\n"));
        assert_eq!(pixmap.width(), 48);
        assert_eq!(pixmap.height(), 32);
        assert!(pixmap.data().iter().any(|pixel| *pixel != u8::MAX));
    }

    #[test]
    fn renders_each_timeline_frame_to_png() {
        let mut first = Frame::new(1, 1);
        first.write_text(0, 0, "A", Default::default()).unwrap();
        let mut second = Frame::new(1, 1);
        second.write_text(0, 0, "B", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![
            KeyFrame::new(first, Duration::ZERO),
            KeyFrame::new(second, Duration::ZERO),
        ]);

        let pngs = RasterRenderer::default()
            .render_timeline_frames(&timeline)
            .unwrap();

        assert_eq!(pngs.len(), 2);
        assert!(pngs.iter().all(|png| png.starts_with(b"\x89PNG")));
    }

    #[test]
    fn renders_timeline_to_animated_gif() {
        let mut first = Frame::new(1, 1);
        first.write_text(0, 0, "A", Default::default()).unwrap();
        let mut second = Frame::new(1, 1);
        second.write_text(0, 0, "B", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![
            KeyFrame::new(first, Duration::from_millis(20)),
            KeyFrame::new(second, Duration::from_millis(30)),
        ])
        .with_repeat(true);

        let gif = RasterRenderer::default().render_gif(&timeline).unwrap();
        let mut options = DecodeOptions::new();
        options.set_color_output(gif::ColorOutput::RGBA);
        let mut decoder = options.read_info(gif.as_slice()).unwrap();

        assert!(gif.starts_with(b"GIF89a"));
        assert_eq!(decoder.width(), 32);
        assert_eq!(decoder.height(), 32);
        assert!(decoder.read_next_frame().unwrap().is_some());
        assert!(decoder.read_next_frame().unwrap().is_some());
        assert!(decoder.read_next_frame().unwrap().is_none());
    }

    #[test]
    fn gif_render_rejects_empty_timeline() {
        assert_eq!(
            RasterRenderer::default()
                .render_gif(&Timeline::new())
                .unwrap_err(),
            RasterRenderError::EmptyTimeline,
        );
    }

    #[test]
    fn rejects_zero_scale_config() {
        assert_eq!(
            RasterRenderer::new(RasterRenderConfig {
                scale: 0,
                ..RasterRenderConfig::default()
            })
            .unwrap_err(),
            RasterRenderError::InvalidScale,
        );
    }
}
