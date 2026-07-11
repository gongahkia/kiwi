#pragma once

#include "cell_buffer.hpp"
#include "frame.hpp"

#include <array>
#include <cstdint>

namespace strok {

uint8_t sextantMaskForSamples(const std::array<double, 6>& samples, double threshold = 0.5);
char32_t sextantGlyphForMask(uint8_t mask);
void renderSextantFrame(const Frame& frame, int cols, int rows, CellBuffer* cells);

}  // namespace strok
