#define PY_SSIZE_T_CLEAN
#include <Python.h>

#include <limits.h>
#include <string.h>

#include <strok/c_api.h>

typedef struct {
  PyObject_HEAD
  StrokRenderer* renderer;
  unsigned long generation;
} StrokRendererObject;

typedef struct {
  PyObject_HEAD
  StrokRendererObject* renderer;
  unsigned long generation;
  int32_t columns;
  int32_t rows;
} StrokCellBufferObject;

typedef struct {
  Py_buffer buffer;
  StrokColorImageView image;
  int acquired;
} StrokColorArrayView;

typedef struct {
  Py_buffer buffer;
  StrokDepthImageView image;
  int acquired;
} StrokDepthArrayView;

typedef struct {
  Py_buffer buffer;
  StrokNormalImageView image;
  int acquired;
} StrokNormalArrayView;

static PyObject* StrokStaleResultError;

static int strok_status_succeeded(StrokStatus status) {
  return status == STROK_STATUS_SUCCESS || status == STROK_STATUS_BACKEND_FALLBACK;
}

static int strok_set_status_error(StrokStatus status) {
  const char* message = strok_last_error_message();
  if (message == NULL || message[0] == '\0') {
    message = "strok C ABI operation failed";
  }
  if (status == STROK_STATUS_INVALID_ARGUMENT || status == STROK_STATUS_INVALID_INPUT ||
      status == STROK_STATUS_INVALID_CONFIGURATION) {
    PyErr_SetString(PyExc_ValueError, message);
  } else {
    PyErr_SetString(PyExc_RuntimeError, message);
  }
  return -1;
}

static int strok_renderer_require_open(const StrokRendererObject* self) {
  if (self->renderer == NULL) {
    PyErr_SetString(PyExc_RuntimeError, "strok renderer is closed");
    return -1;
  }
  return 0;
}

static int strok_require_numpy_array(PyObject* object) {
  PyObject* numpy = PyImport_ImportModule("numpy");
  PyObject* array_type;
  int is_array;

  if (numpy == NULL) {
    return -1;
  }
  array_type = PyObject_GetAttrString(numpy, "ndarray");
  Py_DECREF(numpy);
  if (array_type == NULL) {
    return -1;
  }
  is_array = PyObject_IsInstance(object, array_type);
  Py_DECREF(array_type);
  if (is_array < 0) {
    return -1;
  }
  if (is_array == 0) {
    PyErr_SetString(PyExc_TypeError, "expected a numpy.ndarray");
    return -1;
  }
  return 0;
}

static int strok_array_dimensions(Py_ssize_t height, Py_ssize_t width, int32_t* out_width, int32_t* out_height) {
  if (width <= 0 || height <= 0) {
    PyErr_SetString(PyExc_ValueError, "array dimensions must be positive");
    return -1;
  }
  if (width > INT32_MAX || height > INT32_MAX) {
    PyErr_SetString(PyExc_ValueError, "array dimensions exceed the strok C ABI range");
    return -1;
  }
  *out_width = (int32_t)width;
  *out_height = (int32_t)height;
  return 0;
}

static void strok_color_array_view_release(StrokColorArrayView* view) {
  if (view->acquired) {
    PyBuffer_Release(&view->buffer);
    view->acquired = 0;
  }
}

static void strok_depth_array_view_release(StrokDepthArrayView* view) {
  if (view->acquired) {
    PyBuffer_Release(&view->buffer);
    view->acquired = 0;
  }
}

static void strok_normal_array_view_release(StrokNormalArrayView* view) {
  if (view->acquired) {
    PyBuffer_Release(&view->buffer);
    view->acquired = 0;
  }
}

