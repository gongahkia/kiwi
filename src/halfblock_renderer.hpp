#pragma once

#include "cell_buffer.hpp"
#include "frame.hpp"

namespace strok {

void renderHalfBlockFrame(const Frame& frame, int cols, int rows, CellBuffer* cells);

}  // namespace strok
