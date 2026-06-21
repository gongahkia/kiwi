#include "lic.hpp"

#include "luminance.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <stdexcept>
#include <vector>

namespace contourtty {
namespace {

constexpr double kPi = 3.14159265358979323846;

uint32_t mix(uint32_t value) noexcept {
  value ^= value >> 16U;
  value *= 0x7FEB352DU;
  value ^= value >> 15U;
  value *= 0x846CA68BU;
  value ^= value >> 16U;
  return value;
}

double angularDistance(double a, double b) {
  double delta = std::fmod(std::abs(a - b), 2.0 * kPi);
  if (delta > kPi) {
    delta = 2.0 * kPi - delta;
  }
  return delta;
}

char32_t flowGlyphForGradient(const CellGradient& gradient) {
  struct Candidate {
    double angle;
    char32_t glyph;
  };
  const Candidate candidates[] = {
    Candidate{.angle = 0.0, .glyph = U'│'},
    Candidate{.angle = kPi, .glyph = U'│'},
    Candidate{.angle = -kPi, .glyph = U'│'},
    Candidate{.angle = kPi / 2.0, .glyph = U'─'},
    Candidate{.angle = -kPi / 2.0, .glyph = U'─'},
    Candidate{.angle = kPi / 4.0, .glyph = U'╱'},
    Candidate{.angle = -3.0 * kPi / 4.0, .glyph = U'╱'},
    Candidate{.angle = -kPi / 4.0, .glyph = U'╲'},
    Candidate{.angle = 3.0 * kPi / 4.0, .glyph = U'╲'},
  };

  const Candidate* best = &candidates[0];
  double best_distance = angularDistance(gradient.orientation, best->angle);
  for (const Candidate& candidate : candidates) {
    const double distance = angularDistance(gradient.orientation, candidate.angle);
    if (distance < best_distance) {
      best = &candidate;
      best_distance = distance;
    }
  }
  return best->glyph;
}

std::vector<CellGradient> makeCellGradients(const GradientField& gradients, int cols, int rows) {
  if (cols <= 0 || rows <= 0) {
    throw std::invalid_argument("cell grid dimensions must be positive");
  }
  if (gradients.width <= 0 || gradients.height <= 0 ||
      gradients.values.size() != static_cast<std::size_t>(gradients.width) * static_cast<std::size_t>(gradients.height)) {
    throw std::invalid_argument("invalid gradient field");
  }
  std::vector<CellGradient> cells;
  cells.reserve(static_cast<std::size_t>(cols) * static_cast<std::size_t>(rows));
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      cells.push_back(cellGradient(gradients, cols, rows, col, row));
    }
  }
  return cells;
}

const CellGradient& sampledCellGradient(const std::vector<CellGradient>& gradients, int cols, int rows, int col, int row) {
  const int x = std::clamp(col, 0, cols - 1);
  const int y = std::clamp(row, 0, rows - 1);
  return gradients[static_cast<std::size_t>(y) * static_cast<std::size_t>(cols) + static_cast<std::size_t>(x)];
}

double traceLicValue(const std::vector<CellGradient>& gradients, int cols, int rows, int col, int row, int length, uint32_t seed) {
  if (length <= 0) {
    throw std::invalid_argument("LIC length must be positive");
  }
  double sum = licNoiseSample(col, row, seed);
  int count = 1;
  for (int direction : {-1, 1}) {
    double x = static_cast<double>(col);
    double y = static_cast<double>(row);
    for (int step = 0; step < length; ++step) {
      const CellGradient& gradient = sampledCellGradient(gradients, cols, rows, static_cast<int>(std::lround(x)), static_cast<int>(std::lround(y)));
      if (gradient.magnitude <= 1.0e-9) {
        break;
      }
      const double scale = 1.0 / gradient.magnitude;
      const double tx = -gradient.gy * scale;
      const double ty = gradient.gx * scale;
      x += static_cast<double>(direction) * tx;
      y += static_cast<double>(direction) * ty;
      const int sample_col = std::clamp(static_cast<int>(std::lround(x)), 0, cols - 1);
      const int sample_row = std::clamp(static_cast<int>(std::lround(y)), 0, rows - 1);
      sum += licNoiseSample(sample_col, sample_row, seed);
      ++count;
    }
  }
  return sum / static_cast<double>(count);
}

}  // namespace

double licNoiseSample(int x, int y, uint32_t seed) noexcept {
  uint32_t value = seed ^ (static_cast<uint32_t>(x) * 0x9E3779B1U) ^ (static_cast<uint32_t>(y) * 0x85EBCA77U);
  value = mix(value);
  return static_cast<double>(value & 0x00FFFFFFU) / static_cast<double>(0x00FFFFFFU);
}

double licValueForCell(const GradientField& gradients, int cols, int rows, int col, int row, int length, uint32_t seed) {
  const std::vector<CellGradient> cell_gradients = makeCellGradients(gradients, cols, rows);
  return traceLicValue(cell_gradients, cols, rows, col, row, length, seed);
}

char32_t licGlyphForCell(const CellGradient& gradient, double threshold, double luminance, double lic_value) {
  if (threshold < 0.0) {
    throw std::invalid_argument("edge threshold must be non-negative");
  }
  const double shade = std::clamp(1.0 - luminance, 0.0, 1.0);
  const double ink = std::clamp(shade * 1.15 + 0.06, 0.0, 1.0);
  if (ink <= std::clamp(lic_value, 0.0, 1.0)) {
    return U' ';
  }
  if (gradient.magnitude <= threshold) {
    if (shade > 0.72) {
      return U'•';
    }
    if (shade > 0.48) {
      return U'∙';
    }
    return U'·';
  }
  return flowGlyphForGradient(gradient);
}

void applyLicFlow(CellBuffer* cells, const GradientField& gradients, int cols, int rows, int length, double threshold, uint32_t seed) {
  if (cells == nullptr) {
    throw std::invalid_argument("cells must not be null");
  }
  if (cols != cells->cols() || rows != cells->rows()) {
    throw std::invalid_argument("cell grid mismatch");
  }
  const std::vector<CellGradient> cell_gradients = makeCellGradients(gradients, cols, rows);
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      const std::size_t index = static_cast<std::size_t>(row) * static_cast<std::size_t>(cols) + static_cast<std::size_t>(col);
      Cell& cell = cells->at(col, row);
      const double value = traceLicValue(cell_gradients, cols, rows, col, row, length, seed);
      cell.glyph = licGlyphForCell(cell_gradients[index], threshold, relativeLuminance(cell.fg), value);
    }
  }
}

}  // namespace contourtty