static int strok_color_array_view_init(StrokColorArrayView* view, PyObject* array) {
  Py_ssize_t height;
  Py_ssize_t width;
  Py_ssize_t channels;
  Py_ssize_t pixel_bytes;
  int32_t c_width;
  int32_t c_height;

  memset(view, 0, sizeof(*view));
  if (strok_require_numpy_array(array) < 0 ||
      PyObject_GetBuffer(array, &view->buffer, PyBUF_FORMAT | PyBUF_STRIDES | PyBUF_ND) < 0) {
    return -1;
  }
  view->acquired = 1;
  if (view->buffer.ndim != 3 || view->buffer.format == NULL || strcmp(view->buffer.format, "B") != 0 ||
      view->buffer.itemsize != 1) {
    PyErr_SetString(PyExc_ValueError, "color array must have dtype uint8 and shape (height, width, 3 or 4)");
    goto invalid;
  }
  height = view->buffer.shape[0];
  width = view->buffer.shape[1];
  channels = view->buffer.shape[2];
  if (channels != 3 && channels != 4) {
    PyErr_SetString(PyExc_ValueError, "color array must have 3 RGB or 4 RGBA channels");
    goto invalid;
  }
  if (strok_array_dimensions(height, width, &c_width, &c_height) < 0) {
    goto invalid;
  }
  pixel_bytes = channels;
  if (width > PY_SSIZE_T_MAX / pixel_bytes) {
    PyErr_SetString(PyExc_ValueError, "color array row size overflows");
    goto invalid;
  }
  if (view->buffer.strides[2] != 1 || view->buffer.strides[1] != pixel_bytes ||
      view->buffer.strides[0] < width * pixel_bytes) {
    PyErr_SetString(PyExc_ValueError, "color array must have contiguous channels and pixels with a positive row stride");
    goto invalid;
  }
  strok_color_image_view_init(&view->image);
  view->image.data = view->buffer.buf;
  view->image.width = c_width;
  view->image.height = c_height;
  view->image.row_stride_bytes = (uint64_t)view->buffer.strides[0];
  view->image.pixel_format = channels == 3 ? STROK_COLOR_PIXEL_FORMAT_RGB24 : STROK_COLOR_PIXEL_FORMAT_RGBA8;
  return 0;

invalid:
  strok_color_array_view_release(view);
  return -1;
}

static int strok_depth_array_view_init(StrokDepthArrayView* view, PyObject* array) {
  Py_ssize_t height;
  Py_ssize_t width;
  int32_t c_width;
  int32_t c_height;

  memset(view, 0, sizeof(*view));
  if (strok_require_numpy_array(array) < 0 ||
      PyObject_GetBuffer(array, &view->buffer, PyBUF_FORMAT | PyBUF_STRIDES | PyBUF_ND) < 0) {
    return -1;
  }
  view->acquired = 1;
  if (view->buffer.ndim != 2 || view->buffer.format == NULL || strcmp(view->buffer.format, "d") != 0 ||
      view->buffer.itemsize != sizeof(double)) {
    PyErr_SetString(PyExc_ValueError, "depth array must have dtype float64 and shape (height, width)");
    goto invalid;
  }
  height = view->buffer.shape[0];
  width = view->buffer.shape[1];
  if (strok_array_dimensions(height, width, &c_width, &c_height) < 0) {
    goto invalid;
  }
  if (width > PY_SSIZE_T_MAX / (Py_ssize_t)sizeof(double)) {
    PyErr_SetString(PyExc_ValueError, "depth array row size overflows");
    goto invalid;
  }
  if (view->buffer.strides[1] != (Py_ssize_t)sizeof(double) ||
      view->buffer.strides[0] < width * (Py_ssize_t)sizeof(double) ||
      view->buffer.strides[0] % (Py_ssize_t)sizeof(double) != 0) {
    PyErr_SetString(PyExc_ValueError, "depth array must have contiguous float64 pixels with an aligned positive row stride");
    goto invalid;
  }
  strok_depth_image_view_init(&view->image);
  view->image.data = view->buffer.buf;
  view->image.width = c_width;
  view->image.height = c_height;
  view->image.row_stride_bytes = (uint64_t)view->buffer.strides[0];
  return 0;

invalid:
  strok_depth_array_view_release(view);
  return -1;
}

