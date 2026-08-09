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
#include "render_input.hpp"
#include "render_graph.hpp"
#include "structure_sampling.hpp"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace strok {

struct RenderTemporalState {
  GlyphHysteresisState glyph_hysteresis;
  OrientationHysteresisState orientation_hysteresis;
  std::optional<LuminanceField> previous_luminance;
  std::optional<LuminanceField> previous_supersample_luminance;
  std::vector<CellLuminanceRegion> previous_shape_regions;
  std::optional<CellBuffer> previous_cells;

  void reset() {
    glyph_hysteresis.reset();
    orientation_hysteresis.reset();
    previous_luminance.reset();
    previous_supersample_luminance.reset();
    previous_shape_regions.clear();
    previous_cells.reset();
  }
};

RenderResult renderFrame(const Frame& frame, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state = nullptr);
RenderResult renderFrame(const ColorImageView& image, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state = nullptr);
RenderResult renderFrame(const RenderInput& input, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state = nullptr);
RenderResult renderFrame(const RenderInput& input, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state, const Graph* graph_topology);
RenderResult validateRendererConfiguration(const RendererConfig& config, RenderGrid grid);
Graph buildRendererGraphTopology(const RendererConfig& config);
std::string dumpRenderGraph(const RendererConfig& config);

}  // namespace strok
