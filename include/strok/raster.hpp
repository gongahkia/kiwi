#pragma once

#include "cell_buffer.hpp"

#include <cstdint>
#include <vector>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
enum class ColorMode {
  Truecolor,
  Color256,
  Color16,
  Mono,
};

enum class DitherMode {
  None,
  Ordered,
  FloydSteinberg,
};

class GlyphFont;

constexpr int kRasterCellPixelWidth = 8;
constexpr int kRasterCellPixelHeight = 12;

struct RasterImage {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> rgb;
};

// Composes terminal-independent cells into an owning RGB24 image. glyph_font is
// optional; a null value uses the built-in glyph patterns.
RasterImage rasterComposeCells(const CellBuffer& cells,
                               ColorMode color_mode,
                               DitherMode dither_mode,
                               const GlyphFont* glyph_font = nullptr);

}  // namespace strok