static int strok_normal_array_view_init(StrokNormalArrayView* view, PyObject* array) {
  Py_ssize_t height;
  Py_ssize_t width;
  Py_ssize_t components;
  int32_t c_width;
  int32_t c_height;
  const Py_ssize_t pixel_bytes = 3 * (Py_ssize_t)sizeof(double);

  memset(view, 0, sizeof(*view));
  if (strok_require_numpy_array(array) < 0 ||
      PyObject_GetBuffer(array, &view->buffer, PyBUF_FORMAT | PyBUF_STRIDES | PyBUF_ND) < 0) {
    return -1;
  }
  view->acquired = 1;
  if (view->buffer.ndim != 3 || view->buffer.format == NULL || strcmp(view->buffer.format, "d") != 0 ||
      view->buffer.itemsize != sizeof(double)) {
    PyErr_SetString(PyExc_ValueError, "normal array must have dtype float64 and shape (height, width, 3)");
    goto invalid;
  }
  height = view->buffer.shape[0];
  width = view->buffer.shape[1];
  components = view->buffer.shape[2];
  if (components != 3) {
    PyErr_SetString(PyExc_ValueError, "normal array must have exactly 3 components per pixel");
    goto invalid;
  }
  if (strok_array_dimensions(height, width, &c_width, &c_height) < 0) {
    goto invalid;
  }
  if (width > PY_SSIZE_T_MAX / pixel_bytes) {
    PyErr_SetString(PyExc_ValueError, "normal array row size overflows");
    goto invalid;
  }
  if (view->buffer.strides[2] != (Py_ssize_t)sizeof(double) || view->buffer.strides[1] != pixel_bytes ||
      view->buffer.strides[0] < width * pixel_bytes || view->buffer.strides[0] % (Py_ssize_t)sizeof(double) != 0) {
    PyErr_SetString(PyExc_ValueError, "normal array must have contiguous Float64x3 pixels with an aligned positive row stride");
    goto invalid;
  }
  strok_normal_image_view_init(&view->image);
  view->image.data = view->buffer.buf;
  view->image.width = c_width;
  view->image.height = c_height;
  view->image.row_stride_bytes = (uint64_t)view->buffer.strides[0];
  return 0;

invalid:
  strok_normal_array_view_release(view);
  return -1;
}

static int strok_cell_buffer_require_current(const StrokCellBufferObject* self) {
  if (strok_renderer_require_open(self->renderer) < 0) {
    return -1;
  }
  if (self->generation != self->renderer->generation) {
    PyErr_SetString(StrokStaleResultError, "strok CellBuffer was replaced by a later successful render");
    return -1;
  }
  return 0;
}

static int strok_renderer_init(StrokRendererObject* self, PyObject* arguments, PyObject* keywords) {
  static char* keyword_names[] = {"columns", "rows", "cell_aspect", NULL};
  int columns = 0;
  int rows = 0;
  double cell_aspect = 0.5;
  StrokRendererConfig config;
  StrokRenderGrid grid;
  StrokRenderer* renderer = NULL;
  StrokStatus status;

  if (!PyArg_ParseTupleAndKeywords(arguments, keywords, "ii|d:Renderer", keyword_names,
                                   &columns, &rows, &cell_aspect)) {
    return -1;
  }
  strok_renderer_config_init(&config);
  strok_render_grid_init(&grid);
  config.cell_aspect = cell_aspect;
  grid.cols = columns;
  grid.rows = rows;
  status = strok_renderer_create(&config, &grid, &renderer);
  if (!strok_status_succeeded(status)) {
    return strok_set_status_error(status);
  }
  if (renderer == NULL) {
    PyErr_SetString(PyExc_RuntimeError, "strok C ABI created no renderer");
    return -1;
  }
  strok_renderer_destroy(self->renderer);
  self->renderer = renderer;
  self->generation += 1;
  return 0;
}

static void strok_renderer_dealloc(StrokRendererObject* self) {
  strok_renderer_destroy(self->renderer);
  self->renderer = NULL;
  Py_TYPE(self)->tp_free((PyObject*)self);
}

static PyObject* strok_renderer_close(StrokRendererObject* self, PyObject* ignored) {
  (void)ignored;
  strok_renderer_destroy(self->renderer);
  self->renderer = NULL;
  Py_RETURN_NONE;
}

