#pragma once

#include "optical_flow.hpp"

#include <span>
#include <vector>

namespace contourtty {

std::vector<char32_t> warpGlyphHistory(std::span<const char32_t> previous_glyphs, int cols, int rows, const FlowField& flow);

}  // namespace contourtty
