#pragma once

#include "cell_buffer.hpp"
#include "frame.hpp"

namespace contourtty {

void renderHalfBlockFrame(const Frame& frame, int cols, int rows, CellBuffer* cells);

}  // namespace contourtty
