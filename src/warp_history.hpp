#pragma once

#include "optical_flow.hpp"
#include "structure_sampling.hpp"

#include <span>
#include <vector>

namespace contourtty {

std::vector<char32_t> warpGlyphHistory(std::span<const char32_t> previous_glyphs, int cols, int rows, const FlowField& flow);
std::vector<CellLuminanceRegion> warpCellShapeHistory(std::span<const CellLuminanceRegion> previous_shapes, int cols, int rows, const FlowField& flow);

}  // namespace contourtty
