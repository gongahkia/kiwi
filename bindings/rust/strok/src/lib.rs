//! Safe ownership, borrowed input, and read-only result access for the `strok`
//! C ABI.
//!
//! [`Renderer`] owns its C handle. [`ColorImage`], [`DepthImage`], and
//! [`NormalImage`] borrow their input slices only for a render call, while
//! [`CellBuffer`] borrows the renderer's current output.

use std::ffi::CStr;
use std::fmt;
use std::marker::PhantomData;
use std::mem::MaybeUninit;
use std::ptr::{self, NonNull};
use std::rc::Rc;

use strok_sys as sys;

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

/// The input buffer to which a validation error applies.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InputKind {
    Color,
    Depth,
    Normals,
}

impl InputKind {
    const fn name(self) -> &'static str {
        match self {
            Self::Color => "color",
            Self::Depth => "depth",
            Self::Normals => "normal",
        }
    }
}

/// A safe borrowed-image layout validation failure.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LayoutError {
    /// Width and height must both be positive.
    ZeroDimensions { width: usize, height: usize },
    /// A dimension cannot be represented by the C ABI's signed 32-bit fields.
    DimensionsOutOfRange { width: usize, height: usize },
    /// The row stride cannot hold the requested pixels.
    RowStrideTooSmall { minimum: usize, actual: usize },
    /// Arithmetic required to describe the layout overflowed.
    ArithmeticOverflow,
    /// The backing slice does not include every byte that the C ABI may read.
    BufferTooSmall { required: usize, actual: usize },
}

impl fmt::Display for LayoutError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ZeroDimensions { width, height } => {
                write!(
                    formatter,
                    "dimensions must be positive, got {width}x{height}"
                )
            }
            Self::DimensionsOutOfRange { width, height } => {
                write!(
                    formatter,
                    "dimensions exceed the C ABI range: {width}x{height}"
                )
            }
            Self::RowStrideTooSmall { minimum, actual } => {
                write!(formatter, "row stride {actual} is smaller than {minimum}")
            }
            Self::ArithmeticOverflow => write!(formatter, "layout arithmetic overflows"),
            Self::BufferTooSmall { required, actual } => {
                write!(
                    formatter,
                    "buffer has {actual} bytes but {required} are required"
                )
            }
        }
    }
}

/// An error returned by a safe `strok` operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Error {
    /// Renderer grid dimensions must both be positive.
    InvalidGrid { columns: i32, rows: i32 },
    /// A borrowed input view does not describe a safe C ABI layout.
    Layout {
        input: InputKind,
        problem: LayoutError,
    },
    /// An optional depth or normal input does not match the color dimensions.
    InputDimensions {
        input: InputKind,
        expected: (usize, usize),
        actual: (usize, usize),
    },
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
            Self::InvalidGrid { .. }
            | Self::Layout { .. }
            | Self::InputDimensions { .. }
            | Self::InvalidCellGlyph { .. } => None,
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
            Self::Layout { input, problem } => {
                write!(
                    formatter,
                    "invalid {} image layout: {problem}",
                    input.name()
                )
            }
            Self::InputDimensions {
                input,
                expected,
                actual,
            } => write!(
                formatter,
                "{} image dimensions {}x{} do not match color dimensions {}x{}",
                input.name(),
                actual.0,
                actual.1,
                expected.0,
                expected.1
            ),
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

/// A supported packed color-pixel format.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ColorFormat {
    Rgb24,
    Rgba8,
    Bgra8,
}

impl ColorFormat {
    const fn bytes_per_pixel(self) -> usize {
        match self {
            Self::Rgb24 => 3,
            Self::Rgba8 | Self::Bgra8 => 4,
        }
    }

    const fn raw(self) -> sys::StrokColorPixelFormat {
        match self {
            Self::Rgb24 => sys::STROK_COLOR_PIXEL_FORMAT_RGB24,
            Self::Rgba8 => sys::STROK_COLOR_PIXEL_FORMAT_RGBA8,
            Self::Bgra8 => sys::STROK_COLOR_PIXEL_FORMAT_BGRA8,
        }
    }
}

