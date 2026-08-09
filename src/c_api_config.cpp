#include "c_api_config.hpp"

#include "renderer.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>

namespace strok {
namespace {

constexpr uint32_t kKnownPresence =
    STROK_RENDERER_CONFIG_PRESENT_WIDTH |
    STROK_RENDERER_CONFIG_PRESENT_HEIGHT |
    STROK_RENDERER_CONFIG_PRESENT_FONT_PATH |
    STROK_RENDERER_CONFIG_PRESENT_CHARSET |
    STROK_RENDERER_CONFIG_PRESENT_EDGE_THRESHOLD |
    STROK_RENDERER_CONFIG_PRESENT_EDGE_STRENGTH |
    STROK_RENDERER_CONFIG_PRESENT_DOG_SIGMA |
    STROK_RENDERER_CONFIG_PRESENT_DOG_SIGMA2 |
    STROK_RENDERER_CONFIG_PRESENT_DOG_THRESHOLD |
    STROK_RENDERER_CONFIG_PRESENT_ETF_ITERS |
    STROK_RENDERER_CONFIG_PRESENT_LIC_LENGTH |
    STROK_RENDERER_CONFIG_PRESENT_POSTERIZE |
    STROK_RENDERER_CONFIG_PRESENT_CONTRAST |
    STROK_RENDERER_CONFIG_PRESENT_GLYPH_STICKINESS |
    STROK_RENDERER_CONFIG_PRESENT_ORIENT_STICKINESS;

constexpr uint32_t kKnownFlags =
    STROK_RENDERER_CONFIG_FLAG_RAMP_SORT |
    STROK_RENDERER_CONFIG_FLAG_FIT |
    STROK_RENDERER_CONFIG_FLAG_GPU |
    STROK_RENDERER_CONFIG_FLAG_LINE_LIGATURES;

void setError(std::string* error, const char* message) {
  if (error != nullptr) {
    *error = message;
  }
}

bool hasCompatibleHeader(uint32_t version, uint32_t struct_size, std::size_t known_size, std::string* error) {
  if ((version >> 16U) != STROK_C_ABI_VERSION_MAJOR) {
    setError(error, "unsupported C ABI major version");
    return false;
  }
  if (struct_size < known_size) {
    setError(error, "C ABI structure is smaller than the required layout");
    return false;
  }
  return true;
}

std::optional<std::string> modeFromC(StrokRendererMode mode) {
  switch (mode) {
    case STROK_RENDERER_MODE_AUTO:
      return "auto";
    case STROK_RENDERER_MODE_LUMINANCE:
      return "luminance";
    case STROK_RENDERER_MODE_STRUCTURE:
      return "structure";
    case STROK_RENDERER_MODE_HALFBLOCK:
      return "halfblock";
    case STROK_RENDERER_MODE_BLOCKS:
      return "blocks";
    case STROK_RENDERER_MODE_OCTANT:
      return "octant";
    case STROK_RENDERER_MODE_SEXTANT:
      return "sextant";
    case STROK_RENDERER_MODE_BRAILLE:
      return "braille";
  }
  return std::nullopt;
}

std::optional<std::string> styleFromC(StrokRendererStyle style) {
  switch (style) {
    case STROK_RENDERER_STYLE_NONE:
      return "none";
    case STROK_RENDERER_STYLE_PAINTERLY:
      return "painterly";
    case STROK_RENDERER_STYLE_HATCH:
      return "hatch";
    case STROK_RENDERER_STYLE_STIPPLE:
      return "stipple";
    case STROK_RENDERER_STYLE_FLOW:
      return "flow";
    case STROK_RENDERER_STYLE_CELL_SHADE:
      return "cell-shade";
  }
  return std::nullopt;
}

std::optional<std::string> structureOverlayFromC(StrokStructureOverlay overlay) {
  switch (overlay) {
    case STROK_STRUCTURE_OVERLAY_AUTO:
      return "auto";
    case STROK_STRUCTURE_OVERLAY_ON:
      return "on";
    case STROK_STRUCTURE_OVERLAY_OFF:
      return "off";
  }
  return std::nullopt;
}

std::optional<std::string> glyphFeaturesFromC(StrokGlyphFeatures features) {
  switch (features) {
    case STROK_GLYPH_FEATURES_OVERLAP:
      return "overlap";
    case STROK_GLYPH_FEATURES_HOG:
      return "hog";
    case STROK_GLYPH_FEATURES_SDF:
      return "sdf";
  }
  return std::nullopt;
}

bool copyOptionalString(const char* value, const char* name, std::optional<std::string>* output, std::string* error) {
  if (value == nullptr) {
    setError(error, name);
    return false;
  }
  *output = value;
  return true;
}

}  // namespace

std::optional<RendererConfig> rendererConfigFromC(const StrokRendererConfig* config, std::string* error) {
  if (config == nullptr) {
    setError(error, "renderer configuration is required");
    return std::nullopt;
  }
  if (!hasCompatibleHeader(config->version, config->struct_size, sizeof(*config), error)) {
    return std::nullopt;
  }
  if ((config->presence & ~kKnownPresence) != 0U || (config->flags & ~kKnownFlags) != 0U) {
    setError(error, "renderer configuration has unsupported flags");
    return std::nullopt;
  }
  if (config->graph_pass_count > 1024U || (config->graph_pass_count > 0U && config->graph_passes == nullptr)) {
    setError(error, "renderer graph pass list is invalid");
    return std::nullopt;
  }

  const std::optional<std::string> mode = modeFromC(config->mode);
  const std::optional<std::string> style = styleFromC(config->style);
  const std::optional<std::string> structure_overlay = structureOverlayFromC(config->structure_overlay);
  const std::optional<std::string> glyph_features = glyphFeaturesFromC(config->glyph_features);
  if (!mode.has_value() || !style.has_value() || !structure_overlay.has_value() || !glyph_features.has_value()) {
    setError(error, "renderer configuration has an unsupported enum value");
    return std::nullopt;
  }

  RendererConfig result{
    .cell_aspect = config->cell_aspect,
    .mode = *mode,
    .style = *style,
    .structure_overlay = *structure_overlay,
    .glyph_features = *glyph_features,
    .ramp_sort = (config->flags & STROK_RENDERER_CONFIG_FLAG_RAMP_SORT) != 0U,
    .temporal_supersample = config->temporal_supersample,
    .fit = (config->flags & STROK_RENDERER_CONFIG_FLAG_FIT) != 0U,
    .gpu = (config->flags & STROK_RENDERER_CONFIG_FLAG_GPU) != 0U,
    .line_ligatures = (config->flags & STROK_RENDERER_CONFIG_FLAG_LINE_LIGATURES) != 0U,
  };
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_WIDTH) != 0U) {
    result.width = config->width;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_HEIGHT) != 0U) {
    result.height = config->height;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_FONT_PATH) != 0U &&
      !copyOptionalString(config->font_path, "renderer font path is required", &result.font_path, error)) {
    return std::nullopt;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_CHARSET) != 0U &&
      !copyOptionalString(config->charset, "renderer charset is required", &result.charset, error)) {
    return std::nullopt;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_EDGE_THRESHOLD) != 0U) {
    result.edge_threshold = config->edge_threshold;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_EDGE_STRENGTH) != 0U) {
    result.edge_strength = config->edge_strength;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_DOG_SIGMA) != 0U) {
    result.dog_sigma = config->dog_sigma;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_DOG_SIGMA2) != 0U) {
    result.dog_sigma2 = config->dog_sigma2;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_DOG_THRESHOLD) != 0U) {
    result.dog_threshold = config->dog_threshold;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_ETF_ITERS) != 0U) {
    result.etf_iters = config->etf_iters;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_LIC_LENGTH) != 0U) {
    result.lic_length = config->lic_length;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_POSTERIZE) != 0U) {
    result.posterize = config->posterize;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_CONTRAST) != 0U) {
    result.contrast = config->contrast;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_GLYPH_STICKINESS) != 0U) {
    result.glyph_stickiness = config->glyph_stickiness;
  }
  if ((config->presence & STROK_RENDERER_CONFIG_PRESENT_ORIENT_STICKINESS) != 0U) {
    result.orient_stickiness = config->orient_stickiness;
  }
  result.graph_passes.reserve(config->graph_pass_count);
  for (uint32_t index = 0; index < config->graph_pass_count; ++index) {
    const char* pass = config->graph_passes[index];
    if (pass == nullptr) {
      setError(error, "renderer graph pass entry is required");
      return std::nullopt;
    }
    result.graph_passes.emplace_back(pass);
  }

  if (!validateRendererConfiguration(result, RenderGrid{.cols = 1, .rows = 1}).succeeded()) {
    setError(error, "renderer configuration values are invalid");
    return std::nullopt;
  }
  return result;
}

