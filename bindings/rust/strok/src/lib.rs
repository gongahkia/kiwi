//! Safe ownership and read-only result access for the `strok` C ABI.
//!
//! This crate owns a renderer handle through [`Renderer`]. [`CellBuffer`] is a
//! read-only view tied to that renderer, so Rust prevents it from surviving a
//! later mutable renderer operation. Safe borrowed image inputs are intentionally
//! outside this crate's initial scope.

use std::ffi::CStr;
use std::fmt;
use std::marker::PhantomData;
use std::mem::MaybeUninit;
use std::ptr::{self, NonNull};
use std::rc::Rc;

/// Generated raw C ABI bindings for use with the explicitly unsafe render bridge.
pub use strok_sys as raw;

use raw as sys;

/// A C ABI status value returned with an [`Error::CApi`] failure.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Status(u32);

impl Status {
    /// The raw `StrokStatus` value from the C ABI.
    #[must_use]
    pub const fn raw(self) -> u32 {
        self.0
    }
}

/// An error returned by a safe `strok` operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Error {
    /// Renderer grid dimensions must both be positive.
    InvalidGrid { columns: i32, rows: i32 },
    /// The C ABI rejected an operation.
    CApi { status: Status, message: String },
    /// The C ABI returned a cell glyph that is not a Unicode scalar value.
    InvalidCellGlyph { glyph: u32 },
}

impl Error {
    /// Returns the C ABI status when this error came from the C library.
    #[must_use]
    pub const fn status(&self) -> Option<Status> {
        match self {
            Self::CApi { status, .. } => Some(*status),
            Self::InvalidGrid { .. } | Self::InvalidCellGlyph { .. } => None,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidGrid { columns, rows } => {
                write!(
                    formatter,
                    "renderer grid dimensions must be positive, got {columns}x{rows}"
                )
            }
            Self::CApi { status, message } => {
                write!(
                    formatter,
                    "strok C ABI failed with status {}: {message}",
                    status.raw()
                )
            }
            Self::InvalidCellGlyph { glyph } => {
                write!(
                    formatter,
                    "strok C ABI returned invalid Unicode scalar U+{glyph:04X}"
                )
            }
        }
    }
}

impl std::error::Error for Error {}

/// Dimensions for a renderer's fixed terminal-cell grid.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Grid {
    columns: i32,
    rows: i32,
}

impl Grid {
    /// Constructs a grid with positive column and row counts.
    pub fn new(columns: i32, rows: i32) -> Result<Self, Error> {
        if columns <= 0 || rows <= 0 {
            return Err(Error::InvalidGrid { columns, rows });
        }
        Ok(Self { columns, rows })
    }

    /// The number of columns in this grid.
    #[must_use]
    pub const fn columns(self) -> i32 {
        self.columns
    }

    /// The number of rows in this grid.
    #[must_use]
    pub const fn rows(self) -> i32 {
        self.rows
    }
}

/// Creation settings supported by the initial safe wrapper.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RendererConfig {
    cell_aspect: f64,
}

impl Default for RendererConfig {
    fn default() -> Self {
        Self { cell_aspect: 0.5 }
    }
}

impl RendererConfig {
    /// Sets the terminal cell width-to-height aspect ratio.
    #[must_use]
    pub const fn cell_aspect(mut self, cell_aspect: f64) -> Self {
        self.cell_aspect = cell_aspect;
        self
    }
}

/// An owned, thread-confined C ABI renderer.
///
/// `Renderer` deliberately implements neither `Send` nor `Sync`, matching the
/// C ABI's per-handle thread-safety contract.
pub struct Renderer {
    raw: NonNull<sys::StrokRenderer>,
    thread_confined: PhantomData<Rc<()>>,
}

impl Renderer {
    /// Creates a renderer which is destroyed automatically when dropped.
    pub fn new(config: RendererConfig, grid: Grid) -> Result<Self, Error> {
        let mut raw_config = MaybeUninit::<sys::StrokRendererConfig>::uninit();
        let mut raw_grid = MaybeUninit::<sys::StrokRenderGrid>::uninit();
        unsafe {
            sys::strok_renderer_config_init(raw_config.as_mut_ptr());
            sys::strok_render_grid_init(raw_grid.as_mut_ptr());
        }

        let mut raw_config = unsafe { raw_config.assume_init() };
        raw_config.cell_aspect = config.cell_aspect;
        let mut raw_grid = unsafe { raw_grid.assume_init() };
        raw_grid.cols = grid.columns;
        raw_grid.rows = grid.rows;

        let mut raw_renderer = ptr::null_mut();
        let status =
            unsafe { sys::strok_renderer_create(&raw_config, &raw_grid, &mut raw_renderer) };
        status_result(status)?;
        let raw = NonNull::new(raw_renderer).ok_or_else(|| Error::CApi {
            status: Status(status),
            message: "strok C ABI reported success without creating a renderer".into(),
        })?;

        Ok(Self {
            raw,
            thread_confined: PhantomData,
        })
    }

