#pragma once

#include "frame.hpp"
#include "luminance.hpp"

namespace strok {

Rgb averageRegion(const Frame& frame, int cols, int rows, int col, int row);
void mirrorFrameHorizontally(Frame& frame);

}  // namespace strok
