#pragma once

#include "frame.hpp"
#include "luminance.hpp"

namespace contourtty {

struct Oklab {
  double l = 0.0;
  double a = 0.0;
  double b = 0.0;
};

Oklab rgbToOklab(Rgb rgb) noexcept;
Rgb oklabToRgb(Oklab color) noexcept;
Rgb posterizeOklab(Rgb rgb, int levels);
Frame posterizeFrameOklab(const Frame& frame, int levels);

}  // namespace contourtty
