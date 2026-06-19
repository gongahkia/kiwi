#pragma once

#include "cell_buffer.hpp"
#include "cli.hpp"
#include "frame.hpp"
#include "glyph_shape.hpp"
#include "terminal.hpp"

#include <cstdint>
#include <string_view>

namespace contourtty {

struct RenderStats {
  int64_t frames = 0;
  int64_t cells = 0;
  int64_t render_ns = 0;
  int64_t shape_match_cells = 0;
  int64_t shape_match_ns = 0;
};

void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats = nullptr);

}  // namespace contourtty
