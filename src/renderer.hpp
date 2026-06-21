#pragma once

#include "cell_buffer.hpp"
#include "cli.hpp"
#include "frame.hpp"
#include "glyph_shape.hpp"
#include "hysteresis.hpp"
#include "luminance.hpp"
#include "terminal.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace contourtty {

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
};

struct RenderTemporalState {
  GlyphHysteresisState glyph_hysteresis;
  OrientationHysteresisState orientation_hysteresis;
  std::optional<LuminanceField> previous_luminance;

  void reset() {
    glyph_hysteresis.reset();
    orientation_hysteresis.reset();
    previous_luminance.reset();
  }
};

void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats = nullptr, RenderTemporalState* temporal_state = nullptr, const SceneGBuffer* scene_gbuffer = nullptr);
std::string dumpRenderGraph(const CliOptions& options);

}  // namespace contourtty
