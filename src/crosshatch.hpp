#pragma once

#include "cell_buffer.hpp"
#include "structure_edges.hpp"

namespace contourtty {

char32_t crosshatchGlyphForCell(const CellGradient& gradient, double threshold, double luminance, int col, int row);
void applyCrosshatch(CellBuffer* cells, const GradientField& gradients, int cols, int rows, double threshold);

}  // namespace contourtty
