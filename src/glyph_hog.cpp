#include "glyph_hog.hpp"

#include "glyph_font.hpp"

#include <algorithm>
#include <cmath>
#include <numbers>
#include <stdexcept>
#include <string>

namespace contourtty {
namespace {

double sample(std::span<const double> values, int width, int height, int x, int y) {
  const int clamped_x = std::clamp(x, 0, width - 1);
  const int clamped_y = std::clamp(y, 0, height - 1);
  return values[static_cast<std::size_t>(clamped_y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(clamped_x)];
}

std::size_t hogBin(double gx, double gy) {
  double angle = std::atan2(gy, gx);
  while (angle < 0.0) {
    angle += std::numbers::pi;
  }
  while (angle >= std::numbers::pi) {
    angle -= std::numbers::pi;
  }
  return std::min<std::size_t>(kHogBins - 1, static_cast<std::size_t>(angle / (std::numbers::pi / static_cast<double>(kHogBins))));
}

void normalize(std::vector<double>* features) {
  double norm = 0.0;
  for (const double value : *features) {
    norm += value * value;
  }
  if (norm == 0.0) {
    return;
  }
  const double inv_norm = 1.0 / std::sqrt(norm);
  for (double& value : *features) {
    value *= inv_norm;
  }
}

std::u32string uniqueGlyphs(std::u32string_view glyphs) {
  std::u32string unique;
  for (const char32_t glyph : glyphs) {
    if (std::find(unique.begin(), unique.end(), glyph) == unique.end()) {
      unique.push_back(glyph);
    }
  }
  if (unique.empty()) {
    throw std::invalid_argument("empty shape glyph set");
  }
  return unique;
}

GlyphShapeTable buildHogTable(std::u32string_view glyphs, int cell_width, int cell_height, auto raster_for_glyph) {
  if (cell_width <= 0 || cell_height <= 0) {
    throw std::invalid_argument("HoG table dimensions must be positive");
  }
  GlyphShapeTable table;
  table.cell_width = cell_width;
  table.cell_height = cell_height;
  table.feature_count = kHogFeatureCount;
  table.feature_kind = GlyphFeatureKind::Hog;
  for (const char32_t glyph : uniqueGlyphs(glyphs)) {
    table.entries.push_back(GlyphShapeVector{
      .glyph = glyph,
      .features = raster_for_glyph(glyph),
    });
  }
  return table;
}

}  // namespace

std::vector<double> hogVectorForValues(std::span<const double> values, int width, int height) {
  if (width <= 0 || height <= 0) {
    throw std::invalid_argument("HoG dimensions must be positive");
  }
  if (values.size() != static_cast<std::size_t>(width) * static_cast<std::size_t>(height)) {
    throw std::invalid_argument("HoG values size does not match dimensions");
  }
  std::vector<double> features(kHogFeatureCount, 0.0);
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const double gx = sample(values, width, height, x + 1, y) - sample(values, width, height, x - 1, y);
      const double gy = sample(values, width, height, x, y + 1) - sample(values, width, height, x, y - 1);
      const double magnitude = std::hypot(gx, gy);
      if (magnitude == 0.0) {
        continue;
      }
      const std::size_t block_x = std::min<std::size_t>(kHogBlocksX - 1, static_cast<std::size_t>(x * static_cast<int>(kHogBlocksX) / width));
      const std::size_t block_y = std::min<std::size_t>(kHogBlocksY - 1, static_cast<std::size_t>(y * static_cast<int>(kHogBlocksY) / height));
      const std::size_t index = ((block_y * kHogBlocksX + block_x) * kHogBins) + hogBin(gx, gy);
      features[index] += magnitude;
    }
  }
  normalize(&features);
  return features;
}

std::vector<double> hogVectorForCell(const CellLuminanceRegion& region) {
  return hogVectorForValues(region.values, region.width(), region.height());
}

GlyphShapeTable buildHogGlyphShapeTable(std::u32string_view glyphs, int cell_width, int cell_height) {
  return buildHogTable(glyphs, cell_width, cell_height, [&](char32_t glyph) {
    return hogVectorForValues(renderPrecomputedGlyphBitmap(glyph, cell_width, cell_height), cell_width, cell_height);
  });
}

GlyphShapeTable buildHogGlyphShapeTable(const GlyphFont& font, std::u32string_view glyphs, int cell_width, int cell_height) {
  return buildHogTable(glyphs, cell_width, cell_height, [&](char32_t glyph) {
    const GlyphRaster& raster = font.raster(glyph, cell_width, cell_height);
    return hogVectorForValues(raster.alpha, raster.width, raster.height);
  });
}

}  // namespace contourtty