static PyObject* strok_python_renderer_reset(StrokRendererObject* self, PyObject* ignored) {
  StrokStatus status;

  (void)ignored;
  if (strok_renderer_require_open(self) < 0) {
    return NULL;
  }
  status = strok_renderer_reset(self->renderer);
  if (!strok_status_succeeded(status)) {
    return strok_set_status_error(status), NULL;
  }
  Py_RETURN_NONE;
}

static PyObject* strok_renderer_render_rgb(StrokRendererObject* self, PyObject* arguments) {
  PyObject* data = NULL;
  int width = 0;
  int height = 0;
  Py_buffer buffer = {0};
  size_t row_stride = 0;
  size_t required_size = 0;
  StrokColorImageView image;
  StrokStatus status;
  Py_ssize_t buffer_length;

  if (!PyArg_ParseTuple(arguments, "Oii:render_rgb", &data, &width, &height)) {
    return NULL;
  }
  if (strok_renderer_require_open(self) < 0) {
    return NULL;
  }
  if (width <= 0 || height <= 0) {
    PyErr_SetString(PyExc_ValueError, "RGB image dimensions must be positive");
    return NULL;
  }
  if ((size_t)width > SIZE_MAX / 3U) {
    PyErr_SetString(PyExc_ValueError, "RGB image row size overflows");
    return NULL;
  }
  row_stride = (size_t)width * 3U;
  if ((size_t)height > SIZE_MAX / row_stride) {
    PyErr_SetString(PyExc_ValueError, "RGB image layout overflows");
    return NULL;
  }
  required_size = (size_t)height * row_stride;
  if (PyObject_GetBuffer(data, &buffer, PyBUF_CONTIG_RO) < 0) {
    return NULL;
  }
  if ((size_t)buffer.len != required_size) {
    buffer_length = buffer.len;
    PyBuffer_Release(&buffer);
    PyErr_Format(PyExc_ValueError, "RGB buffer has %zd bytes but %zu are required", buffer_length, required_size);
    return NULL;
  }

  strok_color_image_view_init(&image);
  image.data = buffer.buf;
  image.width = width;
  image.height = height;
  image.row_stride_bytes = row_stride;
  image.pixel_format = STROK_COLOR_PIXEL_FORMAT_RGB24;
  status = strok_renderer_render_color(self->renderer, &image);
  PyBuffer_Release(&buffer);
  if (!strok_status_succeeded(status)) {
    return strok_set_status_error(status), NULL;
  }
  self->generation += 1;
  Py_RETURN_NONE;
}

static PyObject* strok_renderer_render_numpy(StrokRendererObject* self, PyObject* arguments, PyObject* keywords) {
  static char* keyword_names[] = {"color", "depth", "normals", NULL};
  PyObject* color = NULL;
  PyObject* depth = Py_None;
  PyObject* normals = Py_None;
  StrokColorArrayView color_view;
  StrokDepthArrayView depth_view;
  StrokNormalArrayView normal_view;
  StrokRenderInput input;
  StrokStatus status;

  memset(&color_view, 0, sizeof(color_view));
  memset(&depth_view, 0, sizeof(depth_view));
  memset(&normal_view, 0, sizeof(normal_view));
  if (!PyArg_ParseTupleAndKeywords(arguments, keywords, "O|OO:render_numpy", keyword_names,
                                   &color, &depth, &normals)) {
    return NULL;
  }
  if (strok_renderer_require_open(self) < 0 || strok_color_array_view_init(&color_view, color) < 0) {
    goto failed;
  }
  if (depth != Py_None && strok_depth_array_view_init(&depth_view, depth) < 0) {
    goto failed;
  }
  if (normals != Py_None && strok_normal_array_view_init(&normal_view, normals) < 0) {
    goto failed;
  }
  if (depth_view.acquired &&
      (depth_view.image.width != color_view.image.width || depth_view.image.height != color_view.image.height)) {
    PyErr_SetString(PyExc_ValueError, "depth array dimensions must match color array dimensions");
    goto failed;
  }
  if (normal_view.acquired &&
      (normal_view.image.width != color_view.image.width || normal_view.image.height != color_view.image.height)) {
    PyErr_SetString(PyExc_ValueError, "normal array dimensions must match color array dimensions");
    goto failed;
  }
  strok_render_input_init(&input);
  input.color = &color_view.image;
  input.depth = depth_view.acquired ? &depth_view.image : NULL;
  input.normals = normal_view.acquired ? &normal_view.image : NULL;
  status = strok_renderer_render_input(self->renderer, &input);
  strok_normal_array_view_release(&normal_view);
  strok_depth_array_view_release(&depth_view);
  strok_color_array_view_release(&color_view);
  if (!strok_status_succeeded(status)) {
    return strok_set_status_error(status), NULL;
  }
  self->generation += 1;
  Py_RETURN_NONE;

failed:
  strok_normal_array_view_release(&normal_view);
  strok_depth_array_view_release(&depth_view);
  strok_color_array_view_release(&color_view);
  return NULL;
}

