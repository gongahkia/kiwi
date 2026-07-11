#pragma once

#include "cell_buffer.hpp"
#include "color_dither.hpp"
#include "color_mode.hpp"
#include "glyph_font.hpp"

#include <cstdint>
#include <vector>

namespace strok {

constexpr int kRasterCellPixelWidth = 8;
constexpr int kRasterCellPixelHeight = 12;

struct RasterImage {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> rgb;
};

RasterImage rasterComposeCells(const CellBuffer& cells, ColorMode color_mode, DitherMode dither_mode, const GlyphFont* glyph_font = nullptr);

}  // namespace strok
