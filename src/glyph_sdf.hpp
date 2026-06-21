#pragma once

#include "glyph_shape.hpp"
#include "structure_sampling.hpp"

#include <span>
#include <string_view>
#include <vector>

namespace contourtty {

class GlyphFont;

struct SignedDistanceField {
  int width = 0;
  int height = 0;
  std::vector<double> values;
};

SignedDistanceField signedDistanceFieldForValues(std::span<const double> values, int width, int height);
std::vector<double> sdfVectorForValues(std::span<const double> values, int width, int height);
std::vector<double> sdfVectorForCell(const CellLuminanceRegion& region);
GlyphShapeTable buildSdfGlyphShapeTable(std::u32string_view glyphs, int cell_width, int cell_height);
GlyphShapeTable buildSdfGlyphShapeTable(const GlyphFont& font, std::u32string_view glyphs, int cell_width, int cell_height);

}  // namespace contourtty
