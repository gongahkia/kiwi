#pragma once

#include "frame.hpp"
#include "luminance.hpp"

namespace contourtty {

Rgb averageRegion(const Frame& frame, int cols, int rows, int col, int row);
void mirrorFrameHorizontally(Frame& frame);

}  // namespace contourtty