/// A validated, borrowed packed color image.
///
/// The image keeps the byte slice borrowed and therefore cannot outlive it.
/// Padded rows are supported when `row_stride_bytes` includes every byte the C
/// ABI may read.
///
/// ```compile_fail
/// use strok::ColorImage;
///
/// let image = {
///     let pixels = [0_u8, 0, 0];
///     ColorImage::rgb24(&pixels, 1, 1, 3).unwrap()
/// };
/// let _ = image.dimensions();
/// ```
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ColorImage<'data> {
    data: &'data [u8],
    layout: ValidatedLayout,
    format: ColorFormat,
}

impl<'data> ColorImage<'data> {
    /// Validates a borrowed color image using an explicit C ABI pixel format.
    pub fn new(
        data: &'data [u8],
        width: usize,
        height: usize,
        row_stride_bytes: usize,
        format: ColorFormat,
    ) -> Result<Self, Error> {
        let row_bytes = width
            .checked_mul(format.bytes_per_pixel())
            .ok_or_else(|| layout_error(InputKind::Color, LayoutError::ArithmeticOverflow))?;
        let layout = validate_layout(
            InputKind::Color,
            width,
            height,
            row_stride_bytes,
            row_bytes,
            data.len(),
        )?;
        Ok(Self {
            data,
            layout,
            format,
        })
    }

    /// Validates a borrowed RGB24 image.
    pub fn rgb24(
        data: &'data [u8],
        width: usize,
        height: usize,
        row_stride_bytes: usize,
    ) -> Result<Self, Error> {
        Self::new(data, width, height, row_stride_bytes, ColorFormat::Rgb24)
    }

    /// Validates a borrowed RGBA8 image. Alpha is ignored by the C ABI.
    pub fn rgba8(
        data: &'data [u8],
        width: usize,
        height: usize,
        row_stride_bytes: usize,
    ) -> Result<Self, Error> {
        Self::new(data, width, height, row_stride_bytes, ColorFormat::Rgba8)
    }

    /// Validates a borrowed BGRA8 image. Alpha is ignored by the C ABI.
    pub fn bgra8(
        data: &'data [u8],
        width: usize,
        height: usize,
        row_stride_bytes: usize,
    ) -> Result<Self, Error> {
        Self::new(data, width, height, row_stride_bytes, ColorFormat::Bgra8)
    }

    /// Returns `(width, height)` in pixels.
    #[must_use]
    pub const fn dimensions(&self) -> (usize, usize) {
        (self.layout.width, self.layout.height)
    }

    /// Returns this image's pixel format.
    #[must_use]
    pub const fn format(&self) -> ColorFormat {
        self.format
    }

    fn raw(self) -> sys::StrokColorImageView {
        let mut image = MaybeUninit::<sys::StrokColorImageView>::uninit();
        unsafe {
            sys::strok_color_image_view_init(image.as_mut_ptr());
        }
        let mut image = unsafe { image.assume_init() };
        image.data = self.data.as_ptr();
        image.width = self.layout.c_width;
        image.height = self.layout.c_height;
        image.row_stride_bytes = self.layout.row_stride_bytes;
        image.pixel_format = self.format.raw();
        image
    }
}

/// A validated, borrowed Float64 camera-linear depth image.
///
/// `row_stride_elements` is measured in `f64` elements, allowing padded rows
/// without exposing byte-alignment concerns to safe callers.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct DepthImage<'data> {
    data: &'data [f64],
    layout: ValidatedLayout,
}

impl<'data> DepthImage<'data> {
    /// Validates a borrowed depth image with an `f64` element stride.
    pub fn new(
        data: &'data [f64],
        width: usize,
        height: usize,
        row_stride_elements: usize,
    ) -> Result<Self, Error> {
        let element_size = std::mem::size_of::<f64>();
        let row_bytes = width
            .checked_mul(element_size)
            .ok_or_else(|| layout_error(InputKind::Depth, LayoutError::ArithmeticOverflow))?;
        let row_stride_bytes = row_stride_elements
            .checked_mul(element_size)
            .ok_or_else(|| layout_error(InputKind::Depth, LayoutError::ArithmeticOverflow))?;
        let data_len_bytes = data
            .len()
            .checked_mul(element_size)
            .ok_or_else(|| layout_error(InputKind::Depth, LayoutError::ArithmeticOverflow))?;
        let layout = validate_layout(
            InputKind::Depth,
            width,
            height,
            row_stride_bytes,
            row_bytes,
            data_len_bytes,
        )?;
        Ok(Self { data, layout })
    }