std::optional<RenderGrid> renderGridFromC(const StrokRenderGrid* grid, std::string* error) {
  if (grid == nullptr) {
    setError(error, "render grid is required");
    return std::nullopt;
  }
  if (!hasCompatibleHeader(grid->version, grid->struct_size, sizeof(*grid), error)) {
    return std::nullopt;
  }
  if (grid->cols <= 0 || grid->rows <= 0) {
    setError(error, "render grid dimensions must be positive");
    return std::nullopt;
  }
  return RenderGrid{.cols = grid->cols, .rows = grid->rows};
}

}  // namespace strok

extern "C" {

void STROK_C_CALL strok_renderer_config_init(StrokRendererConfig* config) {
  if (config == nullptr) {
    return;
  }
  *config = StrokRendererConfig{
    .version = STROK_C_ABI_VERSION,
    .struct_size = sizeof(StrokRendererConfig),
    .presence = 0U,
    .flags = 0U,
    .cell_aspect = 0.5,
    .mode = STROK_RENDERER_MODE_LUMINANCE,
    .style = STROK_RENDERER_STYLE_NONE,
    .structure_overlay = STROK_STRUCTURE_OVERLAY_AUTO,
    .glyph_features = STROK_GLYPH_FEATURES_OVERLAP,
    .temporal_supersample = 1,
  };
}

void STROK_C_CALL strok_render_grid_init(StrokRenderGrid* grid) {
  if (grid == nullptr) {
    return;
  }
  *grid = StrokRenderGrid{
    .version = STROK_C_ABI_VERSION,
    .struct_size = sizeof(StrokRenderGrid),
  };
}

}  // extern "C"
