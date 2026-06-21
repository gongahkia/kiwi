#pragma once

#include "cell_buffer.hpp"

#include <cstdint>

namespace contourtty {

uint8_t blueNoiseRank64(int x, int y);
char32_t stippleGlyphForLuminance(double luminance, uint8_t noise_rank);
void applyStipple(CellBuffer* cells);

}  // namespace contourtty
