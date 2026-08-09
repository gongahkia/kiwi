#pragma once

#include "../include/strok/renderer_config.hpp"
#include "../include/strok/render_grid.hpp"
#include "../include/strok/render_result.hpp"

#include "cell_buffer.hpp"
#include "color_image_view.hpp"
#include "frame.hpp"
#include "glyph_shape.hpp"
#include "hysteresis.hpp"
#include "luminance.hpp"
#include "structure_sampling.hpp"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace strok {

struct SceneGBuffer;

struct RenderTemporalState {
  GlyphHysteresisState glyph_hysteresis;
  OrientationHysteresisState orientation_hysteresis;
  std::optional<LuminanceField> previous_luminance;
  std::optional<LuminanceField> previous_supersample_luminance;
  std::optional<Frame> next_supersample_frame;
  bool next_supersample_required = false;
  std::vector<CellLuminanceRegion> previous_shape_regions;

  void reset() {
    glyph_hysteresis.reset();
    orientation_hysteresis.reset();
    previous_luminance.reset();
    previous_supersample_luminance.reset();
    next_supersample_frame.reset();
    next_supersample_required = false;
    previous_shape_regions.clear();
  }
};

RenderResult renderFrame(const Frame& frame, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state = nullptr, const SceneGBuffer* scene_gbuffer = nullptr);
RenderResult renderFrame(const ColorImageView& image, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state = nullptr, const SceneGBuffer* scene_gbuffer = nullptr);
RenderResult validateRendererConfiguration(const RendererConfig& config, RenderGrid grid);
std::string dumpRenderGraph(const RendererConfig& config);

}  // namespace strok