    /// Returns `(width, height)` in pixels.
    #[must_use]
    pub const fn dimensions(&self) -> (usize, usize) {
        (self.layout.width, self.layout.height)
    }

    fn raw(self) -> sys::StrokDepthImageView {
        let mut image = MaybeUninit::<sys::StrokDepthImageView>::uninit();
        unsafe {
            sys::strok_depth_image_view_init(image.as_mut_ptr());
        }
        let mut image = unsafe { image.assume_init() };
        image.data = self.data.as_ptr();
        image.width = self.layout.c_width;
        image.height = self.layout.c_height;
        image.row_stride_bytes = self.layout.row_stride_bytes;
        image
    }
}

/// A validated, borrowed Float64x3 view-space normal image.
///
/// `row_stride_pixels` is measured in three-component normal pixels, allowing
/// padded rows without exposing byte-alignment concerns to safe callers.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct NormalImage<'data> {
    data: &'data [[f64; 3]],
    layout: ValidatedLayout,
}

impl<'data> NormalImage<'data> {
    /// Validates a borrowed normal image with a normal-pixel stride.
    pub fn new(
        data: &'data [[f64; 3]],
        width: usize,
        height: usize,
        row_stride_pixels: usize,
    ) -> Result<Self, Error> {
        let pixel_size = std::mem::size_of::<[f64; 3]>();
        let row_bytes = width
            .checked_mul(pixel_size)
            .ok_or_else(|| layout_error(InputKind::Normals, LayoutError::ArithmeticOverflow))?;
        let row_stride_bytes = row_stride_pixels
            .checked_mul(pixel_size)
            .ok_or_else(|| layout_error(InputKind::Normals, LayoutError::ArithmeticOverflow))?;
        let data_len_bytes = data
            .len()
            .checked_mul(pixel_size)
            .ok_or_else(|| layout_error(InputKind::Normals, LayoutError::ArithmeticOverflow))?;
        let layout = validate_layout(
            InputKind::Normals,
            width,
            height,
            row_stride_bytes,
            row_bytes,
            data_len_bytes,
        )?;
        Ok(Self { data, layout })
    }

    /// Returns `(width, height)` in pixels.
    #[must_use]
    pub const fn dimensions(&self) -> (usize, usize) {
        (self.layout.width, self.layout.height)
    }

    fn raw(self) -> sys::StrokNormalImageView {
        let mut image = MaybeUninit::<sys::StrokNormalImageView>::uninit();
        unsafe {
            sys::strok_normal_image_view_init(image.as_mut_ptr());
        }
        let mut image = unsafe { image.assume_init() };
        image.data = self.data.as_ptr().cast::<f64>();
        image.width = self.layout.c_width;
        image.height = self.layout.c_height;
        image.row_stride_bytes = self.layout.row_stride_bytes;
        image
    }
}

/// Color input with optional matching depth and view-space normal inputs.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RenderInput<'data> {
    color: ColorImage<'data>,
    depth: Option<DepthImage<'data>>,
    normals: Option<NormalImage<'data>>,
}

impl<'data> RenderInput<'data> {
    /// Starts a color-only render input.
    #[must_use]
    pub const fn new(color: ColorImage<'data>) -> Self {
        Self {
            color,
            depth: None,
            normals: None,
        }
    }

    /// Adds a depth image whose dimensions must match the color image.
    pub fn with_depth(mut self, depth: DepthImage<'data>) -> Result<Self, Error> {
        self.require_matching_dimensions(InputKind::Depth, depth.dimensions())?;
        self.depth = Some(depth);
        Ok(self)
    }

    /// Adds a normal image whose dimensions must match the color image.
    pub fn with_normals(mut self, normals: NormalImage<'data>) -> Result<Self, Error> {
        self.require_matching_dimensions(InputKind::Normals, normals.dimensions())?;
        self.normals = Some(normals);
        Ok(self)
    }

