#pragma once

#include "cell_buffer.hpp"
#include "color_dither.hpp"
#include "color_mode.hpp"
#include "glyph_font.hpp"
#include "render_mode.hpp"

#include <cstddef>
#include <cstdint>
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

GraphicsFrameResult emitGraphicsFrame(const CellBuffer& cells, const GraphicsFrameOptions& options);

}  // namespace contourtty
