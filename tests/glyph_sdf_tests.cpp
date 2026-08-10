#include "glyph_sdf.hpp"
#include "glyph_shape.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
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

strok::SignedDistanceField exhaustiveSdf(const std::vector<double>& values, int width, int height) {
  strok::SignedDistanceField result;
  result.width = width;
  result.height = height;
  result.values.resize(values.size(), 0.0);
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const bool pixel_inside = values[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] >= 0.5;
      double distance = std::numeric_limits<double>::infinity();
      for (int yy = 0; yy < height; ++yy) {
        for (int xx = 0; xx < width; ++xx) {
          const bool candidate_inside = values[static_cast<std::size_t>(yy) * static_cast<std::size_t>(width) + static_cast<std::size_t>(xx)] >= 0.5;
          if (candidate_inside != pixel_inside) {
            distance = std::min(distance, std::hypot(static_cast<double>(xx - x), static_cast<double>(yy - y)));
          }
        }
      }
      if (!std::isfinite(distance)) {
        distance = std::hypot(static_cast<double>(width), static_cast<double>(height));
      }
      result.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] = pixel_inside ? distance : -distance;
    }
  }
  return result;
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
    const std::vector<std::vector<double>> fixtures = {
      {0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0},
      std::vector<double>(12U, 1.0),
      std::vector<double>(12U, 0.0),
    };
    for (const std::vector<double>& values : fixtures) {
      const strok::SignedDistanceField actual = strok::signedDistanceFieldForValues(values, 4, 3);
      const strok::SignedDistanceField expected = exhaustiveSdf(values, 4, 3);
      for (std::size_t index = 0; index < actual.values.size(); ++index) {
        expect(std::abs(actual.values[index] - expected.values[index]) < 1e-12, "exact EDT matches exhaustive SDF");
      }
    }
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
