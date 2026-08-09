#pragma once

#include "cell_buffer.hpp"
#include "color_image_view.hpp"
#include "frame.hpp"

namespace strok {

void renderBrailleFrame(const Frame& frame, int cols, int rows, CellBuffer* cells);
void renderBrailleFrame(const ColorImageView& image, int cols, int rows, CellBuffer* cells);

}  // namespace strok