    fn require_matching_dimensions(
        &self,
        input: InputKind,
        actual: (usize, usize),
    ) -> Result<(), Error> {
        let expected = self.color.dimensions();
        if actual != expected {
            return Err(Error::InputDimensions {
                input,
                expected,
                actual,
            });
        }
        Ok(())
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

    /// Renders a borrowed color image without retaining its byte slice.
    pub fn render_color(&mut self, image: ColorImage<'_>) -> Result<(), Error> {
        let image = image.raw();
        let status = unsafe { sys::strok_renderer_render_color(self.raw.as_ptr(), &image) };
        status_result(status)
    }

    /// Renders borrowed color input with optional matching depth and normals.
    ///
    /// The C ABI receives the borrowed views only for this synchronous call; no
    /// input slice is retained after this function returns.
    pub fn render(&mut self, input: RenderInput<'_>) -> Result<(), Error> {
        let color = input.color.raw();
        let depth = input.depth.map(DepthImage::raw);
        let normals = input.normals.map(NormalImage::raw);
        let mut raw_input = MaybeUninit::<sys::StrokRenderInput>::uninit();
        unsafe {
            sys::strok_render_input_init(raw_input.as_mut_ptr());
        }
        let mut raw_input = unsafe { raw_input.assume_init() };
        raw_input.color = &color;
        raw_input.depth = depth.as_ref().map_or(ptr::null(), |view| view);
        raw_input.normals = normals.as_ref().map_or(ptr::null(), |view| view);
        let status = unsafe { sys::strok_renderer_render_input(self.raw.as_ptr(), &raw_input) };
        status_result(status)
    }

    /// Returns the result of the most recent successful render.
    ///
    /// The C ABI reports an error until a render has completed successfully.
    /// The returned view borrows this renderer, while rendering requires
    /// `&mut self`, preventing stale result access in safe Rust.
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
/// from outliving the renderer or a later successful render.
///
/// ```compile_fail
/// use strok::{ColorImage, Grid, Renderer, RendererConfig};
///
/// let pixels = [0_u8, 0, 0];
/// let image = ColorImage::rgb24(&pixels, 1, 1, 3).unwrap();
/// let mut renderer = Renderer::new(RendererConfig::default(), Grid::new(1, 1).unwrap()).unwrap();
/// let cells = renderer.cells().unwrap();
/// renderer.render_color(image).unwrap();
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

#[derive(Clone, Copy, Debug, PartialEq)]
struct ValidatedLayout {
    width: usize,
    height: usize,
    c_width: i32,
    c_height: i32,
    row_stride_bytes: u64,
}

fn layout_error(input: InputKind, problem: LayoutError) -> Error {
    Error::Layout { input, problem }
}

fn validate_layout(
    input: InputKind,
    width: usize,
    height: usize,
    row_stride_bytes: usize,
    row_bytes: usize,
    data_len_bytes: usize,
) -> Result<ValidatedLayout, Error> {
    if width == 0 || height == 0 {
        return Err(layout_error(
            input,
            LayoutError::ZeroDimensions { width, height },
        ));
    }
    let c_width = i32::try_from(width)
        .map_err(|_| layout_error(input, LayoutError::DimensionsOutOfRange { width, height }))?;
    let c_height = i32::try_from(height)
        .map_err(|_| layout_error(input, LayoutError::DimensionsOutOfRange { width, height }))?;
    width
        .checked_mul(height)
        .ok_or_else(|| layout_error(input, LayoutError::ArithmeticOverflow))?;
    if row_stride_bytes < row_bytes {
        return Err(layout_error(
            input,
            LayoutError::RowStrideTooSmall {
                minimum: row_bytes,
                actual: row_stride_bytes,
            },
        ));
    }
    let required_bytes = height
        .checked_sub(1)
        .and_then(|rows_before_last| rows_before_last.checked_mul(row_stride_bytes))
        .and_then(|offset| offset.checked_add(row_bytes))
        .ok_or_else(|| layout_error(input, LayoutError::ArithmeticOverflow))?;
    if data_len_bytes < required_bytes {
        return Err(layout_error(
            input,
            LayoutError::BufferTooSmall {
                required: required_bytes,
                actual: data_len_bytes,
            },
        ));
    }
    let row_stride_bytes = u64::try_from(row_stride_bytes)
        .map_err(|_| layout_error(input, LayoutError::ArithmeticOverflow))?;
    Ok(ValidatedLayout {
        width,
        height,
        c_width,
        c_height,
        row_stride_bytes,
    })
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

    fn assert_rendered(renderer: &Renderer) {
        let cells = renderer.cells().unwrap();
        assert!(cells.dimensions().0 > 0 && cells.dimensions().1 > 0);
        assert!(cells.get(0, 0).unwrap().is_some());
        assert_eq!(
            cells.iter().collect::<Result<Vec<_>, _>>().unwrap().len(),
            cells.len()
        );
    }

    #[test]
    fn borrowed_rgb_and_rgba_images_support_padded_rows() {
        let rgb = [0_u8, 0, 0, 255, 0, 0, 99, 99, 0, 255, 0, 255, 255, 255];
        let rgba = [
            0_u8, 0, 255, 255, 255, 255, 0, 255, 99, 99, 0, 255, 255, 255, 255, 255, 255, 0,
        ];
        let mut renderer = renderer();

        renderer
            .render_color(ColorImage::rgb24(&rgb, 2, 2, 8).unwrap())
            .unwrap();
        assert_rendered(&renderer);
        renderer
            .render_color(ColorImage::rgba8(&rgba, 2, 2, 10).unwrap())
            .unwrap();
        assert_rendered(&renderer);
        renderer.reset().unwrap();
        assert_rendered(&renderer);
    }

    #[test]
    fn rich_input_borrows_matching_depth_and_normals() {
        let color = [
            0_u8, 0, 0, 255, 0, 0, 77, 77, 0, 255, 0, 0, 255, 255, 255, 77, 77,
        ];
        let depth = [1.0, 2.0, 99.0, 3.0, 4.0];
        let normals = [
            [0.0, 0.0, 1.0],
            [0.0, 0.0, 1.0],
            [9.0, 9.0, 9.0],
            [0.0, 0.0, 1.0],
            [0.0, 0.0, 1.0],
        ];
        let color = ColorImage::rgb24(&color, 2, 2, 8).unwrap();
        let depth = DepthImage::new(&depth, 2, 2, 3).unwrap();
        let normals = NormalImage::new(&normals, 2, 2, 3).unwrap();
        let input = RenderInput::new(color)
            .with_depth(depth)
            .unwrap()
            .with_normals(normals)
            .unwrap();
        let mut renderer = renderer();

        renderer
            .render(RenderInput::new(color).with_depth(depth).unwrap())
            .unwrap();
        assert_rendered(&renderer);
        renderer
            .render(RenderInput::new(color).with_normals(normals).unwrap())
            .unwrap();
        assert_rendered(&renderer);
        renderer.render(input).unwrap();
        assert_rendered(&renderer);
    }

    #[test]
    fn invalid_layouts_and_dimension_mismatches_are_errors() {
        let color = [0_u8; 12];
        assert_eq!(
            ColorImage::rgb24(&color, 2, 1, 5),
            Err(Error::Layout {
                input: InputKind::Color,
                problem: LayoutError::RowStrideTooSmall {
                    minimum: 6,
                    actual: 5,
                },
            })
        );
        assert_eq!(
            ColorImage::rgba8(&color, 2, 2, 8),
            Err(Error::Layout {
                input: InputKind::Color,
                problem: LayoutError::BufferTooSmall {
                    required: 16,
                    actual: 12,
                },
            })
        );
        assert!(matches!(
            DepthImage::new(&[1.0], 1, 2, 1),
            Err(Error::Layout {
                input: InputKind::Depth,
                problem: LayoutError::BufferTooSmall { .. },
            })
        ));

        let color = ColorImage::rgb24(&[0_u8; 6], 2, 1, 6).unwrap();
        let depth = DepthImage::new(&[1.0], 1, 1, 1).unwrap();
        assert_eq!(
            RenderInput::new(color).with_depth(depth),
            Err(Error::InputDimensions {
                input: InputKind::Depth,
                expected: (2, 1),
                actual: (1, 1),
            })
        );
    }

    #[test]
    fn invalid_configuration_returns_an_error_without_panicking() {
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
