#pragma once

#include "cell_buffer.hpp"
#include "frame.hpp"

#include <array>

namespace contourtty {

char32_t blockGlyphForSamples(const std::array<double, 4>& samples);
void renderBlockSadFrame(const Frame& frame, int cols, int rows, CellBuffer* cells);

}  // namespace contourtty
