#include "raster_compose.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

contourtty::Rgb pixel(const contourtty::RasterImage& image, int x, int y) {
  const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(image.width) + static_cast<std::size_t>(x)) * 3U;
  return contourtty::Rgb{
    .r = image.rgb.at(index),
    .g = image.rgb.at(index + 1U),
    .b = image.rgb.at(index + 2U),
  };
}

bool same(contourtty::Rgb lhs, contourtty::Rgb rhs) {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

}  // namespace

int main() {
  contourtty::CellBuffer cells(1, 1);
  cells.at(0, 0) = contourtty::Cell{.glyph = U'█', .fg = contourtty::Rgb{.r = 200, .g = 10, .b = 20}, .bg = contourtty::Rgb{.r = 1, .g = 2, .b = 3}};
  const contourtty::RasterImage full = contourtty::rasterComposeCells(cells, contourtty::ColorMode::Truecolor, contourtty::DitherMode::None);
  expect(full.width == contourtty::kRasterCellPixelWidth && full.height == contourtty::kRasterCellPixelHeight, "raster dimensions");
  expect(full.rgb.size() == static_cast<std::size_t>(full.width) * static_cast<std::size_t>(full.height) * 3U, "raster byte count");
  expect(same(pixel(full, 0, 0), contourtty::Rgb{.r = 200, .g = 10, .b = 20}), "full block uses foreground");

  cells.at(0, 0).glyph = U'▀';
  const contourtty::RasterImage half = contourtty::rasterComposeCells(cells, contourtty::ColorMode::Truecolor, contourtty::DitherMode::None);
  expect(same(pixel(half, 0, 0), contourtty::Rgb{.r = 200, .g = 10, .b = 20}), "upper half uses foreground");
  expect(same(pixel(half, 0, contourtty::kRasterCellPixelHeight - 1), contourtty::Rgb{.r = 1, .g = 2, .b = 3}), "lower half uses background");

  cells.at(0, 0).glyph = U'█';
  const contourtty::RasterImage mono = contourtty::rasterComposeCells(cells, contourtty::ColorMode::Mono, contourtty::DitherMode::None);
  expect(same(pixel(mono, 0, 0), contourtty::Rgb{.r = 255, .g = 255, .b = 255}), "mono foreground is white");
}
