#pragma once

#include "cell_buffer.hpp"
#include "frame.hpp"

#include <array>
#include <cstdint>

namespace strok {

uint8_t octantMaskForSamples(const std::array<double, 8>& samples, double threshold = 0.5);
char32_t octantGlyphForMask(uint8_t mask);
void renderOctantFrame(const Frame& frame, int cols, int rows, CellBuffer* cells);

}  // namespace strok