    /// Resets the renderer's temporal state.
    ///
    /// This requires exclusive access so an existing [`CellBuffer`] cannot span
    /// a state-changing renderer operation.
    pub fn reset(&mut self) -> Result<(), Error> {
        let status = unsafe { sys::strok_renderer_reset(self.raw.as_ptr()) };
        status_result(status)
    }

    /// Renders one raw C color image view.
    ///
    /// This is an escape hatch until safe borrowed image views are available.
    /// Prefer the safe input API once it is introduced.
    ///
    /// # Safety
    ///
    /// `image` and its data pointer must satisfy the C ABI contract for
    /// `strok_renderer_render_color`: the header must be initialized, and its
    /// data must remain valid and unchanged for the full call. The renderer does
    /// not retain the image after this function returns.
    pub unsafe fn render_color_raw(
        &mut self,
        image: &sys::StrokColorImageView,
    ) -> Result<(), Error> {
        let status = unsafe { sys::strok_renderer_render_color(self.raw.as_ptr(), image) };
        status_result(status)
    }

    /// Returns the result of the most recent successful render.
    ///
    /// The C ABI reports an error until a render has completed successfully.
    /// The returned view borrows this renderer, and a future render API will
    /// require `&mut self`, preventing stale result access in safe Rust.
    pub fn cells(&self) -> Result<CellBuffer<'_>, Error> {
        let mut columns = 0;
        let mut rows = 0;
        let status = unsafe {
            sys::strok_renderer_cell_buffer_dimensions(self.raw.as_ptr(), &mut columns, &mut rows)
        };
        status_result(status)?;

        let columns = usize::try_from(columns).map_err(|_| Error::CApi {
            status: Status(status),
            message: "strok C ABI returned a negative cell-buffer width".into(),
        })?;
        let rows = usize::try_from(rows).map_err(|_| Error::CApi {
            status: Status(status),
            message: "strok C ABI returned a negative cell-buffer height".into(),
        })?;
        Ok(CellBuffer {
            renderer: self,
            columns,
            rows,
        })
    }
}

impl Drop for Renderer {
    fn drop(&mut self) {
        unsafe {
            sys::strok_renderer_destroy(self.raw.as_ptr());
        }
    }
}

/// A copied terminal-cell result view borrowed from a [`Renderer`].
///
/// Each access copies a cell out of the C ABI. The borrow prevents this view
/// from outliving the renderer or a later mutable renderer operation.
///
/// ```compile_fail
/// use strok::{Grid, Renderer, RendererConfig};
///
/// let mut renderer = Renderer::new(RendererConfig::default(), Grid::new(2, 2).unwrap()).unwrap();
/// let cells = renderer.cells().unwrap();
/// let image: strok::raw::StrokColorImageView = unsafe { std::mem::zeroed() };
/// unsafe { renderer.render_color_raw(&image).unwrap() };
/// let _ = cells.dimensions();
/// ```
pub struct CellBuffer<'renderer> {
    renderer: &'renderer Renderer,
    columns: usize,
    rows: usize,
}

impl<'renderer> CellBuffer<'renderer> {
    /// Returns `(columns, rows)`.
    #[must_use]
    pub const fn dimensions(&self) -> (usize, usize) {
        (self.columns, self.rows)
    }

    /// Returns the number of cells in the result.
    #[must_use]
    pub const fn len(&self) -> usize {
        self.columns.saturating_mul(self.rows)
    }

    /// Returns whether this result contains no cells.
    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Copies the cell at zero-based `(column, row)`, or returns `None` when it
    /// lies outside this buffer.
    pub fn get(&self, column: usize, row: usize) -> Result<Option<Cell>, Error> {
        if column >= self.columns || row >= self.rows {
            return Ok(None);
        }

        let column = i32::try_from(column).map_err(|_| Error::CApi {
            status: Status(sys::STROK_STATUS_INTERNAL_ERROR),
            message: "strok cell-buffer column exceeds the C ABI range".into(),
        })?;
        let row = i32::try_from(row).map_err(|_| Error::CApi {
            status: Status(sys::STROK_STATUS_INTERNAL_ERROR),
            message: "strok cell-buffer row exceeds the C ABI range".into(),
        })?;
        let mut raw_cell = MaybeUninit::<sys::StrokCell>::uninit();
        let status = unsafe {
            sys::strok_renderer_cell_buffer_at(
                self.renderer.raw.as_ptr(),
                column,
                row,
                raw_cell.as_mut_ptr(),
            )
        };
        status_result(status)?;
        let raw_cell = unsafe { raw_cell.assume_init() };
        let glyph = char::from_u32(raw_cell.glyph).ok_or(Error::InvalidCellGlyph {
            glyph: raw_cell.glyph,
        })?;
        Ok(Some(Cell {
            glyph,
            foreground: Rgb {
                red: raw_cell.fg_r,
                green: raw_cell.fg_g,
                blue: raw_cell.fg_b,
            },
            background: Rgb {
                red: raw_cell.bg_r,
                green: raw_cell.bg_g,
                blue: raw_cell.bg_b,
            },
        }))
    }

