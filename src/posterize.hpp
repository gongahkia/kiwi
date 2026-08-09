#pragma once

#include "color_image_view.hpp"
#include "frame.hpp"
#include "luminance.hpp"

namespace strok {

struct Oklab {
  double l = 0.0;
  double a = 0.0;
  double b = 0.0;
};

Oklab rgbToOklab(Rgb rgb) noexcept;
Rgb oklabToRgb(Oklab color) noexcept;
Rgb posterizeOklab(Rgb rgb, int levels);
Frame posterizeFrameOklab(const Frame& frame, int levels);
Frame posterizeFrameOklab(const ColorImageView& image, int levels);

}  // namespace strok
