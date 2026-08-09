#pragma once

#include "raster.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
enum class GraphicsProtocol {
  None,
  Kitty,
  Sixel,
  ITermInline,
};

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

// Stores only protocol upload state for one presentation stream. It is owned by
// the presentation caller and has no connection to Renderer state.
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

// Requires the optional strok_graphics_backend target. The result owns the
// protocol bytes; state is optional and enables retained protocol uploads.
GraphicsFrameResult emitGraphicsFrame(const CellBuffer& cells, const GraphicsFrameOptions& options);
GraphicsFrameResult emitGraphicsFrame(const CellBuffer& cells, const GraphicsFrameOptions& options, GraphicsFrameState* state);

}  // namespace strok
