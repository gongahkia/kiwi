#ifndef STROK_C_API_H
#define STROK_C_API_H

#include <stdint.h>

/*
 * C ABI policy:
 *
 * - Future exported functions use STROK_C_API and STROK_C_CALL. The build
 *   defining STROK_C_API_BUILD owns their exported definitions; consumers only
 *   import them on Windows.
 * - All ABI scalars use fixed-width integer types from <stdint.h>. Future public
 *   structures begin with version and size fields and grow only additively within
 *   one ABI major version.
 * - No C++ exceptions, references, STL types, or C++ object layouts cross this
 *   boundary. ABI functions report failures through C-safe result values.
 */

#define STROK_C_ABI_VERSION_MAJOR 1u
#define STROK_C_ABI_VERSION_MINOR 2u
#define STROK_C_ABI_VERSION ((STROK_C_ABI_VERSION_MAJOR << 16) | STROK_C_ABI_VERSION_MINOR)

#if defined(_WIN32) || defined(__CYGWIN__)
  #if defined(STROK_C_API_BUILD)
    #define STROK_C_API __declspec(dllexport)
  #else
    #define STROK_C_API __declspec(dllimport)
  #endif
  #define STROK_C_CALL __cdecl
#elif defined(__GNUC__) || defined(__clang__)
  #define STROK_C_API __attribute__((visibility("default")))
  #define STROK_C_CALL
#else
  #define STROK_C_API
  #define STROK_C_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t StrokRendererMode;
enum {
  STROK_RENDERER_MODE_AUTO = UINT32_C(0),
  STROK_RENDERER_MODE_LUMINANCE = UINT32_C(1),
  STROK_RENDERER_MODE_STRUCTURE = UINT32_C(2),
  STROK_RENDERER_MODE_HALFBLOCK = UINT32_C(3),
  STROK_RENDERER_MODE_BLOCKS = UINT32_C(4),
  STROK_RENDERER_MODE_OCTANT = UINT32_C(5),
  STROK_RENDERER_MODE_SEXTANT = UINT32_C(6),
  STROK_RENDERER_MODE_BRAILLE = UINT32_C(7),
};

typedef uint32_t StrokRendererStyle;
enum {
  STROK_RENDERER_STYLE_NONE = UINT32_C(0),
  STROK_RENDERER_STYLE_PAINTERLY = UINT32_C(1),
  STROK_RENDERER_STYLE_HATCH = UINT32_C(2),
  STROK_RENDERER_STYLE_STIPPLE = UINT32_C(3),
  STROK_RENDERER_STYLE_FLOW = UINT32_C(4),
  STROK_RENDERER_STYLE_CELL_SHADE = UINT32_C(5),
};

typedef uint32_t StrokStructureOverlay;
enum {
  STROK_STRUCTURE_OVERLAY_AUTO = UINT32_C(0),
  STROK_STRUCTURE_OVERLAY_ON = UINT32_C(1),
  STROK_STRUCTURE_OVERLAY_OFF = UINT32_C(2),
};

typedef uint32_t StrokGlyphFeatures;
enum {
  STROK_GLYPH_FEATURES_OVERLAP = UINT32_C(0),
  STROK_GLYPH_FEATURES_HOG = UINT32_C(1),
  STROK_GLYPH_FEATURES_SDF = UINT32_C(2),
};

enum {
  STROK_RENDERER_CONFIG_PRESENT_WIDTH = UINT32_C(1) << 0,
  STROK_RENDERER_CONFIG_PRESENT_HEIGHT = UINT32_C(1) << 1,
  STROK_RENDERER_CONFIG_PRESENT_FONT_PATH = UINT32_C(1) << 2,
  STROK_RENDERER_CONFIG_PRESENT_CHARSET = UINT32_C(1) << 3,
  STROK_RENDERER_CONFIG_PRESENT_EDGE_THRESHOLD = UINT32_C(1) << 4,
  STROK_RENDERER_CONFIG_PRESENT_EDGE_STRENGTH = UINT32_C(1) << 5,
  STROK_RENDERER_CONFIG_PRESENT_DOG_SIGMA = UINT32_C(1) << 6,
  STROK_RENDERER_CONFIG_PRESENT_DOG_SIGMA2 = UINT32_C(1) << 7,
  STROK_RENDERER_CONFIG_PRESENT_DOG_THRESHOLD = UINT32_C(1) << 8,
  STROK_RENDERER_CONFIG_PRESENT_ETF_ITERS = UINT32_C(1) << 9,
  STROK_RENDERER_CONFIG_PRESENT_LIC_LENGTH = UINT32_C(1) << 10,
  STROK_RENDERER_CONFIG_PRESENT_POSTERIZE = UINT32_C(1) << 11,
  STROK_RENDERER_CONFIG_PRESENT_CONTRAST = UINT32_C(1) << 12,
  STROK_RENDERER_CONFIG_PRESENT_GLYPH_STICKINESS = UINT32_C(1) << 13,
  STROK_RENDERER_CONFIG_PRESENT_ORIENT_STICKINESS = UINT32_C(1) << 14,
};

