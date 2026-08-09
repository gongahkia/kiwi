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
#define STROK_C_ABI_VERSION_MINOR 0u
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

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* STROK_C_API_H */
