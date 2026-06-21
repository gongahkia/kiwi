#pragma once

#include "diff_emitter.hpp"
#include "graphics_emitter.hpp"
#include "terminal.hpp"

#include <cstddef>
#include <string>

namespace contourtty {

struct HybridFrameOptions {
  GraphicsFrameOptions graphics;
  EmissionOptions text;
  TerminalSize terminal;
};

struct HybridFrameResult {
  std::string bytes;
  std::size_t raster_bytes = 0;
  std::size_t overlay_cells = 0;
};

HybridFrameResult emitHybridFrame(const CellBuffer& cells, const HybridFrameOptions& options);

}  // namespace contourtty
