#include "structure_edges.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <stdexcept>

namespace contourtty {
namespace {

double sampleClamped(const LuminanceField& field, int x, int y) {
  const int clamped_x = std::min(std::max(x, 0), field.width - 1);
  const int clamped_y = std::min(std::max(y, 0), field.height - 1);
  return field.at(clamped_x, clamped_y);
}

}  // namespace

Gradient GradientField::at(int x, int y) const {
  if (x < 0 || y < 0 || x >= width || y >= height) {
    throw std::out_of_range("gradient field index out of range");
  }
  return values.at(static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x));
}

GradientField computeSobelGradients(const LuminanceField& field) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }

  GradientField gradients;
  gradients.width = field.width;
  gradients.height = field.height;
  gradients.values.reserve(static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height));
  for (int y = 0; y < field.height; ++y) {
    for (int x = 0; x < field.width; ++x) {
      const double gx =
        -sampleClamped(field, x - 1, y - 1) + sampleClamped(field, x + 1, y - 1) -
        2.0 * sampleClamped(field, x - 1, y) + 2.0 * sampleClamped(field, x + 1, y) -
        sampleClamped(field, x - 1, y + 1) + sampleClamped(field, x + 1, y + 1);
      const double gy =
        -sampleClamped(field, x - 1, y - 1) - 2.0 * sampleClamped(field, x, y - 1) - sampleClamped(field, x + 1, y - 1) +
        sampleClamped(field, x - 1, y + 1) + 2.0 * sampleClamped(field, x, y + 1) + sampleClamped(field, x + 1, y + 1);
      gradients.values.push_back(Gradient{.gx = gx, .gy = gy});
    }
  }
  return gradients;
}

CellGradient cellGradient(const GradientField& gradients, int cols, int rows, int col, int row) {
  if (gradients.width <= 0 || gradients.height <= 0 ||
      gradients.values.size() != static_cast<std::size_t>(gradients.width) * static_cast<std::size_t>(gradients.height)) {
    throw std::invalid_argument("invalid gradient field");
  }
  const SourceRegion region = cellSourceRegion(gradients.width, gradients.height, cols, rows, col, row);
  double gx = 0.0;
  double gy = 0.0;
  int count = 0;
  for (int y = region.y0; y < region.y1; ++y) {
    for (int x = region.x0; x < region.x1; ++x) {
      const Gradient gradient = gradients.at(x, y);
      gx += gradient.gx;
      gy += gradient.gy;
      ++count;
    }
  }
  if (count > 0) {
    gx /= static_cast<double>(count);
    gy /= static_cast<double>(count);
  }
  return CellGradient{
    .gx = gx,
    .gy = gy,
    .magnitude = std::hypot(gx, gy),
    .orientation = std::atan2(gy, gx),
  };
}

}  // namespace contourtty
