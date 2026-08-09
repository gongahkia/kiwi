#pragma once

#include "../include/strok/color.hpp"

#include <span>

namespace strok {

double srgbToLinear(uint8_t value) noexcept;
double relativeLuminance(Rgb rgb) noexcept;
double cellLuminance(std::span<const Rgb> samples) noexcept;

}  // namespace strok
