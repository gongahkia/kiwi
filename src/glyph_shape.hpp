#pragma once

#include <cstddef>
#include <string_view>
#include <vector>

namespace contourtty {

constexpr std::u32string_view kDefaultShapeGlyphs = U" .:-=+*#%@|/_\\";
constexpr std::size_t kShapeRegionCount = 9;

enum class ShapeRegion : std::size_t {
  Center = 0,
  Top,
  Bottom,
  Left,
  Right,
  TopLeft,
  TopRight,
  BottomLeft,
  BottomRight,
};

struct GlyphShapeVector {
  char32_t glyph = U' ';
  std::vector<double> features;
};

struct GlyphShapeTable {
  int cell_width = 0;
  int cell_height = 0;
  std::vector<GlyphShapeVector> entries;
};

std::vector<double> renderPrecomputedGlyphBitmap(char32_t glyph, int cell_width, int cell_height);
GlyphShapeTable buildGlyphShapeTable(std::u32string_view glyphs, int cell_width, int cell_height);

}  // namespace contourtty
