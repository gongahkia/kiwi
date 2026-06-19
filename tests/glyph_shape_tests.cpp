#include "glyph_shape.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

const contourtty::GlyphShapeVector* findGlyph(const contourtty::GlyphShapeTable& table, char32_t glyph) {
  for (const contourtty::GlyphShapeVector& entry : table.entries) {
    if (entry.glyph == glyph) {
      return &entry;
    }
  }
  return nullptr;
}

double feature(const contourtty::GlyphShapeVector& vector, contourtty::ShapeRegion region) {
  return vector.features[static_cast<std::size_t>(region)];
}

}  // namespace

int main() {
  const auto table = contourtty::buildGlyphShapeTable(contourtty::kDefaultShapeGlyphs, 10, 14);
  expect(table.cell_width == 10 && table.cell_height == 14, "shape table dimensions");
  expect(table.entries.size() == contourtty::kDefaultShapeGlyphs.size(), "shape table entry count");

  for (std::size_t i = 0; i < contourtty::kShapeRegionCount; ++i) {
    double max_feature = 0.0;
    for (const auto& entry : table.entries) {
      expect(entry.features.size() == contourtty::kShapeRegionCount, "shape vector length");
      for (const double value : entry.features) {
        expect(value >= 0.0 && value <= 1.0, "shape vector normalized range");
      }
      max_feature = std::max(max_feature, entry.features[i]);
    }
    expect(std::abs(max_feature - 1.0) < 1e-12, "shape vector dimension normalized");
  }

  const auto* vertical = findGlyph(table, U'|');
  const auto* slash = findGlyph(table, U'/');
  const auto* backslash = findGlyph(table, U'\\');
  const auto* space = findGlyph(table, U' ');
  expect(vertical != nullptr && slash != nullptr && backslash != nullptr && space != nullptr, "expected glyph entries");

  expect(feature(*vertical, contourtty::ShapeRegion::Center) > feature(*vertical, contourtty::ShapeRegion::Left), "vertical center exceeds left");
  expect(feature(*vertical, contourtty::ShapeRegion::Center) > feature(*vertical, contourtty::ShapeRegion::Right), "vertical center exceeds right");
  expect(feature(*slash, contourtty::ShapeRegion::TopRight) > feature(*slash, contourtty::ShapeRegion::TopLeft), "slash covers top right");
  expect(feature(*slash, contourtty::ShapeRegion::BottomLeft) > feature(*slash, contourtty::ShapeRegion::BottomRight), "slash covers bottom left");
  expect(feature(*backslash, contourtty::ShapeRegion::TopLeft) > feature(*backslash, contourtty::ShapeRegion::TopRight), "backslash covers top left");
  expect(feature(*backslash, contourtty::ShapeRegion::BottomRight) > feature(*backslash, contourtty::ShapeRegion::BottomLeft), "backslash covers bottom right");
  for (const double value : space->features) {
    expect(value == 0.0, "space shape vector is empty");
  }

  expect(contourtty::matchGlyphShape(contourtty::shapeVectorForValues(contourtty::renderPrecomputedGlyphBitmap(U'|', 10, 14), 10, 14), table) == U'|', "vertical bitmap matches vertical glyph");
  expect(contourtty::matchGlyphShape(contourtty::shapeVectorForValues(contourtty::renderPrecomputedGlyphBitmap(U'/', 10, 14), 10, 14), table) == U'/', "slash bitmap matches slash glyph");
  expect(contourtty::matchGlyphShape(contourtty::shapeVectorForValues(contourtty::renderPrecomputedGlyphBitmap(U'\\', 10, 14), 10, 14), table) == U'\\', "backslash bitmap matches backslash glyph");
  expect(contourtty::matchGlyphShape(std::vector<double>(contourtty::kShapeRegionCount, 0.0), table) == U' ', "empty cell matches space");

  bool unsupported_threw = false;
  try {
    (void)contourtty::buildGlyphShapeTable(U"~", 10, 14);
  } catch (const std::invalid_argument&) {
    unsupported_threw = true;
  }
  expect(unsupported_threw, "unsupported glyph rejected");
}
