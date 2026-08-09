#pragma once

#include "../include/strok/raster.hpp"

#include "luminance.hpp"

#include <cstdint>
#include <string>

namespace strok {

DitherMode ditherModeFromString(const std::string& value);
Rgb applyOrderedDither(Rgb color, int row, int col, int amplitude);
uint8_t quantizeXterm256(Rgb color);
uint8_t quantizeAnsi16(Rgb color);
Rgb xterm256Color(uint8_t index);
Rgb ansi16Color(uint8_t index);

}  // namespace strok
