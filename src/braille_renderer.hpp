#pragma once

#include "cell_buffer.hpp"
#include "frame.hpp"

namespace contourtty {

void renderBrailleFrame(const Frame& frame, int cols, int rows, CellBuffer* cells);

}  // namespace contourtty
