//! A minimal Bevy integration for CPU-readable rich frames.
//!
//! [`StrokRenderer`] is a Bevy non-send resource because the safe `strok`
//! wrapper deliberately confines each renderer to one thread. Insert one per
//! independent frame stream, then add [`StrokRendererPlugin`] to synchronously
//! borrow the current [`CpuColorFrame`] and copy its output into [`CellGrid`].

use bevy_app::{App, Plugin, Update};
use bevy_ecs::prelude::{NonSendMut, Res, ResMut, Resource};

pub use strok::{Cell, ColorFormat, Error, Grid, RendererConfig};

/// Persistent, main-thread renderer state for one Bevy frame stream.
pub struct StrokRenderer {
    renderer: strok::Renderer,
    previous_dimensions: Option<(usize, usize)>,
    previous_stream_epoch: Option<u64>,
}

impl StrokRenderer {
    /// Creates a persistent renderer for a fixed cell grid.
    pub fn new(config: RendererConfig, grid: Grid) -> Result<Self, Error> {
        Ok(Self {
            renderer: strok::Renderer::new(config, grid)?,
            previous_dimensions: None,
            previous_stream_epoch: None,
        })
    }

    /// Clears the renderer's temporal history after a source discontinuity.
    pub fn reset(&mut self) -> Result<(), Error> {
        self.renderer.reset()?;
        self.previous_dimensions = None;
        self.previous_stream_epoch = None;
        Ok(())
    }

    fn reset_for_source(
        &mut self,
        dimensions: (usize, usize),
        stream_epoch: u64,
    ) -> Result<bool, Error> {
        let source_changed = self
            .previous_dimensions
            .is_some_and(|previous| previous != dimensions)
            || self
                .previous_stream_epoch
                .is_some_and(|previous| previous != stream_epoch);
        if source_changed {
            self.renderer.reset()?;
        }
        self.previous_dimensions = Some(dimensions);
        self.previous_stream_epoch = Some(stream_epoch);
        Ok(source_changed)
    }
}

/// A CPU-readable Float64 depth attachment.
#[derive(Clone, Debug, PartialEq)]
pub struct CpuDepthFrame {
    /// Camera-linear depth samples in row-major order.
    pub samples: Vec<f64>,
    /// Frame width in pixels.
    pub width: usize,
    /// Frame height in pixels.
    pub height: usize,
    /// Row spacing in Float64 elements, including any padding.
    pub row_stride_elements: usize,
}

impl CpuDepthFrame {
    /// Creates a tightly packed Float64 depth frame.
    #[must_use]
    pub fn tightly_packed(samples: Vec<f64>, width: usize, height: usize) -> Self {
        Self {
            samples,
            width,
            height,
            row_stride_elements: width,
        }
    }

    fn depth_image(&self) -> Result<strok::DepthImage<'_>, Error> {
        strok::DepthImage::new(
            &self.samples,
            self.width,
            self.height,
            self.row_stride_elements,
        )
    }
}

/// A CPU-readable Float64x3 view-space normal attachment.
#[derive(Clone, Debug, PartialEq)]
pub struct CpuNormalFrame {
    /// View-space normal samples in row-major order.
    pub samples: Vec<[f64; 3]>,
    /// Frame width in pixels.
    pub width: usize,
    /// Frame height in pixels.
    pub height: usize,
    /// Row spacing in three-component normal pixels, including any padding.
    pub row_stride_pixels: usize,
}

impl CpuNormalFrame {
    /// Creates a tightly packed Float64x3 normal frame.
    #[must_use]
    pub fn tightly_packed(samples: Vec<[f64; 3]>, width: usize, height: usize) -> Self {
        Self {
            samples,
            width,
            height,
            row_stride_pixels: width,
        }
    }

    fn normal_image(&self) -> Result<strok::NormalImage<'_>, Error> {
        strok::NormalImage::new(
            &self.samples,
            self.width,
            self.height,
            self.row_stride_pixels,
        )
    }
}

