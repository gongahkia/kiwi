#include "raster_compose.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>

namespace contourtty {
namespace {

std::array<uint8_t, 7> asciiGlyphPattern(char32_t glyph) {
  switch (glyph) {
    case U' ':
      return {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000};
    case U'.':
      return {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b00100};
    case U':':
      return {0b00000, 0b00100, 0b00100, 0b00000, 0b00100, 0b00100, 0b00000};
    case U'-':
      return {0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000};
    case U'=':
      return {0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000};
    case U'+':
      return {0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000};
    case U'*':
      return {0b00000, 0b10101, 0b01110, 0b11111, 0b01110, 0b10101, 0b00000};
    case U'#':
      return {0b01010, 0b11111, 0b01010, 0b01010, 0b11111, 0b01010, 0b00000};
    case U'%':
      return {0b11001, 0b11010, 0b00100, 0b01000, 0b10110, 0b00110, 0b00000};
    case U'@':
      return {0b01110, 0b10001, 0b10111, 0b10101, 0b10111, 0b10000, 0b01110};
    case U'|':
    case U'│':
      return {0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100};
    case U'/':
      return {0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b00000, 0b00000};
    case U'\\':
      return {0b10000, 0b01000, 0b00100, 0b00010, 0b00001, 0b00000, 0b00000};
    case U'_':
      return {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b11111};
    case U'─':
      return {0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000};
    case U'┌':
      return {0b00000, 0b00000, 0b00111, 0b00100, 0b00100, 0b00100, 0b00100};
    case U'┐':
      return {0b00000, 0b00000, 0b11100, 0b00100, 0b00100, 0b00100, 0b00100};
    case U'└':
      return {0b00100, 0b00100, 0b00100, 0b00100, 0b00111, 0b00000, 0b00000};
    case U'┘':
      return {0b00100, 0b00100, 0b00100, 0b00100, 0b11100, 0b00000, 0b00000};
    case U'├':
      return {0b00100, 0b00100, 0b00111, 0b00100, 0b00100, 0b00100, 0b00100};
    case U'┤':
      return {0b00100, 0b00100, 0b11100, 0b00100, 0b00100, 0b00100, 0b00100};
    case U'┬':
      return {0b00000, 0b00000, 0b11111, 0b00100, 0b00100, 0b00100, 0b00100};
    case U'┴':
      return {0b00100, 0b00100, 0b00100, 0b00100, 0b11111, 0b00000, 0b00000};
    case U'┼':
      return {0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00100, 0b00100};
    case U'?':
      return {0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b00000, 0b00100};
    default:
      return asciiGlyphPattern(U'?');
  }
}

bool asciiGlyphPixel(const std::array<uint8_t, 7>& pattern, int x, int y) {
  if (x < 1 || x > 6 || y < 2 || y > 9) {
    return false;
  }
  const int source_x = (x - 1) * 5 / 6;
  const int source_y = (y - 2) * 7 / 8;
  return ((pattern[static_cast<std::size_t>(source_y)] >> (4 - source_x)) & 1U) != 0;
}

void writeRasterPixel(std::vector<uint8_t>* raster, int width, int x, int y, Rgb color) {
  const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)) * 3U;
  raster->at(index) = color.r;
  raster->at(index + 1U) = color.g;
  raster->at(index + 2U) = color.b;
}

bool brailleDotSet(char32_t glyph, int dot_col, int dot_row) {
  if (glyph < 0x2800U || glyph > 0x28ffU) {
    return false;
  }
  static constexpr uint8_t kBrailleBits[4][2] {
    {0x01, 0x08},
    {0x02, 0x10},
    {0x04, 0x20},
    {0x40, 0x80},
  };
  const uint8_t mask = static_cast<uint8_t>(glyph - 0x2800U);
  return (mask & kBrailleBits[dot_row][dot_col]) != 0;
}

bool brailleGlyphPixel(char32_t glyph, int x, int y) {
  static constexpr int kDotCentersX[2] {2, 5};
  static constexpr int kDotCentersY[4] {1, 4, 7, 10};
  for (int dot_row = 0; dot_row < 4; ++dot_row) {
    for (int dot_col = 0; dot_col < 2; ++dot_col) {
      if (!brailleDotSet(glyph, dot_col, dot_row)) {
        continue;
      }
      if (std::abs(x - kDotCentersX[dot_col]) <= 1 && std::abs(y - kDotCentersY[dot_row]) <= 1) {
        return true;
      }
    }
  }
  return false;
}