static PyTypeObject StrokCellBufferType;

static PyObject* strok_renderer_cells(StrokRendererObject* self, PyObject* ignored) {
  int32_t columns = 0;
  int32_t rows = 0;
  StrokStatus status;
  StrokCellBufferObject* cells;

  (void)ignored;
  if (strok_renderer_require_open(self) < 0) {
    return NULL;
  }
  status = strok_renderer_cell_buffer_dimensions(self->renderer, &columns, &rows);
  if (!strok_status_succeeded(status)) {
    return strok_set_status_error(status), NULL;
  }
  cells = PyObject_New(StrokCellBufferObject, &StrokCellBufferType);
  if (cells == NULL) {
    return NULL;
  }
  Py_INCREF(self);
  cells->renderer = self;
  cells->generation = self->generation;
  cells->columns = columns;
  cells->rows = rows;
  return (PyObject*)cells;
}

static PyMethodDef strok_renderer_methods[] = {
    {"close", (PyCFunction)strok_renderer_close, METH_NOARGS, "Destroy the native renderer handle."},
    {"reset", (PyCFunction)strok_python_renderer_reset, METH_NOARGS, "Reset renderer temporal state."},
    {"render_rgb", (PyCFunction)strok_renderer_render_rgb, METH_VARARGS,
     "Render a contiguous RGB24 buffer without retaining it."},
    {"render_numpy", (PyCFunction)(void(*)(void))strok_renderer_render_numpy, METH_VARARGS | METH_KEYWORDS,
     "Render NumPy RGB/RGBA color with optional Float64 depth and normals without copying."},
    {"cells", (PyCFunction)strok_renderer_cells, METH_NOARGS,
     "Return the CellBuffer from the most recent successful render."},
    {NULL, NULL, 0, NULL},
};

static PyTypeObject StrokRendererType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "strok.Renderer",
    .tp_basicsize = sizeof(StrokRendererObject),
    .tp_dealloc = (destructor)strok_renderer_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Owned strok C ABI renderer.",
    .tp_methods = strok_renderer_methods,
    .tp_init = (initproc)strok_renderer_init,
    .tp_new = PyType_GenericNew,
};

static void strok_cell_buffer_dealloc(StrokCellBufferObject* self) {
  Py_XDECREF(self->renderer);
  Py_TYPE(self)->tp_free((PyObject*)self);
}

static PyObject* strok_cell_buffer_dimensions(StrokCellBufferObject* self, PyObject* ignored) {
  (void)ignored;
  if (strok_cell_buffer_require_current(self) < 0) {
    return NULL;
  }
  return Py_BuildValue("(ii)", self->columns, self->rows);
}

