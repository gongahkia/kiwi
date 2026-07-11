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

strok::Rgb pixel(const strok::RasterImage& image, int x, int y) {
  const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(image.width) + static_cast<std::size_t>(x)) * 3U;
  return strok::Rgb{
    .r = image.rgb.at(index),
    .g = image.rgb.at(index + 1U),
    .b = image.rgb.at(index + 2U),
  };
}

bool same(strok::Rgb lhs, strok::Rgb rhs) {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

}  // namespace

int main() {
  strok::CellBuffer cells(1, 1);
  cells.at(0, 0) = strok::Cell{.glyph = U'█', .fg = strok::Rgb{.r = 200, .g = 10, .b = 20}, .bg = strok::Rgb{.r = 1, .g = 2, .b = 3}};
  const strok::RasterImage full = strok::rasterComposeCells(cells, strok::ColorMode::Truecolor, strok::DitherMode::None);
  expect(full.width == strok::kRasterCellPixelWidth && full.height == strok::kRasterCellPixelHeight, "raster dimensions");
  expect(full.rgb.size() == static_cast<std::size_t>(full.width) * static_cast<std::size_t>(full.height) * 3U, "raster byte count");
  expect(same(pixel(full, 0, 0), strok::Rgb{.r = 200, .g = 10, .b = 20}), "full block uses foreground");

  cells.at(0, 0).glyph = U'▀';
  const strok::RasterImage half = strok::rasterComposeCells(cells, strok::ColorMode::Truecolor, strok::DitherMode::None);
  expect(same(pixel(half, 0, 0), strok::Rgb{.r = 200, .g = 10, .b = 20}), "upper half uses foreground");
  expect(same(pixel(half, 0, strok::kRasterCellPixelHeight - 1), strok::Rgb{.r = 1, .g = 2, .b = 3}), "lower half uses background");

  cells.at(0, 0).glyph = U'█';
  const strok::RasterImage mono = strok::rasterComposeCells(cells, strok::ColorMode::Mono, strok::DitherMode::None);
  expect(same(pixel(mono, 0, 0), strok::Rgb{.r = 255, .g = 255, .b = 255}), "mono foreground is white");
}