enum {
  STROK_RENDERER_CONFIG_FLAG_RAMP_SORT = UINT32_C(1) << 0,
  STROK_RENDERER_CONFIG_FLAG_FIT = UINT32_C(1) << 1,
  STROK_RENDERER_CONFIG_FLAG_GPU = UINT32_C(1) << 2,
  STROK_RENDERER_CONFIG_FLAG_LINE_LIGATURES = UINT32_C(1) << 3,
};

/*
 * A borrowed C representation of RendererConfig. version must use the current
 * ABI major and struct_size must be at least sizeof(StrokRendererConfig).
 * Optional scalar and string fields are selected by presence; strings and graph
 * pass entries must be non-null, NUL-terminated strings for the duration
 * of the conversion call. Future ABI fields are appended after graph_pass_count.
 */
typedef struct StrokRendererConfig {
  uint32_t version;
  uint32_t struct_size;
  uint32_t presence;
  uint32_t flags;
  int32_t width;
  int32_t height;
  double cell_aspect;
  StrokRendererMode mode;
  StrokRendererStyle style;
  StrokStructureOverlay structure_overlay;
  StrokGlyphFeatures glyph_features;
  const char* font_path;
  const char* charset;
  double edge_threshold;
  double edge_strength;
  double dog_sigma;
  double dog_sigma2;
  double dog_threshold;
  int32_t etf_iters;
  int32_t lic_length;
  int32_t posterize;
  double contrast;
  double glyph_stickiness;
  double orient_stickiness;
  int32_t temporal_supersample;
  const char* const* graph_passes;
  uint32_t graph_pass_count;
} StrokRendererConfig;

/* A caller-owned C representation of RenderGrid. Zero dimensions are initialized
 * deliberately and must be set to positive values before renderer creation. */
typedef struct StrokRenderGrid {
  uint32_t version;
  uint32_t struct_size;
  int32_t cols;
  int32_t rows;
} StrokRenderGrid;

STROK_C_API void STROK_C_CALL strok_renderer_config_init(StrokRendererConfig* config);
STROK_C_API void STROK_C_CALL strok_render_grid_init(StrokRenderGrid* grid);

typedef uint32_t StrokColorPixelFormat;
enum {
  STROK_COLOR_PIXEL_FORMAT_RGB24 = UINT32_C(0),
  STROK_COLOR_PIXEL_FORMAT_RGBA8 = UINT32_C(1),
  STROK_COLOR_PIXEL_FORMAT_BGRA8 = UINT32_C(2),
};

/* A borrowed read-only color image. data must remain valid and unchanged for the
 * complete strok_renderer_render_color call. row_stride_bytes is the distance
 * between row starts and may include padding. RGBA8 and BGRA8 ignore alpha. */
typedef struct StrokColorImageView {
  uint32_t version;
  uint32_t struct_size;
  const uint8_t* data;
  int32_t width;
  int32_t height;
  uint64_t row_stride_bytes;
  StrokColorPixelFormat pixel_format;
} StrokColorImageView;

STROK_C_API void STROK_C_CALL strok_color_image_view_init(StrokColorImageView* image);

typedef uint32_t StrokDepthPixelFormat;
enum { STROK_DEPTH_PIXEL_FORMAT_FLOAT64 = UINT32_C(0) };
typedef uint32_t StrokDepthInterpretation;
enum { STROK_DEPTH_INTERPRETATION_CAMERA_LINEAR = UINT32_C(0) };

