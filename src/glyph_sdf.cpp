#include "glyph_sdf.hpp"

#include "glyph_font.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <string>

namespace contourtty {
namespace {

constexpr double kInsideThreshold = 0.5;

struct Region {
  double cx = 0.0;
  double cy = 0.0;
};

constexpr std::array<Region, kShapeRegionCount> kSdfRegions = {
  Region{.cx = 0.50, .cy = 0.50},
  Region{.cx = 0.50, .cy = 0.20},
  Region{.cx = 0.50, .cy = 0.80},
  Region{.cx = 0.20, .cy = 0.50},
  Region{.cx = 0.80, .cy = 0.50},
  Region{.cx = 0.25, .cy = 0.25},
  Region{.cx = 0.75, .cy = 0.25},
  Region{.cx = 0.25, .cy = 0.75},
  Region{.cx = 0.75, .cy = 0.75},
};

bool inside(std::span<const double> values, int width, int x, int y) {
  return values[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] >= kInsideThreshold;
}

double nearestDistance(std::span<const double> values, int width, int height, int x, int y, bool target_inside) {
  double best = std::numeric_limits<double>::infinity();
  for (int yy = 0; yy < height; ++yy) {
    for (int xx = 0; xx < width; ++xx) {
      if (inside(values, width, xx, yy) != target_inside) {
        continue;
      }
      best = std::min(best, std::hypot(static_cast<double>(xx - x), static_cast<double>(yy - y)));
    }
  }
  return std::isfinite(best) ? best : std::hypot(static_cast<double>(width), static_cast<double>(height));
}

std::vector<double> sdfRegionFeatures(const SignedDistanceField& sdf) {
  const double radius = 0.29;
  const double falloff = std::max(1.0, std::hypot(static_cast<double>(sdf.width), static_cast<double>(sdf.height)) * 0.20);
  std::vector<double> features(kShapeRegionCount, 0.0);
  std::vector<int> samples(kShapeRegionCount, 0);
  for (int y = 0; y < sdf.height; ++y) {
    const double ny = (static_cast<double>(y) + 0.5) / static_cast<double>(sdf.height);
    for (int x = 0; x < sdf.width; ++x) {
      const double nx = (static_cast<double>(x) + 0.5) / static_cast<double>(sdf.width);
      const double signed_distance = sdf.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(sdf.width) + static_cast<std::size_t>(x)];
      const double contribution = std::clamp(0.5 + signed_distance / (2.0 * falloff), 0.0, 1.0);
      for (std::size_t i = 0; i < kSdfRegions.size(); ++i) {
        const double dx = nx - kSdfRegions[i].cx;
        const double dy = ny - kSdfRegions[i].cy;
        if (std::hypot(dx, dy) <= radius) {
          features[i] += contribution;
          ++samples[i];
        }
      }
    }
  }
  for (std::size_t i = 0; i < features.size(); ++i) {
    if (samples[i] > 0) {
      features[i] /= static_cast<double>(samples[i]);
    }
  }
  return features;
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

void normalizeFeatures(GlyphShapeTable* table) {
  std::vector<double> maxima(table->feature_count, 0.0);
  for (const GlyphShapeVector& entry : table->entries) {
    for (std::size_t i = 0; i < entry.features.size(); ++i) {
      maxima[i] = std::max(maxima[i], entry.features[i]);
    }
  }
  for (GlyphShapeVector& entry : table->entries) {
    for (std::size_t i = 0; i < entry.features.size(); ++i) {
      if (maxima[i] > 0.0) {
        entry.features[i] /= maxima[i];
      }
    }
  }
}

GlyphShapeTable buildSdfTable(std::u32string_view glyphs, int cell_width, int cell_height, auto raster_for_glyph) {
  if (cell_width <= 0 || cell_height <= 0) {
    throw std::invalid_argument("SDF table dimensions must be positive");
  }
  GlyphShapeTable table;
  table.cell_width = cell_width;
  table.cell_height = cell_height;
  table.feature_count = kShapeRegionCount;
  table.feature_kind = GlyphFeatureKind::Sdf;
  for (const char32_t glyph : uniqueGlyphs(glyphs)) {
    table.entries.push_back(GlyphShapeVector{
      .glyph = glyph,
      .features = raster_for_glyph(glyph),
    });
  }
  normalizeFeatures(&table);
  return table;
}

}  // namespace

SignedDistanceField signedDistanceFieldForValues(std::span<const double> values, int width, int height) {
  if (width <= 0 || height <= 0) {
    throw std::invalid_argument("SDF dimensions must be positive");
  }
  if (values.size() != static_cast<std::size_t>(width) * static_cast<std::size_t>(height)) {
    throw std::invalid_argument("SDF values size does not match dimensions");
  }
  SignedDistanceField sdf;
  sdf.width = width;
  sdf.height = height;
  sdf.values.resize(values.size(), 0.0);
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const bool pixel_inside = inside(values, width, x, y);
      const double distance = nearestDistance(values, width, height, x, y, !pixel_inside);
      sdf.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] = pixel_inside ? distance : -distance;
    }
  }
  return sdf;
}

std::vector<double> sdfVectorForValues(std::span<const double> values, int width, int height) {
  return sdfRegionFeatures(signedDistanceFieldForValues(values, width, height));
}

std::vector<double> sdfVectorForCell(const CellLuminanceRegion& region) {
  return sdfVectorForValues(region.values, region.width(), region.height());
}

GlyphShapeTable buildSdfGlyphShapeTable(std::u32string_view glyphs, int cell_width, int cell_height) {
  return buildSdfTable(glyphs, cell_width, cell_height, [&](char32_t glyph) {
    return sdfVectorForValues(renderPrecomputedGlyphBitmap(glyph, cell_width, cell_height), cell_width, cell_height);
  });
}

GlyphShapeTable buildSdfGlyphShapeTable(const GlyphFont& font, std::u32string_view glyphs, int cell_width, int cell_height) {
  return buildSdfTable(glyphs, cell_width, cell_height, [&](char32_t glyph) {
    const GlyphRaster& raster = font.raster(glyph, cell_width, cell_height);
    return sdfVectorForValues(raster.alpha, raster.width, raster.height);
  });
}

}  // namespace contourtty
