#include "luminance.hpp"

#include <cmath>

namespace strok {

double srgbToLinear(uint8_t value) noexcept {
  const double channel = static_cast<double>(value) / 255.0;
  if (channel <= 0.04045) {
    return channel / 12.92;
  }
  return std::pow((channel + 0.055) / 1.055, 2.4);
}

double relativeLuminance(Rgb rgb) noexcept {
  const double r = srgbToLinear(rgb.r);
  const double g = srgbToLinear(rgb.g);
  const double b = srgbToLinear(rgb.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double cellLuminance(std::span<const Rgb> samples) noexcept {
  if (samples.empty()) {
    return 0.0;
  }
  double r = 0.0;
  double g = 0.0;
  double b = 0.0;
  for (const Rgb sample : samples) {
    r += static_cast<double>(sample.r);
    g += static_cast<double>(sample.g);
    b += static_cast<double>(sample.b);
  }
  const double scale = 1.0 / static_cast<double>(samples.size());
  return relativeLuminance(Rgb{
    .r = static_cast<uint8_t>(std::lround(r * scale)),
    .g = static_cast<uint8_t>(std::lround(g * scale)),
    .b = static_cast<uint8_t>(std::lround(b * scale)),
  });
}

}  // namespace strok
