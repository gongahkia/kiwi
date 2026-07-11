#pragma once

#include <cstdint>
#include <span>

namespace strok {

struct Rgb {
  uint8_t r = 0;
  uint8_t g = 0;
  uint8_t b = 0;
};

double srgbToLinear(uint8_t value) noexcept;
double relativeLuminance(Rgb rgb) noexcept;
double cellLuminance(std::span<const Rgb> samples) noexcept;

}  // namespace strok
