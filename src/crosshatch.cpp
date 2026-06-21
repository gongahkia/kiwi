#include "crosshatch.hpp"

#include "luminance.hpp"

#include <algorithm>
#include <cmath>
#include <optional>
#include <stdexcept>

namespace contourtty {
namespace {

constexpr double kPi = 3.14159265358979323846;

double angularDistance(double a, double b) {
  double delta = std::fmod(std::abs(a - b), 2.0 * kPi);
  if (delta > kPi) {
    delta = 2.0 * kPi - delta;
  }
  return delta;
}

char32_t glyphForOrientation(double orientation) {
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
  double best_distance = angularDistance(orientation, best->angle);
  for (const Candidate& candidate : candidates) {
    const double distance = angularDistance(orientation, candidate.angle);
    if (distance < best_distance) {
      best = &candidate;
      best_distance = distance;
    }
  }
  return best->glyph;
}

bool sparsePick(int col, int row, int modulus) {
  const unsigned hash = static_cast<unsigned>(col * 73856093) ^ static_cast<unsigned>(row * 19349663);
  return hash % static_cast<unsigned>(modulus) == 0U;
}

}  // namespace

char32_t crosshatchGlyphForCell(const CellGradient& gradient, double threshold, double luminance, int col, int row) {
  if (threshold < 0.0) {
    throw std::invalid_argument("edge threshold must be non-negative");
  }
  const double shade = std::clamp(1.0 - luminance, 0.0, 1.0);
  if (gradient.magnitude > threshold) {
    if (shade > 0.72) {
      return U'╳';
    }
    return glyphForOrientation(gradient.orientation);
  }
  if (shade > 0.78) {
    return U'╳';
  }
  if (shade > 0.58) {
    return (col + row) % 2 == 0 ? U'╱' : U'╲';
  }
  if (shade > 0.38 && sparsePick(col, row, 2)) {
    return row % 2 == 0 ? U'─' : U'│';
  }
  if (shade > 0.22 && sparsePick(col, row, 4)) {
    return U'·';
  }
  return U' ';
}

void applyCrosshatch(CellBuffer* cells, const GradientField& gradients, int cols, int rows, double threshold) {
  if (cells == nullptr) {
    throw std::invalid_argument("cells must not be null");
  }
  if (cols != cells->cols() || rows != cells->rows()) {
    throw std::invalid_argument("cell grid mismatch");
  }
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      Cell& cell = cells->at(col, row);
      const CellGradient gradient = cellGradient(gradients, cols, rows, col, row);
      cell.glyph = crosshatchGlyphForCell(gradient, threshold, relativeLuminance(cell.fg), col, row);
    }
  }
}

}  // namespace contourtty