    /// Iterates over copied cells in row-major order.
    #[must_use]
    pub fn iter(&self) -> CellIter<'_, 'renderer> {
        CellIter {
            cells: self,
            next: 0,
        }
    }
}

/// A row-major iterator over [`CellBuffer`] entries.
pub struct CellIter<'buffer, 'renderer> {
    cells: &'buffer CellBuffer<'renderer>,
    next: usize,
}

impl Iterator for CellIter<'_, '_> {
    type Item = Result<Cell, Error>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.next == self.cells.len() {
            return None;
        }
        let index = self.next;
        self.next = self.next.saturating_add(1);
        let column = index % self.cells.columns;
        let row = index / self.cells.columns;
        Some(match self.cells.get(column, row) {
            Ok(Some(cell)) => Ok(cell),
            Ok(None) => Err(Error::CApi {
                status: Status(sys::STROK_STATUS_INTERNAL_ERROR),
                message: "strok C ABI omitted an in-range cell".into(),
            }),
            Err(error) => Err(error),
        })
    }
}

/// An RGB color copied from a terminal cell.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Rgb {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
}

/// A terminal-independent output cell copied from the C ABI.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Cell {
    pub glyph: char,
    pub foreground: Rgb,
    pub background: Rgb,
}

fn status_result(status: sys::StrokStatus) -> Result<(), Error> {
    if status == sys::STROK_STATUS_SUCCESS || status == sys::STROK_STATUS_BACKEND_FALLBACK {
        return Ok(());
    }
    Err(Error::CApi {
        status: Status(status),
        message: last_error_message(),
    })
}

fn last_error_message() -> String {
    let message = unsafe { sys::strok_last_error_message() };
    if message.is_null() {
        return "strok C ABI reported an error without a message".into();
    }
    unsafe { CStr::from_ptr(message) }
        .to_string_lossy()
        .into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn renderer() -> Renderer {
        Renderer::new(RendererConfig::default(), Grid::new(2, 2).unwrap()).unwrap()
    }

    fn rgb24_image(pixels: &[u8; 12]) -> sys::StrokColorImageView {
        let mut image = MaybeUninit::<sys::StrokColorImageView>::uninit();
        unsafe {
            sys::strok_color_image_view_init(image.as_mut_ptr());
        }
        let mut image = unsafe { image.assume_init() };
        image.data = pixels.as_ptr();
        image.width = 2;
        image.height = 2;
        image.row_stride_bytes = 6;
        image.pixel_format = sys::STROK_COLOR_PIXEL_FORMAT_RGB24;
        image
    }

    #[test]
    fn lifecycle_and_result_access_are_safe() {
        let mut renderer = renderer();
        assert!(matches!(renderer.cells(), Err(Error::CApi { .. })));

        let pixels = [0_u8, 0, 0, 255, 0, 0, 0, 255, 0, 255, 255, 255];
        let image = rgb24_image(&pixels);
        unsafe { renderer.render_color_raw(&image) }.unwrap();
        {
            let cells = renderer.cells().unwrap();
            let (columns, rows) = cells.dimensions();
            assert!(columns > 0 && rows > 0);
            assert_eq!(cells.len(), columns * rows);
            assert!(!cells.is_empty());
            assert!(cells.get(0, 0).unwrap().is_some());
            assert_eq!(cells.get(columns, 0).unwrap(), None);
            assert_eq!(
                cells.iter().collect::<Result<Vec<_>, _>>().unwrap().len(),
                cells.len()
            );
        }

        renderer.reset().unwrap();
    }

    #[test]
    fn invalid_input_returns_errors_without_panicking() {
        assert_eq!(
            Grid::new(0, 1),
            Err(Error::InvalidGrid {
                columns: 0,
                rows: 1
            })
        );

        let error = Renderer::new(
            RendererConfig::default().cell_aspect(0.0),
            Grid::new(2, 2).unwrap(),
        )
        .err()
        .expect("invalid C configuration must return an error");
        assert_eq!(
            error.status(),
            Some(Status(sys::STROK_STATUS_INVALID_ARGUMENT))
        );
        assert!(matches!(error, Error::CApi { .. }));
    }
}
