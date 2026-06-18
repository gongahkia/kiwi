#[cfg(not(target_arch = "wasm32"))]
use font_kit::{
    canvas::{Canvas, Format, RasterizationOptions},
    family_name::FamilyName,
    font::Font,
    hinting::HintingOptions,
    properties::Properties,
    source::SystemSource,
};
use font8x8::{BASIC_FONTS, BLOCK_FONTS, BOX_FONTS, MISC_FONTS, UnicodeFonts};
use gif::{Encoder as GifEncoder, Frame as GifFrame, Repeat};
use kumeyuri_core::{animator::Timeline, frame::Frame};
#[cfg(not(target_arch = "wasm32"))]
use pathfinder_geometry::{
    transform2d::Transform2F,
    vector::{Vector2F, Vector2I},
};
use png::{BitDepth, ColorType, Encoder as PngEncoder};
use tiny_skia::{Color, Paint, Pixmap, Rect, Transform};
#[cfg(not(target_arch = "wasm32"))]
use webp_animation::{Encoder as WebPEncoder, EncoderOptions as WebPEncoderOptions};

const GLYPH_SIZE: u32 = 8;
pub const FONT_FALLBACK_FAMILIES: &[&str] = &[
    "Noto Sans",
    "Noto Sans CJK",
    "Noto Sans Arabic",
    "Noto Color Emoji",
];

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

    pub fn render_apng(&self, timeline: &Timeline) -> Result<Vec<u8>, RasterRenderError> {
        let (width, height) = timeline_canvas_size(timeline, self.config)?;
        let frame_count =
            u32::try_from(timeline.len()).map_err(|_| RasterRenderError::ImageTooLarge)?;
        let mut output = Vec::new();
        {
            let mut encoder = PngEncoder::new(&mut output, width, height);
            encoder.set_color(ColorType::Rgba);
            encoder.set_depth(BitDepth::Eight);
            encoder
                .set_animated(frame_count, if timeline.repeat() { 0 } else { 1 })
                .map_err(|error| RasterRenderError::PngEncode(error.to_string()))?;
            let mut writer = encoder
                .write_header()
                .map_err(|error| RasterRenderError::PngEncode(error.to_string()))?;
            for keyframe in timeline.keyframes() {
                let (delay, denominator) = apng_delay(keyframe.duration());
                writer
                    .set_frame_delay(delay, denominator)
                    .map_err(|error| RasterRenderError::PngEncode(error.to_string()))?;
                let pixmap = self.frame_pixmap_with_canvas(keyframe.frame(), width, height)?;
                writer
                    .write_image_data(&rgba_pixels(&pixmap))
                    .map_err(|error| RasterRenderError::PngEncode(error.to_string()))?;
            }
            writer
                .finish()
                .map_err(|error| RasterRenderError::PngEncode(error.to_string()))?;
        }
        Ok(output)
    }

    #[cfg(not(target_arch = "wasm32"))]
    pub fn render_webp(&self, timeline: &Timeline) -> Result<Vec<u8>, RasterRenderError> {
        let (width, height) = timeline_canvas_size(timeline, self.config)?;
        let mut options = WebPEncoderOptions::default();
        if !timeline.repeat() {
            options.anim_params.loop_count = 1;
        }
        let mut encoder = WebPEncoder::new_with_options((width, height), options)
            .map_err(|error| RasterRenderError::WebPEncode(error.to_string()))?;
        let mut timestamp_ms = 0;
        for keyframe in timeline.keyframes() {
            let pixmap = self.frame_pixmap_with_canvas(keyframe.frame(), width, height)?;
            let pixels = rgba_pixels(&pixmap);
            encoder
                .add_frame(&pixels, timestamp_ms)
                .map_err(|error| RasterRenderError::WebPEncode(error.to_string()))?;
            timestamp_ms = add_webp_duration(timestamp_ms, keyframe.duration())?;
        }
        let data = encoder
            .finalize(timestamp_ms)
            .map_err(|error| RasterRenderError::WebPEncode(error.to_string()))?;
        Ok(data.as_ref().to_vec())
    }

    #[cfg(target_arch = "wasm32")]
    pub fn render_webp(&self, timeline: &Timeline) -> Result<Vec<u8>, RasterRenderError> {
        let _ = timeline_canvas_size(timeline, self.config)?;
        Err(RasterRenderError::UnsupportedTarget("webp"))
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
        let font_fallbacks = FontFallbackChain::new();
        for (row, line) in frame.to_lines().iter().enumerate() {
            for (column, glyph) in line.chars().enumerate() {
                let mut glyph_context = GlyphDrawContext {
                    pixmap: &mut pixmap,
                    paint: &paint,
                    font_fallbacks: &font_fallbacks,
                };
                self.draw_glyph(&mut glyph_context, column, row, glyph)?;
            }
        }
        Ok(pixmap)
    }

    fn draw_glyph(
        &self,
        context: &mut GlyphDrawContext<'_, '_>,
        column: usize,
        row: usize,
        glyph: char,
    ) -> Result<(), RasterRenderError> {
        if glyph == ' ' {
            return Ok(());
        }
        if self.draw_bitmap_glyph(context.pixmap, context.paint, column, row, glyph)? {
            return Ok(());
        }
        if self.draw_font_glyph(context.pixmap, column, row, glyph, context.font_fallbacks)? {
            return Ok(());
        }
        let _ = self.draw_bitmap_glyph(context.pixmap, context.paint, column, row, '?')?;
        Ok(())
    }

    fn draw_bitmap_glyph(
        &self,
        pixmap: &mut Pixmap,
        paint: &Paint,
        column: usize,
        row: usize,
        glyph: char,
    ) -> Result<bool, RasterRenderError> {
        let Some(bitmap) = glyph_bitmap(glyph) else {
            return Ok(false);
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
        Ok(true)
    }

    fn draw_font_glyph(
        &self,
        pixmap: &mut Pixmap,
        column: usize,
        row: usize,
        glyph: char,
        font_fallbacks: &FontFallbackChain,
    ) -> Result<bool, RasterRenderError> {
        draw_font_glyph(self.config, pixmap, column, row, glyph, font_fallbacks)
    }
}

