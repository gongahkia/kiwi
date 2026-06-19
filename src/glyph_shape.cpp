#include "glyph_shape.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <stdexcept>
#include <string>

namespace contourtty {
namespace {

constexpr int kBitmapWidth = 5;
constexpr int kBitmapHeight = 7;

using BitmapRows = std::array<std::string_view, kBitmapHeight>;

BitmapRows bitmapRows(char32_t glyph) {
  switch (glyph) {
    case U' ':
      return BitmapRows{".....", ".....", ".....", ".....", ".....", ".....", "....."};
    case U'.':
      return BitmapRows{".....", ".....", ".....", ".....", ".....", "..#..", "..#.."};
    case U':':
      return BitmapRows{".....", "..#..", "..#..", ".....", "..#..", "..#..", "....."};
    case U'-':
      return BitmapRows{".....", ".....", ".....", "#####", ".....", ".....", "....."};
    case U'_':
      return BitmapRows{".....", ".....", ".....", ".....", ".....", ".....", "#####"};
    case U'=':
      return BitmapRows{".....", ".....", "#####", ".....", "#####", ".....", "....."};
    case U'+':
      return BitmapRows{"..#..", "..#..", "..#..", "#####", "..#..", "..#..", "..#.."};
    case U'*':
      return BitmapRows{"#...#", ".#.#.", "..#..", "#####", "..#..", ".#.#.", "#...#"};
    case U'#':
      return BitmapRows{".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."};
    case U'%':
      return BitmapRows{"##..#", "##.#.", "...#.", "..#..", ".#...", ".#.##", "#..##"};
    case U'@':
      return BitmapRows{".###.", "#...#", "#.###", "#.#.#", "#.###", "#....", ".###."};
    case U'|':
      return BitmapRows{"..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."};
    case U'/':
      return BitmapRows{"....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."};
    case U'\\':
      return BitmapRows{"#....", ".#...", ".#...", "..#..", "...#.", "...#.", "....#"};
    default:
      throw std::invalid_argument("unsupported glyph for precomputed shape bitmap");
  }
}

struct Region {
  double cx = 0.0;
  double cy = 0.0;
};

constexpr std::array<Region, kShapeRegionCount> kRegions = {
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

std::vector<double> shapeFeatures(const std::vector<double>& bitmap, int width, int height) {
  const double radius = 0.29;
  std::vector<double> features(kShapeRegionCount, 0.0);
  std::vector<int> samples(kShapeRegionCount, 0);
  for (int y = 0; y < height; ++y) {
    const double ny = (static_cast<double>(y) + 0.5) / static_cast<double>(height);
    for (int x = 0; x < width; ++x) {
      const double nx = (static_cast<double>(x) + 0.5) / static_cast<double>(width);
      const double ink = bitmap[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)];
      for (std::size_t i = 0; i < kRegions.size(); ++i) {
        const double dx = nx - kRegions[i].cx;
        const double dy = ny - kRegions[i].cy;
        if (std::hypot(dx, dy) <= radius) {
          features[i] += ink;
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

void normalizeFeatures(GlyphShapeTable* table) {
  std::vector<double> maxima(kShapeRegionCount, 0.0);
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

}  // namespace

std::vector<double> renderPrecomputedGlyphBitmap(char32_t glyph, int cell_width, int cell_height) {
  if (cell_width <= 0 || cell_height <= 0) {
    throw std::invalid_argument("glyph bitmap dimensions must be positive");
  }
  const BitmapRows rows = bitmapRows(glyph);
  std::vector<double> bitmap;
  bitmap.reserve(static_cast<std::size_t>(cell_width) * static_cast<std::size_t>(cell_height));
  for (int y = 0; y < cell_height; ++y) {
    const int source_y = std::min(kBitmapHeight - 1, (y * kBitmapHeight) / cell_height);
    for (int x = 0; x < cell_width; ++x) {
      const int source_x = std::min(kBitmapWidth - 1, (x * kBitmapWidth) / cell_width);
      bitmap.push_back(rows[static_cast<std::size_t>(source_y)][static_cast<std::size_t>(source_x)] == '#' ? 1.0 : 0.0);
    }
  }
  return bitmap;
}

GlyphShapeTable buildGlyphShapeTable(std::u32string_view glyphs, int cell_width, int cell_height) {
  if (cell_width <= 0 || cell_height <= 0) {
    throw std::invalid_argument("shape table dimensions must be positive");
  }
  GlyphShapeTable table;
  table.cell_width = cell_width;
  table.cell_height = cell_height;
  for (const char32_t glyph : uniqueGlyphs(glyphs)) {
    const std::vector<double> bitmap = renderPrecomputedGlyphBitmap(glyph, cell_width, cell_height);
    table.entries.push_back(GlyphShapeVector{
      .glyph = glyph,
      .features = shapeFeatures(bitmap, cell_width, cell_height),
    });
  }
  normalizeFeatures(&table);
  return table;
}

}  // namespace contourtty