Rgb exportForegroundColor(const Cell& cell, ColorMode color_mode) {
  if (color_mode == ColorMode::Mono) {
    return Rgb{.r = 255, .g = 255, .b = 255};
  }
  return cell.fg;
}

Rgb exportBackgroundColor(const Cell& cell, ColorMode color_mode) {
  if (color_mode == ColorMode::Mono) {
    return Rgb{};
  }
  return cell.bg;
}

Rgb blendRgb(Rgb bg, Rgb fg, double alpha) {
  const double clamped = std::clamp(alpha, 0.0, 1.0);
  return Rgb{
    .r = static_cast<uint8_t>(std::lround(static_cast<double>(bg.r) + (static_cast<double>(fg.r) - static_cast<double>(bg.r)) * clamped)),
    .g = static_cast<uint8_t>(std::lround(static_cast<double>(bg.g) + (static_cast<double>(fg.g) - static_cast<double>(bg.g)) * clamped)),
    .b = static_cast<uint8_t>(std::lround(static_cast<double>(bg.b) + (static_cast<double>(fg.b) - static_cast<double>(bg.b)) * clamped)),
  };
}

bool isSpecialRasterGlyph(char32_t glyph) {
  return glyph == U'▀' || glyph == U'▄' || glyph == U'█' || (glyph >= 0x2800U && glyph <= 0x28ffU);
}

}  // namespace

RasterImage rasterComposeCells(const CellBuffer& cells, ColorMode color_mode, DitherMode dither_mode, const GlyphFont* glyph_font) {
  CellBuffer quantized;
  const CellBuffer* source = &cells;
  if (supportsPaletteDither(color_mode)) {
    quantized = applyPaletteDither(cells, color_mode, dither_mode);
    source = &quantized;
  }
  RasterImage image{
    .width = source->cols() * kRasterCellPixelWidth,
    .height = source->rows() * kRasterCellPixelHeight,
    .rgb = {},
  };
  image.rgb.assign(static_cast<std::size_t>(image.width) * static_cast<std::size_t>(image.height) * 3U, 0);
  for (int cell_row = 0; cell_row < source->rows(); ++cell_row) {
    for (int cell_col = 0; cell_col < source->cols(); ++cell_col) {
      const Cell& cell = source->at(cell_col, cell_row);
      const Rgb fg = exportForegroundColor(cell, color_mode);
      const Rgb bg = exportBackgroundColor(cell, color_mode);
      const auto pattern = asciiGlyphPattern(cell.glyph);
      const GlyphRaster* glyph_raster = nullptr;
      if (glyph_font != nullptr && !isSpecialRasterGlyph(cell.glyph)) {
        glyph_raster = &glyph_font->raster(cell.glyph, kRasterCellPixelWidth, kRasterCellPixelHeight);
      }
      for (int y = 0; y < kRasterCellPixelHeight; ++y) {
        for (int x = 0; x < kRasterCellPixelWidth; ++x) {
          Rgb color = bg;
          if (cell.glyph == U'▀') {
            color = y < kRasterCellPixelHeight / 2 ? fg : bg;
          } else if (cell.glyph == U'▄') {
            color = y < kRasterCellPixelHeight / 2 ? bg : fg;
          } else if (cell.glyph == U'█') {
            color = fg;
          } else if (cell.glyph >= 0x2800U && cell.glyph <= 0x28ffU) {
            color = brailleGlyphPixel(cell.glyph, x, y) ? fg : bg;
          } else if (glyph_raster != nullptr) {
            const double alpha = glyph_raster->alpha[static_cast<std::size_t>(y) * static_cast<std::size_t>(kRasterCellPixelWidth) + static_cast<std::size_t>(x)];
            color = blendRgb(bg, fg, alpha);
          } else if (asciiGlyphPixel(pattern, x, y)) {
            color = fg;
          }
          writeRasterPixel(&image.rgb, image.width, cell_col * kRasterCellPixelWidth + x, cell_row * kRasterCellPixelHeight + y, color);
        }
      }
    }
  }
  return image;
}

}  // namespace contourtty