static PyObject* strok_cell_buffer_cell(StrokCellBufferObject* self, PyObject* arguments) {
  int column = 0;
  int row = 0;
  StrokCell cell;
  StrokStatus status;
  PyObject* glyph;

  if (!PyArg_ParseTuple(arguments, "ii:cell", &column, &row)) {
    return NULL;
  }
  if (strok_cell_buffer_require_current(self) < 0) {
    return NULL;
  }
  if (column < 0 || row < 0 || column >= self->columns || row >= self->rows) {
    PyErr_SetString(PyExc_IndexError, "CellBuffer coordinates are out of range");
    return NULL;
  }
  status = strok_renderer_cell_buffer_at(self->renderer->renderer, column, row, &cell);
  if (!strok_status_succeeded(status)) {
    return strok_set_status_error(status), NULL;
  }
  glyph = PyUnicode_FromOrdinal((int)cell.glyph);
  if (glyph == NULL) {
    return NULL;
  }
  return Py_BuildValue("N(iii)(iii)", glyph, (int)cell.fg_r, (int)cell.fg_g, (int)cell.fg_b,
                       (int)cell.bg_r, (int)cell.bg_g, (int)cell.bg_b);
}

static PyMethodDef strok_cell_buffer_methods[] = {
    {"dimensions", (PyCFunction)strok_cell_buffer_dimensions, METH_NOARGS,
     "Return the current CellBuffer dimensions."},
    {"cell", (PyCFunction)strok_cell_buffer_cell, METH_VARARGS,
     "Return (glyph, foreground_rgb, background_rgb) for one cell."},
    {NULL, NULL, 0, NULL},
};

static PyTypeObject StrokCellBufferType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "strok.CellBuffer",
    .tp_basicsize = sizeof(StrokCellBufferObject),
    .tp_dealloc = (destructor)strok_cell_buffer_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Read-only CellBuffer result borrowed from a Renderer.",
    .tp_methods = strok_cell_buffer_methods,
};

static PyObject* strok_abi_version(PyObject* self, PyObject* ignored) {
  (void)self;
  (void)ignored;
  return PyLong_FromUnsignedLong(STROK_C_ABI_VERSION);
}

static PyMethodDef strok_methods[] = {
    {"abi_version", (PyCFunction)strok_abi_version, METH_NOARGS,
     "Return the C ABI version linked by this extension."},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef strok_module = {
    PyModuleDef_HEAD_INIT,
    "_strok",
    "Native C ABI binding for strok.",
    -1,
    strok_methods,
};

PyMODINIT_FUNC PyInit__strok(void) {
  StrokRendererConfig config;
  PyObject* module;

  strok_renderer_config_init(&config);
  if (config.version != STROK_C_ABI_VERSION || config.struct_size != sizeof(config)) {
    PyErr_Format(
        PyExc_ImportError,
        "strok C ABI mismatch: expected version %u and config size %zu, got version %u and config size %u",
        STROK_C_ABI_VERSION,
        sizeof(config),
        config.version,
        config.struct_size);
    return NULL;
  }
  if (PyType_Ready(&StrokRendererType) < 0 || PyType_Ready(&StrokCellBufferType) < 0) {
    return NULL;
  }
  module = PyModule_Create(&strok_module);
  if (module == NULL) {
    return NULL;
  }
  StrokStaleResultError = PyErr_NewException("strok.StaleResultError", PyExc_RuntimeError, NULL);
  if (StrokStaleResultError == NULL) {
    Py_DECREF(module);
    return NULL;
  }
  Py_INCREF(&StrokRendererType);
  if (PyModule_AddObject(module, "Renderer", (PyObject*)&StrokRendererType) < 0) {
    Py_DECREF(&StrokRendererType);
    Py_DECREF(StrokStaleResultError);
    Py_DECREF(module);
    return NULL;
  }
  Py_INCREF(&StrokCellBufferType);
  if (PyModule_AddObject(module, "CellBuffer", (PyObject*)&StrokCellBufferType) < 0) {
    Py_DECREF(&StrokCellBufferType);
    Py_DECREF(StrokStaleResultError);
    Py_DECREF(module);
    return NULL;
  }
  Py_INCREF(StrokStaleResultError);
  if (PyModule_AddObject(module, "StaleResultError", StrokStaleResultError) < 0) {
    Py_DECREF(StrokStaleResultError);
    Py_DECREF(StrokStaleResultError);
    Py_DECREF(module);
    return NULL;
  }
  return module;
}
