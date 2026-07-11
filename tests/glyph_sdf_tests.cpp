#include "glyph_sdf.hpp"
#include "glyph_shape.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

std::vector<double> centeredSquare(int width, int height) {
  std::vector<double> values(static_cast<std::size_t>(width) * static_cast<std::size_t>(height), 0.0);
  for (int y = height / 3; y < (height * 2) / 3; ++y) {
    for (int x = width / 3; x < (width * 2) / 3; ++x) {
      values[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] = 1.0;
    }
  }
  return values;
}

}  // namespace

int main() {
  {
    const int width = 9;
    const int height = 9;
    const strok::SignedDistanceField sdf = strok::signedDistanceFieldForValues(centeredSquare(width, height), width, height);
    expect(sdf.width == width && sdf.height == height, "SDF dimensions");
    expect(sdf.values[4 * width + 4] > 0.0, "SDF center is inside-positive");
    expect(sdf.values[0] < 0.0, "SDF corner is outside-negative");
  }

  {
    const std::vector<double> features = strok::sdfVectorForValues(centeredSquare(9, 9), 9, 9);
    expect(features.size() == strok::kShapeRegionCount, "SDF feature count");
    for (const double value : features) {
      expect(value >= 0.0 && value <= 1.0, "SDF feature range");
    }
  }

  {
    const std::vector<double> slash = strok::sdfVectorForValues(strok::renderPrecomputedGlyphBitmap(U'/', 10, 14), 10, 14);
    const strok::GlyphShapeTable table = strok::buildSdfGlyphShapeTable(strok::kDefaultStructureShapeGlyphs, 10, 14);
    expect(table.feature_kind == strok::GlyphFeatureKind::Sdf, "SDF table kind");
    expect(table.feature_count == strok::kShapeRegionCount, "SDF table feature count");
    expect(strok::matchGlyphShape(slash, table) == U'/', "SDF slash matches slash glyph");
  }
}