/// A CPU-readable Bevy resource containing a color frame and optional attachments.
///
/// The plugin borrows the contained data synchronously for a single render. It
/// does not copy, retain, or perform GPU texture readback; applications must
/// supply any required readback and pixel conversion before inserting it.
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
    /// Optional camera-linear depth attachment with matching dimensions.
    pub depth: Option<CpuDepthFrame>,
    /// Optional view-space normal attachment with matching dimensions.
    pub normals: Option<CpuNormalFrame>,
    /// Increment after a same-size source discontinuity to reset temporal state.
    pub stream_epoch: u64,
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
            depth: None,
            normals: None,
            stream_epoch: 0,
        }
    }

    /// Adds a CPU-readable camera-linear depth attachment.
    #[must_use]
    pub fn with_depth(mut self, depth: CpuDepthFrame) -> Self {
        self.depth = Some(depth);
        self
    }

    /// Adds a CPU-readable view-space normal attachment.
    #[must_use]
    pub fn with_normals(mut self, normals: CpuNormalFrame) -> Self {
        self.normals = Some(normals);
        self
    }

    /// Sets the source epoch used to reset temporal state after discontinuities.
    #[must_use]
    pub fn with_stream_epoch(mut self, stream_epoch: u64) -> Self {
        self.stream_epoch = stream_epoch;
        self
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

impl CellGrid {
    /// Returns the copied cell at zero-based `(column, row)`.
    #[must_use]
    pub fn get(&self, column: usize, row: usize) -> Option<&Cell> {
        if column >= self.columns || row >= self.rows {
            return None;
        }
        self.cells
            .get(row.checked_mul(self.columns)?.checked_add(column)?)
    }
}

/// Per-stream rendering status exposed without terminal logging.
#[derive(Clone, Debug, Default, Resource)]
pub struct StrokRenderMetrics {
    /// Number of successfully copied CellBuffer results.
    pub rendered_frames: u64,
    /// Number of temporal resets triggered by source changes.
    pub temporal_resets: u64,
    /// The latest layout, renderer, or CellBuffer error.
    pub last_error: Option<String>,
}

/// Installs the CPU rich-frame renderer system and result resources.
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
    let color = match frame.color_image() {
        Ok(image) => image,
        Err(error) => {
            metrics.last_error = Some(error.to_string());
            return;
        }
    };
    let mut input = strok::RenderInput::new(color);
    if let Some(depth) = &frame.depth {
        let depth = match depth.depth_image() {
            Ok(depth) => depth,
            Err(error) => {
                metrics.last_error = Some(error.to_string());
                return;
            }
        };
        input = match input.with_depth(depth) {
            Ok(input) => input,
            Err(error) => {
                metrics.last_error = Some(error.to_string());
                return;
            }
        };
    }
    if let Some(normals) = &frame.normals {
        let normals = match normals.normal_image() {
            Ok(normals) => normals,
            Err(error) => {
                metrics.last_error = Some(error.to_string());
                return;
            }
        };
        input = match input.with_normals(normals) {
            Ok(input) => input,
            Err(error) => {
                metrics.last_error = Some(error.to_string());
                return;
            }
        };
    }
    let reset = match renderer.reset_for_source(color.dimensions(), frame.stream_epoch) {
        Ok(reset) => reset,
        Err(error) => {
            metrics.last_error = Some(error.to_string());
            return;
        }
    };
    if let Err(error) = renderer.renderer.render(input) {
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
    if reset {
        metrics.temporal_resets = metrics.temporal_resets.saturating_add(1);
    }
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

    #[test]
    fn headless_rich_input_smoke_copies_a_native_cell_grid() {
        let mut app = App::new();
        app.add_plugins(StrokRendererPlugin)
            .insert_non_send(
                StrokRenderer::new(
                    RendererConfig::default().cell_aspect(1.0),
                    Grid::new(2, 1).unwrap(),
                )
                .unwrap(),
            )
            .insert_resource(
                CpuColorFrame::rgb24(vec![0, 0, 0, 255, 255, 255], 2, 1)
                    .with_depth(CpuDepthFrame::tightly_packed(vec![1.0, 2.0], 2, 1))
                    .with_normals(CpuNormalFrame::tightly_packed(
                        vec![[0.0, 0.0, 1.0], [0.0, 0.0, 1.0]],
                        2,
                        1,
                    )),
            );

        app.update();

        let cells = app.world().resource::<CellGrid>();
        assert_eq!((cells.columns, cells.rows), (2, 1));
        assert_eq!(cells.cells.len(), 2);
        assert_eq!(cells.get(2, 0), None);
        assert!(cells.get(1, 0).is_some());
        let metrics = app.world().resource::<StrokRenderMetrics>();
        assert_eq!(metrics.rendered_frames, 1);
        assert_eq!(metrics.temporal_resets, 0);
        assert!(metrics.last_error.is_none());
    }

    #[test]
    fn source_resize_and_epoch_change_reset_temporal_state() {
        let mut app = App::new();
        app.add_plugins(StrokRendererPlugin)
            .insert_non_send(
                StrokRenderer::new(
                    RendererConfig::default().cell_aspect(1.0),
                    Grid::new(1, 1).unwrap(),
                )
                .unwrap(),
            )
            .insert_resource(CpuColorFrame::rgb24(vec![0, 0, 0], 1, 1));

        app.update();
        app.world_mut()
            .insert_resource(CpuColorFrame::rgb24(vec![0, 0, 0, 255, 255, 255], 2, 1));
        app.update();
        app.world_mut().insert_resource(
            CpuColorFrame::rgb24(vec![0, 0, 0, 255, 255, 255], 2, 1).with_stream_epoch(1),
        );
        app.update();

        let metrics = app.world().resource::<StrokRenderMetrics>();
        assert_eq!(metrics.rendered_frames, 3);
        assert_eq!(metrics.temporal_resets, 2);
        assert!(metrics.last_error.is_none());
    }
}