typedef struct StrokDepthImageView {
  uint32_t version;
  uint32_t struct_size;
  const double* data;
  int32_t width;
  int32_t height;
  uint64_t row_stride_bytes;
  StrokDepthPixelFormat pixel_format;
  StrokDepthInterpretation interpretation;
} StrokDepthImageView;

typedef uint32_t StrokNormalPixelFormat;
enum { STROK_NORMAL_PIXEL_FORMAT_FLOAT64X3 = UINT32_C(0) };
typedef uint32_t StrokNormalSpace;
enum { STROK_NORMAL_SPACE_VIEW = UINT32_C(0) };

typedef struct StrokNormalImageView {
  uint32_t version;
  uint32_t struct_size;
  const double* data;
  int32_t width;
  int32_t height;
  uint64_t row_stride_bytes;
  StrokNormalPixelFormat pixel_format;
  StrokNormalSpace space;
} StrokNormalImageView;

/* A borrowed rich CPU input. color is required; depth and normals are optional.
 * All nested views and their data remain valid and unchanged only for the render call. */
typedef struct StrokRenderInput {
  uint32_t version;
  uint32_t struct_size;
  const StrokColorImageView* color;
  const StrokDepthImageView* depth;
  const StrokNormalImageView* normals;
} StrokRenderInput;

STROK_C_API void STROK_C_CALL strok_depth_image_view_init(StrokDepthImageView* image);
STROK_C_API void STROK_C_CALL strok_normal_image_view_init(StrokNormalImageView* image);
STROK_C_API void STROK_C_CALL strok_render_input_init(StrokRenderInput* input);

typedef struct StrokRenderer StrokRenderer;

typedef uint32_t StrokStatus;
enum {
  STROK_STATUS_SUCCESS = UINT32_C(0),
  STROK_STATUS_BACKEND_FALLBACK = UINT32_C(1),
  STROK_STATUS_INVALID_ARGUMENT = UINT32_C(2),
  STROK_STATUS_INVALID_INPUT = UINT32_C(3),
  STROK_STATUS_INVALID_CONFIGURATION = UINT32_C(4),
  STROK_STATUS_INTERNAL_ERROR = UINT32_C(5),
};

/*
 * Creates a renderer that owns its C++ configuration, grid, temporal history, and
 * output storage. On failure, out_renderer is set to null and the thread-local
 * error message can be inspected with strok_last_error_message(). A handle is not
 * thread-safe; callers must synchronize all calls that share one handle.
 */
STROK_C_API StrokStatus STROK_C_CALL strok_renderer_create(const StrokRendererConfig* config,
                                                            const StrokRenderGrid* grid,
                                                            StrokRenderer** out_renderer);

/* Resets only renderer temporal state. A null handle returns STROK_STATUS_INVALID_ARGUMENT. */
STROK_C_API StrokStatus STROK_C_CALL strok_renderer_reset(StrokRenderer* renderer);

/* Renders one borrowed RGB24, RGBA8, or BGRA8 image. Invalid image headers,
 * formats, dimensions, or layouts return STROK_STATUS_INVALID_ARGUMENT and set
 * strok_last_error_message(); the renderer handle remains usable. */
STROK_C_API StrokStatus STROK_C_CALL strok_renderer_render_color(StrokRenderer* renderer,
                                                                   const StrokColorImageView* image);

/* Renders required borrowed color with optional borrowed depth and view-space normals.
 * Invalid nested views or incompatible auxiliary dimensions return STROK_STATUS_INVALID_ARGUMENT. */
STROK_C_API StrokStatus STROK_C_CALL strok_renderer_render_input(StrokRenderer* renderer,
                                                                   const StrokRenderInput* input);

/* Safe for null, failed, and never-rendered handles. This does not modify the caller's pointer. */
STROK_C_API void STROK_C_CALL strok_renderer_destroy(StrokRenderer* renderer);

/* Returns a library-owned, NUL-terminated message for the calling thread. The pointer
 * remains valid until the next non-query C ABI call on that thread and must not be freed. */
STROK_C_API const char* STROK_C_CALL strok_last_error_message(void);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* STROK_C_API_H */
