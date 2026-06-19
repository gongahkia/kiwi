#include "structure_edges.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <optional>
#include <stdexcept>
#include <vector>

namespace contourtty {
namespace {

constexpr double kPi = 3.14159265358979323846;

double sampleClamped(const LuminanceField& field, int x, int y) {
  const int clamped_x = std::min(std::max(x, 0), field.width - 1);
  const int clamped_y = std::min(std::max(y, 0), field.height - 1);
  return field.at(clamped_x, clamped_y);
}

std::vector<double> gaussianKernel(double sigma) {
  if (sigma <= 0.0) {
    throw std::invalid_argument("gaussian sigma must be positive");
  }
  const int radius = std::max(1, static_cast<int>(std::ceil(sigma * 3.0)));
  std::vector<double> kernel;
  kernel.reserve(static_cast<std::size_t>(radius * 2 + 1));
  double sum = 0.0;
  for (int i = -radius; i <= radius; ++i) {
    const double value = std::exp(-(static_cast<double>(i * i)) / (2.0 * sigma * sigma));
    kernel.push_back(value);
    sum += value;
  }
  for (double& value : kernel) {
    value /= sum;
  }
  return kernel;
}

double angularDistance(double a, double b) {
  double delta = std::fmod(std::abs(a - b), 2.0 * kPi);
  if (delta > kPi) {
    delta = 2.0 * kPi - delta;
  }
  return delta;
}

bool isCornerLike(const CellGradient& gradient, double threshold) {
  const double min_energy = std::min(gradient.horizontal_energy, gradient.vertical_energy);
  const double max_energy = std::max(gradient.horizontal_energy, gradient.vertical_energy);
  if (min_energy <= threshold || max_energy <= 0.0) {
    return false;
  }
  return min_energy / max_energy >= 0.55 && gradient.magnitude < max_energy * 1.15;
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

LuminanceField gradientMagnitudeField(const GradientField& gradients, double threshold) {
  if (gradients.width <= 0 || gradients.height <= 0 ||
      gradients.values.size() != static_cast<std::size_t>(gradients.width) * static_cast<std::size_t>(gradients.height)) {
    throw std::invalid_argument("invalid gradient field");
  }
  if (threshold < 0.0) {
    throw std::invalid_argument("gradient magnitude threshold must be non-negative");
  }
  LuminanceField field;
  field.width = gradients.width;
  field.height = gradients.height;
  field.values.reserve(gradients.values.size());
  for (const Gradient gradient : gradients.values) {
    const double magnitude = std::hypot(gradient.gx, gradient.gy);
    field.values.push_back(magnitude > threshold ? magnitude : 0.0);
  }
  return field;
}

LuminanceField gaussianBlur(const LuminanceField& field, double sigma) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }
  const std::vector<double> kernel = gaussianKernel(sigma);
  const int radius = static_cast<int>(kernel.size() / 2);

  LuminanceField horizontal;
  horizontal.width = field.width;
  horizontal.height = field.height;
  horizontal.values.assign(field.values.size(), 0.0);
  for (int y = 0; y < field.height; ++y) {
    for (int x = 0; x < field.width; ++x) {
      double sum = 0.0;
      for (int k = -radius; k <= radius; ++k) {
        sum += sampleClamped(field, x + k, y) * kernel[static_cast<std::size_t>(k + radius)];
      }
      horizontal.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(field.width) + static_cast<std::size_t>(x)] = sum;
    }
  }

  LuminanceField output;
  output.width = field.width;
  output.height = field.height;
  output.values.assign(field.values.size(), 0.0);
  for (int y = 0; y < field.height; ++y) {
    for (int x = 0; x < field.width; ++x) {
      double sum = 0.0;
      for (int k = -radius; k <= radius; ++k) {
        sum += sampleClamped(horizontal, x, y + k) * kernel[static_cast<std::size_t>(k + radius)];
      }
      output.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(field.width) + static_cast<std::size_t>(x)] = sum;
    }
  }
  return output;
}

LuminanceField differenceOfGaussians(const LuminanceField& field, DogOptions options) {
  if (!options.enabled()) {
    return field;
  }
  if (options.threshold < 0.0) {
    throw std::invalid_argument("DoG threshold must be non-negative");
  }
  const LuminanceField narrow = gaussianBlur(field, options.sigma1);
  const LuminanceField wide = gaussianBlur(field, options.sigma2);

  LuminanceField output;
  output.width = field.width;
  output.height = field.height;
  output.values.reserve(field.values.size());
  for (std::size_t i = 0; i < field.values.size(); ++i) {
    const double value = std::abs(narrow.values[i] - wide.values[i]);
    output.values.push_back(value >= options.threshold ? value : 0.0);
  }
  return output;
}

CellGradient cellGradient(const GradientField& gradients, int cols, int rows, int col, int row) {
  if (gradients.width <= 0 || gradients.height <= 0 ||
      gradients.values.size() != static_cast<std::size_t>(gradients.width) * static_cast<std::size_t>(gradients.height)) {
    throw std::invalid_argument("invalid gradient field");
  }
  const SourceRegion region = cellSourceRegion(gradients.width, gradients.height, cols, rows, col, row);
  double gx = 0.0;
  double gy = 0.0;
  double horizontal_energy = 0.0;
  double vertical_energy = 0.0;
  int count = 0;
  for (int y = region.y0; y < region.y1; ++y) {
    for (int x = region.x0; x < region.x1; ++x) {
      const Gradient gradient = gradients.at(x, y);
      gx += gradient.gx;
      gy += gradient.gy;
      horizontal_energy += std::abs(gradient.gx);
      vertical_energy += std::abs(gradient.gy);
      ++count;
    }
  }
  if (count > 0) {
    const double scale = 1.0 / static_cast<double>(count);
    gx *= scale;
    gy *= scale;
    horizontal_energy *= scale;
    vertical_energy *= scale;
  }
  return CellGradient{
    .gx = gx,
    .gy = gy,
    .magnitude = std::hypot(gx, gy),
    .orientation = std::atan2(gy, gx),
    .horizontal_energy = horizontal_energy,
    .vertical_energy = vertical_energy,
  };
}

std::optional<char32_t> directionalGlyphForGradient(const CellGradient& gradient, double threshold) {
  if (threshold < 0.0) {
    throw std::invalid_argument("edge threshold must be non-negative");
  }
  if (gradient.magnitude <= threshold) {
    return std::nullopt;
  }
  if (isCornerLike(gradient, threshold)) {
    return U'+';
  }

  struct Candidate {
    double angle;
    char32_t glyph;
  };
  const Candidate candidates[] = {
    Candidate{.angle = 0.0, .glyph = U'|'},
    Candidate{.angle = kPi, .glyph = U'|'},
    Candidate{.angle = -kPi, .glyph = U'|'},
    Candidate{.angle = kPi / 2.0, .glyph = gradient.gy >= 0.0 ? U'_' : U'-'},
    Candidate{.angle = -kPi / 2.0, .glyph = U'-'},
    Candidate{.angle = kPi / 4.0, .glyph = U'/'},
    Candidate{.angle = -3.0 * kPi / 4.0, .glyph = U'/'},
    Candidate{.angle = -kPi / 4.0, .glyph = U'\\'},
    Candidate{.angle = 3.0 * kPi / 4.0, .glyph = U'\\'},
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

}  // namespace contourtty
