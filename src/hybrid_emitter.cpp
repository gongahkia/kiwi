#include "hybrid_emitter.hpp"

#include "ansi.hpp"
#include "color_dither.hpp"
#include "render_layout.hpp"

#include <optional>

namespace contourtty {
namespace {

bool sameColor(Rgb lhs, Rgb rhs) noexcept {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

Rgb ditherColor(Rgb color, int row, int col, EmissionOptions options) {
  if (options.dither_mode != DitherMode::Ordered || !supportsPaletteDither(options.color_mode)) {
    return color;
  }
  const int amplitude = options.color_mode == ColorMode::Color16 ? 32 : 16;
  return applyOrderedDither(color, row, col, amplitude);
}

void appendOverlayFg(std::string& out, Rgb color, int row, int col, EmissionOptions options) {
  color = ditherColor(color, row, col, options);
  switch (options.color_mode) {
    case ColorMode::Truecolor:
      appendSgrFg(out, color);
      return;
    case ColorMode::Color256:
      appendSgrFg256(out, quantizeXterm256(color));
      return;
    case ColorMode::Color16:
      appendSgrFg16(out, quantizeAnsi16(color));
      return;
    case ColorMode::Mono:
      return;
  }
}

}  // namespace

HybridFrameResult emitHybridFrame(const CellBuffer& cells, const HybridFrameOptions& options) {
  GraphicsFrameResult graphics = emitGraphicsFrame(cells, options.graphics);
  const RenderOrigin origin = centeredOrigin(RenderSize{.cols = cells.cols(), .rows = cells.rows()}, options.terminal);
  HybridFrameResult result{
    .bytes = std::move(graphics.bytes),
    .raster_bytes = graphics.raster_bytes,
  };
  std::optional<Rgb> active_fg;
  const bool color = options.text.color_mode != ColorMode::Mono;
  for (int row = 0; row < cells.rows(); ++row) {
    for (int col = 0; col < cells.cols(); ++col) {
      const Cell& cell = cells.at(col, row);
      if (cell.glyph == U' ') {
        continue;
      }
      appendCursorMove(result.bytes, origin.row + row, origin.col + col);
      if (color && (!active_fg.has_value() || !sameColor(*active_fg, cell.fg))) {
        appendOverlayFg(result.bytes, cell.fg, row, col, options.text);
        active_fg = cell.fg;
      }
      appendUtf8(result.bytes, cell.glyph);
      ++result.overlay_cells;
    }
  }
  if (result.overlay_cells > 0 && color) {
    appendSgrReset(result.bytes);
  }
  return result;
}

}  // namespace contourtty
