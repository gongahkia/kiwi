#pragma once

#include "cell_buffer.hpp"
#include "color_dither.hpp"
#include "color_mode.hpp"
#include "glyph_font.hpp"
#include "raster_compose.hpp"
#include "render_mode.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>

namespace contourtty {

struct GraphicsFrameOptions {
  GraphicsProtocol protocol = GraphicsProtocol::Kitty;
  ColorMode color_mode = ColorMode::Truecolor;
  DitherMode dither_mode = DitherMode::None;
  const GlyphFont* glyph_font = nullptr;
  uint32_t image_id = 1;
  uint32_t placement_id = 1;
};

struct GraphicsFrameResult {
  std::string bytes;
  std::size_t raster_bytes = 0;
};

struct GraphicsFrameState {
  GraphicsProtocol protocol = GraphicsProtocol::None;
  uint32_t image_id = 0;
  uint32_t placement_id = 0;
  int columns = 0;
  int rows = 0;
  std::optional<RasterImage> previous_raster;

  void reset() {
    protocol = GraphicsProtocol::None;
    image_id = 0;
    placement_id = 0;
    columns = 0;
    rows = 0;
    previous_raster.reset();
  }
};

GraphicsFrameResult emitGraphicsFrame(const CellBuffer& cells, const GraphicsFrameOptions& options);
GraphicsFrameResult emitGraphicsFrame(const CellBuffer& cells, const GraphicsFrameOptions& options, GraphicsFrameState* state);

}  // namespace contourtty