struct GlyphDrawContext<'a, 'paint> {
    pixmap: &'a mut Pixmap,
    paint: &'a Paint<'paint>,
    font_fallbacks: &'a FontFallbackChain,
}

#[derive(Debug)]
struct FontFallbackChain {
    #[cfg(not(target_arch = "wasm32"))]
    fonts: Vec<Font>,
}

impl FontFallbackChain {
    fn new() -> Self {
        Self::from_families(FONT_FALLBACK_FAMILIES)
    }

    fn from_families(families: &[&str]) -> Self {
        #[cfg(not(target_arch = "wasm32"))]
        {
            let source = SystemSource::new();
            let fonts = families
                .iter()
                .filter_map(|family| {
                    source
                        .select_best_match(
                            &[FamilyName::Title((*family).to_owned())],
                            &Properties::new(),
                        )
                        .ok()
                        .and_then(|handle| handle.load().ok())
                })
                .collect();
            Self { fonts }
        }
        #[cfg(target_arch = "wasm32")]
        {
            let _ = families;
            Self {}
        }
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn font_for_char(&self, glyph: char) -> Option<(&Font, u32)> {
        self.fonts
            .iter()
            .find_map(|font| font.glyph_for_char(glyph).map(|glyph_id| (font, glyph_id)))
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn draw_font_glyph(
    config: RasterRenderConfig,
    pixmap: &mut Pixmap,
    column: usize,
    row: usize,
    glyph: char,
    font_fallbacks: &FontFallbackChain,
) -> Result<bool, RasterRenderError> {
    let Some((font, glyph_id)) = font_fallbacks.font_for_char(glyph) else {
        return Ok(false);
    };
    let cell_size = GLYPH_SIZE
        .checked_mul(config.scale)
        .ok_or(RasterRenderError::ImageTooLarge)?;
    let mut canvas = Canvas::new(
        Vector2I::new(u32_to_i32(cell_size)?, u32_to_i32(cell_size)?),
        Format::A8,
    );
    if font
        .rasterize_glyph(
            &mut canvas,
            glyph_id,
            cell_size as f32,
            Transform2F::from_translation(Vector2F::new(0.0, cell_size as f32)),
            HintingOptions::None,
            RasterizationOptions::GrayscaleAa,
        )
        .is_err()
    {
        return Ok(false);
    }
    let origin_x = config.padding + usize_to_u32(column)? * GLYPH_SIZE * config.scale;
    let origin_y = config.padding + usize_to_u32(row)? * GLYPH_SIZE * config.scale;
    let mut paint = Paint::default();
    for y in 0..cell_size {
        for x in 0..cell_size {
            let coverage = canvas.pixels[(y as usize * canvas.stride) + x as usize];
            if coverage == 0 {
                continue;
            }
            paint.set_color(color_with_coverage(config.foreground, coverage));
            let rect = Rect::from_xywh((origin_x + x) as f32, (origin_y + y) as f32, 1.0, 1.0)
                .ok_or(RasterRenderError::InvalidRect)?;
            pixmap.fill_rect(rect, &paint, Transform::identity(), None);
        }
    }
    Ok(true)
}

#[cfg(target_arch = "wasm32")]
fn draw_font_glyph(
    _config: RasterRenderConfig,
    _pixmap: &mut Pixmap,
    _column: usize,
    _row: usize,
    _glyph: char,
    _font_fallbacks: &FontFallbackChain,
) -> Result<bool, RasterRenderError> {
    Ok(false)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RasterRenderError {
    InvalidScale,
    EmptyTimeline,
    ImageTooLarge,
    InvalidRect,
    GifEncode(String),
    PngEncode(String),
    WebPEncode(String),
    UnsupportedTarget(&'static str),
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

fn apng_delay(duration: std::time::Duration) -> (u16, u16) {
    let millis = duration.as_millis().clamp(1, u128::from(u16::MAX));
    (millis as u16, 1000)
}

#[cfg(not(target_arch = "wasm32"))]
fn add_webp_duration(
    timestamp_ms: i32,
    duration: std::time::Duration,
) -> Result<i32, RasterRenderError> {
    timestamp_ms
        .checked_add(webp_duration_ms(duration))
        .ok_or(RasterRenderError::ImageTooLarge)
}

#[cfg(not(target_arch = "wasm32"))]
fn webp_duration_ms(duration: std::time::Duration) -> i32 {
    duration.as_millis().clamp(1, i32::MAX as u128) as i32
}

fn rgba_pixels(pixmap: &Pixmap) -> Vec<u8> {
    pixmap.data().to_vec()
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

fn u32_to_i32(value: u32) -> Result<i32, RasterRenderError> {
    i32::try_from(value).map_err(|_| RasterRenderError::ImageTooLarge)
}

fn color_with_coverage(color: RgbaColor, coverage: u8) -> Color {
    let alpha = (u16::from(color.alpha) * u16::from(coverage) / u16::from(u8::MAX)) as u8;
    Color::from_rgba8(color.red, color.green, color.blue, alpha)
}

fn glyph_bitmap(glyph: char) -> Option<[u8; 8]> {
    BASIC_FONTS
        .get(glyph)
        .or_else(|| BOX_FONTS.get(glyph))
        .or_else(|| BLOCK_FONTS.get(glyph))
        .or_else(|| MISC_FONTS.get(glyph))
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

    use super::{
        FONT_FALLBACK_FAMILIES, FontFallbackChain, RasterRenderConfig, RasterRenderError,
        RasterRenderer,
    };

    #[test]
    fn default_font_fallback_chain_names_are_ordered() {
        assert_eq!(
            FONT_FALLBACK_FAMILIES,
            &[
                "Noto Sans",
                "Noto Sans CJK",
                "Noto Sans Arabic",
                "Noto Color Emoji"
            ]
        );
    }

    #[test]
    fn empty_font_fallback_chain_has_no_fonts() {
        let chain = FontFallbackChain::from_families(&[]);

        #[cfg(not(target_arch = "wasm32"))]
        assert!(chain.font_for_char('漢').is_none());
        #[cfg(target_arch = "wasm32")]
        let _ = chain;
    }

    #[test]
    fn missing_bitmap_glyphs_are_not_replaced_before_font_fallback() {
        assert!(super::glyph_bitmap('漢').is_none());
        assert!(super::glyph_bitmap('?').is_some());
    }

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
    fn renders_timeline_to_apng() {
        let mut first = Frame::new(1, 1);
        first.write_text(0, 0, "A", Default::default()).unwrap();
        let mut second = Frame::new(1, 1);
        second.write_text(0, 0, "B", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![
            KeyFrame::new(first, Duration::from_millis(20)),
            KeyFrame::new(second, Duration::from_millis(30)),
        ])
        .with_repeat(true);

        let apng = RasterRenderer::default().render_apng(&timeline).unwrap();

        assert!(apng.starts_with(b"\x89PNG\r\n\x1a\n"));
        assert!(apng.windows(4).any(|chunk| chunk == b"acTL"));
        assert_eq!(apng.windows(4).filter(|chunk| *chunk == b"fcTL").count(), 2);
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn renders_timeline_to_animated_webp() {
        let mut first = Frame::new(1, 1);
        first.write_text(0, 0, "A", Default::default()).unwrap();
        let mut second = Frame::new(1, 1);
        second.write_text(0, 0, "B", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![
            KeyFrame::new(first, Duration::from_millis(20)),
            KeyFrame::new(second, Duration::from_millis(30)),
        ])
        .with_repeat(true);

        let webp = RasterRenderer::default().render_webp(&timeline).unwrap();
        let decoder = webp_animation::Decoder::new(&webp).unwrap();
        let dimensions = decoder.dimensions();
        let frames: Vec<_> = decoder.into_iter().collect();

        assert_eq!(&webp[..4], b"RIFF");
        assert_eq!(&webp[8..12], b"WEBP");
        assert!(webp.windows(4).any(|chunk| chunk == b"ANIM"));
        assert_eq!(dimensions, (32, 32));
        assert_eq!(frames.len(), 2);
    }

    #[test]
    fn apng_render_rejects_empty_timeline() {
        assert_eq!(
            RasterRenderer::default()
                .render_apng(&Timeline::new())
                .unwrap_err(),
            RasterRenderError::EmptyTimeline,
        );
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn webp_render_rejects_empty_timeline() {
        assert_eq!(
            RasterRenderer::default()
                .render_webp(&Timeline::new())
                .unwrap_err(),
            RasterRenderError::EmptyTimeline,
        );
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
