#pragma once

#include <cstddef>
#include <span>
#include <string_view>
#include <vector>

#include "structure_sampling.hpp"

namespace contourtty {

class GlyphFont;

constexpr std::u32string_view kDefaultShapeGlyphs = U" .:-=+*#%@|/_\\";
constexpr std::u32string_view kDefaultStructureShapeGlyphs = U" |/_\\-+";
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
  std::size_t feature_count = kShapeRegionCount;
  std::vector<GlyphShapeVector> entries;
};

std::vector<double> renderPrecomputedGlyphBitmap(char32_t glyph, int cell_width, int cell_height);
std::vector<double> shapeVectorForValues(std::span<const double> values, int width, int height);
std::vector<double> shapeVectorForCell(const CellLuminanceRegion& region);
GlyphShapeTable buildGlyphShapeTable(std::u32string_view glyphs, int cell_width, int cell_height);
GlyphShapeTable buildGlyphShapeTable(const GlyphFont& font, std::u32string_view glyphs, int cell_width, int cell_height);
char32_t matchGlyphShape(std::span<const double> features, const GlyphShapeTable& table);

}  // namespace contourtty
