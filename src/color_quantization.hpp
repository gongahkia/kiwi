#pragma once

#include "luminance.hpp"

#include <cstdint>
#include <string>

namespace contourtty {

enum class DitherMode {
  None,
  Ordered,
  FloydSteinberg,
};

DitherMode ditherModeFromString(const std::string& value);
Rgb applyOrderedDither(Rgb color, int row, int col, int amplitude);
uint8_t quantizeXterm256(Rgb color);
uint8_t quantizeAnsi16(Rgb color);

}  // namespace contourtty
