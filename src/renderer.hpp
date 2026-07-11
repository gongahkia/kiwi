#pragma once

#include "cell_buffer.hpp"
#include "cli.hpp"
#include "frame.hpp"
#include "glyph_shape.hpp"
#include "hysteresis.hpp"
#include "luminance.hpp"
#include "structure_sampling.hpp"
#include "terminal.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace strok {

struct SceneGBuffer;

struct RenderStats {
  int64_t frames = 0;
  int64_t cells = 0;
  int64_t render_ns = 0;
  int64_t shape_match_cells = 0;
  int64_t shape_match_ns = 0;
  int64_t optical_flow_blocks = 0;
  int64_t optical_flow_ns = 0;
  int64_t warp_history_cells = 0;
  int64_t warp_history_ns = 0;
  int64_t temporal_supersample_frames = 0;
  int64_t temporal_supersample_ns = 0;
};

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

void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats = nullptr, RenderTemporalState* temporal_state = nullptr, const SceneGBuffer* scene_gbuffer = nullptr);
std::string dumpRenderGraph(const CliOptions& options);

}  // namespace strok
