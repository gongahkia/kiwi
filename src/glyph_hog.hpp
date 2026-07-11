#pragma once

#include "glyph_shape.hpp"
#include "structure_sampling.hpp"

#include <cstddef>
#include <span>
#include <string_view>
#include <vector>

namespace strok {

class GlyphFont;

constexpr std::size_t kHogBlocksX = 2;
constexpr std::size_t kHogBlocksY = 2;
constexpr std::size_t kHogBins = 8;
constexpr std::size_t kHogFeatureCount = kHogBlocksX * kHogBlocksY * kHogBins;

std::vector<double> hogVectorForValues(std::span<const double> values, int width, int height);
std::vector<double> hogVectorForCell(const CellLuminanceRegion& region);
GlyphShapeTable buildHogGlyphShapeTable(std::u32string_view glyphs, int cell_width, int cell_height);
GlyphShapeTable buildHogGlyphShapeTable(const GlyphFont& font, std::u32string_view glyphs, int cell_width, int cell_height);

}  // namespace strok
