#pragma once

#include <cstddef>
#include <memory>
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

enum class GlyphFeatureKind {
  Overlap,
  Hog,
  Sdf,
};

struct GlyphShapeVector {
  char32_t glyph = U' ';
  std::vector<double> features;
};

struct GlyphShapeMatch {
  char32_t glyph = U' ';
  double score = 0.0;
};

class GlyphShapeIndex {
 public:
  virtual ~GlyphShapeIndex() = default;
  virtual char32_t match(std::span<const double> features) const = 0;
};

struct GlyphShapeTable {
  int cell_width = 0;
  int cell_height = 0;
  std::size_t feature_count = kShapeRegionCount;
  GlyphFeatureKind feature_kind = GlyphFeatureKind::Overlap;
  std::vector<GlyphShapeVector> entries;
  std::shared_ptr<const GlyphShapeIndex> index;
};

std::vector<double> renderPrecomputedGlyphBitmap(char32_t glyph, int cell_width, int cell_height);
std::vector<double> shapeVectorForValues(std::span<const double> values, int width, int height);
std::vector<double> shapeVectorForCell(const CellLuminanceRegion& region);
GlyphShapeTable buildGlyphShapeTable(std::u32string_view glyphs, int cell_width, int cell_height);
GlyphShapeTable buildGlyphShapeTable(const GlyphFont& font, std::u32string_view glyphs, int cell_width, int cell_height);
double scoreGlyphShape(std::span<const double> features, const GlyphShapeTable& table, char32_t glyph);
GlyphShapeMatch matchGlyphShapeLinearWithScore(std::span<const double> features, const GlyphShapeTable& table);
char32_t matchGlyphShapeLinear(std::span<const double> features, const GlyphShapeTable& table);
GlyphShapeMatch matchGlyphShapeWithScore(std::span<const double> features, const GlyphShapeTable& table);
char32_t matchGlyphShape(std::span<const double> features, const GlyphShapeTable& table);

}  // namespace contourtty
