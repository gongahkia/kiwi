#pragma once

#include "cell_buffer.hpp"
#include "optical_flow.hpp"
#include "structure_edges.hpp"

#include <cstdint>

namespace strok {

double licNoiseSample(int x, int y, uint32_t seed = 0) noexcept;
double licValueForCell(const GradientField& gradients, int cols, int rows, int col, int row, int length, uint32_t seed = 0);
char32_t licGlyphForCell(const CellGradient& gradient, double threshold, double luminance, double lic_value);
void applyLicFlow(CellBuffer* cells, const GradientField& gradients, int cols, int rows, int length, double threshold, uint32_t seed = 0);
void applyLicMotionFlow(CellBuffer* cells, const FlowField& flow, int cols, int rows, int length, double threshold, uint32_t seed = 0);

}  // namespace strok
