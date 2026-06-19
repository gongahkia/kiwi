#include "structure_sampling.hpp"

#include "luminance.hpp"

#include <cstddef>
#include <stdexcept>

namespace contourtty {

double LuminanceField::at(int x, int y) const {
  if (x < 0 || y < 0 || x >= width || y >= height) {
    throw std::out_of_range("luminance field index out of range");
  }
  return values.at(static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x));
}

double CellLuminanceRegion::at(int x, int y) const {
  if (x < 0 || y < 0 || x >= width() || y >= height()) {
    throw std::out_of_range("cell luminance index out of range");
  }
  return values.at(static_cast<std::size_t>(y) * static_cast<std::size_t>(width()) + static_cast<std::size_t>(x));
}

LuminanceField makeLuminanceField(const Frame& frame) {
  if (frame.w <= 0 || frame.h <= 0) {
    throw std::invalid_argument("frame dimensions must be positive");
  }
  const std::size_t expected = static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h) * 3;
  if (frame.rgb.size() != expected) {
    throw std::invalid_argument("frame RGB data size does not match dimensions");
  }

  LuminanceField field;
  field.width = frame.w;
  field.height = frame.h;
  field.values.reserve(static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h));
  for (int y = 0; y < frame.h; ++y) {
    for (int x = 0; x < frame.w; ++x) {
      const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(x)) * 3;
      field.values.push_back(relativeLuminance(Rgb{
        .r = frame.rgb[index],
        .g = frame.rgb[index + 1],
        .b = frame.rgb[index + 2],
      }));
    }
  }
  return field;
}

SourceRegion cellSourceRegion(int source_width, int source_height, int cols, int rows, int col, int row) {
  if (source_width <= 0 || source_height <= 0 || cols <= 0 || rows <= 0) {
    throw std::invalid_argument("source and grid dimensions must be positive");
  }
  if (col < 0 || row < 0 || col >= cols || row >= rows) {
    throw std::out_of_range("cell index out of range");
  }
  const int x0 = (col * source_width) / cols;
  const int x1 = ((col + 1) * source_width) / cols;
  const int y0 = (row * source_height) / rows;
  const int y1 = ((row + 1) * source_height) / rows;
  return SourceRegion{.x0 = x0, .x1 = x1, .y0 = y0, .y1 = y1};
}

CellLuminanceRegion sampleCellRegion(const LuminanceField& field, int cols, int rows, int col, int row) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }
  CellLuminanceRegion region;
  region.source = cellSourceRegion(field.width, field.height, cols, rows, col, row);
  region.values.reserve(static_cast<std::size_t>(region.width()) * static_cast<std::size_t>(region.height()));
  for (int y = region.source.y0; y < region.source.y1; ++y) {
    for (int x = region.source.x0; x < region.source.x1; ++x) {
      region.values.push_back(field.at(x, y));
    }
  }
  return region;
}

}  // namespace contourtty
