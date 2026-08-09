//! A minimal Bevy integration for CPU-readable color frames.
//!
//! [`StrokRenderer`] is a Bevy non-send resource because the safe `strok`
//! wrapper deliberately confines each renderer to one thread. Insert one per
//! independent frame stream, then add [`StrokRendererPlugin`] to copy the
//! current [`CpuColorFrame`] into [`CellGrid`] every update.

use bevy_app::{App, Plugin, Update};
use bevy_ecs::prelude::{NonSendMut, Res, ResMut, Resource};

pub use strok::{Cell, ColorFormat, Error, Grid, RendererConfig};

/// Persistent, main-thread renderer state for one Bevy frame stream.
pub struct StrokRenderer {
    renderer: strok::Renderer,
}

impl StrokRenderer {
    /// Creates a persistent renderer for a fixed cell grid.
    pub fn new(config: RendererConfig, grid: Grid) -> Result<Self, Error> {
        Ok(Self {
            renderer: strok::Renderer::new(config, grid)?,
        })
    }

    /// Clears the renderer's temporal history after a source discontinuity.
    pub fn reset(&mut self) -> Result<(), Error> {
        self.renderer.reset()
    }
}

/// A CPU-readable Bevy resource containing one packed color frame.
///
/// The plugin borrows `pixels` synchronously for a single render. It does not
/// copy, retain, or perform GPU texture readback; applications must supply any
/// required readback and pixel conversion before inserting this resource.
#[derive(Clone, Debug, Resource)]
pub struct CpuColorFrame {
    /// Packed RGB, RGBA, or BGRA pixel bytes.
    pub pixels: Vec<u8>,
    /// Frame width in pixels.
    pub width: usize,
    /// Frame height in pixels.
    pub height: usize,
    /// Row spacing in bytes, including any padding.
    pub row_stride_bytes: usize,
    /// Packed pixel format.
    pub format: ColorFormat,
}

impl CpuColorFrame {
    /// Creates a packed RGB24 frame with tightly packed rows.
    pub fn rgb24(pixels: Vec<u8>, width: usize, height: usize) -> Self {
        Self {
            pixels,
            width,
            height,
            row_stride_bytes: width.saturating_mul(3),
            format: ColorFormat::Rgb24,
        }
    }

    fn color_image(&self) -> Result<strok::ColorImage<'_>, Error> {
        strok::ColorImage::new(
            &self.pixels,
            self.width,
            self.height,
            self.row_stride_bytes,
            self.format,
        )
    }
}

/// A copied CellBuffer presentation owned by Bevy.
#[derive(Clone, Debug, Default, Resource)]
pub struct CellGrid {
    /// Cell columns in the copied result.
    pub columns: usize,
    /// Cell rows in the copied result.
    pub rows: usize,
    /// Row-major glyph and foreground/background cells.
    pub cells: Vec<Cell>,
}

/// Per-stream rendering status exposed without terminal logging.
#[derive(Clone, Debug, Default, Resource)]
pub struct StrokRenderMetrics {
    /// Number of successfully copied CellBuffer results.
    pub rendered_frames: u64,
    /// The latest layout, renderer, or CellBuffer error.
    pub last_error: Option<String>,
}

/// Installs the CPU color-frame renderer system and result resources.
#[derive(Default)]
pub struct StrokRendererPlugin;

impl Plugin for StrokRendererPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CellGrid>()
            .init_resource::<StrokRenderMetrics>()
            .add_systems(Update, render_cpu_color_frame);
    }
}

fn render_cpu_color_frame(
    renderer: Option<NonSendMut<StrokRenderer>>,
    frame: Option<Res<CpuColorFrame>>,
    mut cell_grid: ResMut<CellGrid>,
    mut metrics: ResMut<StrokRenderMetrics>,
) {
    let (Some(mut renderer), Some(frame)) = (renderer, frame) else {
        return;
    };
    let image = match frame.color_image() {
        Ok(image) => image,
        Err(error) => {
            metrics.last_error = Some(error.to_string());
            return;
        }
    };
    if let Err(error) = renderer.renderer.render_color(image) {
        metrics.last_error = Some(error.to_string());
        return;
    }
    let cells = match renderer.renderer.cells() {
        Ok(cells) => cells,
        Err(error) => {
            metrics.last_error = Some(error.to_string());
            return;
        }
    };
    let copied_cells = match cells.iter().collect::<Result<Vec<_>, _>>() {
        Ok(cells) => cells,
        Err(error) => {
            metrics.last_error = Some(error.to_string());
            return;
        }
    };
    let (columns, rows) = cells.dimensions();
    *cell_grid = CellGrid {
        columns,
        rows,
        cells: copied_cells,
    };
    metrics.rendered_frames = metrics.rendered_frames.saturating_add(1);
    metrics.last_error = None;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_renders_cpu_color_through_persistent_renderer() {
        let mut app = App::new();
        app.add_plugins(StrokRendererPlugin)
            .insert_non_send(
                StrokRenderer::new(
                    RendererConfig::default().cell_aspect(1.0),
                    Grid::new(2, 2).unwrap(),
                )
                .unwrap(),
            )
            .insert_resource(CpuColorFrame::rgb24(
                vec![0, 0, 0, 255, 255, 255, 128, 128, 128, 64, 64, 64],
                2,
                2,
            ));

        app.update();
        app.update();

        let cells = app.world().resource::<CellGrid>();
        assert_eq!((cells.columns, cells.rows), (2, 2));
        assert_eq!(cells.cells.len(), 4);
        let metrics = app.world().resource::<StrokRenderMetrics>();
        assert_eq!(metrics.rendered_frames, 2);
        assert!(metrics.last_error.is_none());
    }

    #[test]
    fn invalid_cpu_frame_reports_error_without_rendering() {
        let mut app = App::new();
        app.add_plugins(StrokRendererPlugin)
            .insert_non_send(
                StrokRenderer::new(
                    RendererConfig::default().cell_aspect(1.0),
                    Grid::new(1, 1).unwrap(),
                )
                .unwrap(),
            )
            .insert_resource(CpuColorFrame::rgb24(vec![0, 0], 1, 1));

        app.update();

        let metrics = app.world().resource::<StrokRenderMetrics>();
        assert_eq!(metrics.rendered_frames, 0);
        assert!(metrics.last_error.is_some());
    }
}
