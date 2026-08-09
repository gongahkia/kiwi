#include "posterize.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <stdexcept>

namespace strok {
namespace {

double linearToSrgb(double value) noexcept {
  value = std::clamp(value, 0.0, 1.0);
  if (value <= 0.0031308) {
    return value * 12.92;
  }
  return 1.055 * std::pow(value, 1.0 / 2.4) - 0.055;
}

uint8_t channelFromLinear(double value) noexcept {
  return static_cast<uint8_t>(std::clamp(static_cast<int>(std::lround(linearToSrgb(value) * 255.0)), 0, 255));
}

void validateLevels(int levels) {
  if (levels < 2 || levels > 64) {
    throw std::invalid_argument("posterize levels must be in 2..64");
  }
}

void validateFrame(const Frame& frame) {
  if (frame.w <= 0 || frame.h <= 0 ||
      frame.rgb.size() != static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h) * 3U) {
    throw std::invalid_argument("invalid frame");
  }
}

double quantizeUnit(double value, int levels) noexcept {
  const double scale = static_cast<double>(levels - 1);
  return std::clamp(std::round(std::clamp(value, 0.0, 1.0) * scale) / scale, 0.0, 1.0);
}

}  // namespace

Oklab rgbToOklab(Rgb rgb) noexcept {
  const double r = srgbToLinear(rgb.r);
  const double g = srgbToLinear(rgb.g);
  const double b = srgbToLinear(rgb.b);

  const double l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
  const double m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
  const double s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

  const double l3 = std::cbrt(l);
  const double m3 = std::cbrt(m);
  const double s3 = std::cbrt(s);

  return Oklab{
    .l = 0.2104542553 * l3 + 0.7936177850 * m3 - 0.0040720468 * s3,
    .a = 1.9779984951 * l3 - 2.4285922050 * m3 + 0.4505937099 * s3,
    .b = 0.0259040371 * l3 + 0.7827717662 * m3 - 0.8086757660 * s3,
  };
}

Rgb oklabToRgb(Oklab color) noexcept {
  const double l3 = color.l + 0.3963377774 * color.a + 0.2158037573 * color.b;
  const double m3 = color.l - 0.1055613458 * color.a - 0.0638541728 * color.b;
  const double s3 = color.l - 0.0894841775 * color.a - 1.2914855480 * color.b;

  const double l = l3 * l3 * l3;
  const double m = m3 * m3 * m3;
  const double s = s3 * s3 * s3;

  return Rgb{
    .r = channelFromLinear(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    .g = channelFromLinear(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    .b = channelFromLinear(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
  };
}

Rgb posterizeOklab(Rgb rgb, int levels) {
  validateLevels(levels);
  Oklab color = rgbToOklab(rgb);
  color.l = quantizeUnit(color.l, levels);
  return oklabToRgb(color);
}

Frame posterizeFrameOklab(const Frame& frame, int levels) {
  validateLevels(levels);
  validateFrame(frame);
  Frame output = posterizeFrameOklab(colorImageViewFromValidFrame(frame), levels);
  output.pts_us = frame.pts_us;
  return output;
}

Frame posterizeFrameOklab(const ColorImageView& image, int levels) {
  validateLevels(levels);
  if (const std::optional<std::string> error = colorImageViewError(image); error.has_value()) {
    throw std::invalid_argument(*error);
  }
  Frame output;
  output.w = image.width;
  output.h = image.height;
  output.rgb.resize(static_cast<std::size_t>(image.width) * static_cast<std::size_t>(image.height) * 3U);
  for (int y = 0; y < image.height; ++y) {
    for (int x = 0; x < image.width; ++x) {
      const Rgb color = colorAt(image, x, y);
      const Rgb posterized = posterizeOklab(color, levels);
      const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(image.width) + static_cast<std::size_t>(x)) * 3U;
      output.rgb[index] = posterized.r;
      output.rgb[index + 1U] = posterized.g;
      output.rgb[index + 2U] = posterized.b;
    }
  }
  return output;
}

}  // namespace strok
