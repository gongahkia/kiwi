#include "glyph_font.hpp"
#include "glyph_ramp.hpp"
#include "glyph_shape.hpp"

#include <array>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <optional>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

std::optional<std::filesystem::path> firstExisting(std::initializer_list<const char*> paths) {
  for (const char* path : paths) {
    if (std::filesystem::exists(path)) {
      return std::filesystem::path(path);
    }
  }
  return std::nullopt;
}

double sumAlpha(const strok::GlyphRaster& raster) {
  double sum = 0.0;
  for (const double alpha : raster.alpha) {
    sum += alpha;
  }
  return sum;
}

const strok::GlyphShapeVector* findGlyph(const strok::GlyphShapeTable& table, char32_t glyph) {
  for (const strok::GlyphShapeVector& entry : table.entries) {
    if (entry.glyph == glyph) {
      return &entry;
    }
  }
  return nullptr;
}

double featureDistance(const strok::GlyphShapeTable& lhs, const strok::GlyphShapeTable& rhs, char32_t glyph) {
  const auto* left = findGlyph(lhs, glyph);
  const auto* right = findGlyph(rhs, glyph);
  expect(left != nullptr && right != nullptr, "font shape glyph present");
  double distance = 0.0;
  for (std::size_t i = 0; i < left->features.size(); ++i) {
    distance += std::abs(left->features[i] - right->features[i]);
  }
  return distance;
}

bool findDifferentMatch(const strok::GlyphShapeTable& first, const strok::GlyphShapeTable& second) {
  std::array<double, 4> values{0.0, 0.35, 0.7, 1.0};
  std::vector<double> sample(strok::kShapeRegionCount, 0.0);
  for (std::size_t mask = 0; mask < 4096; ++mask) {
    std::size_t value = mask;
    for (double& feature : sample) {
      feature = values[value % values.size()];
      value /= values.size();
    }
    if (strok::matchGlyphShape(sample, first) != strok::matchGlyphShape(sample, second)) {
      return true;
    }
  }
  return false;
}

}  // namespace

int main() {
  const auto mono_path = firstExisting({
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",
  });
  const auto alternate_path = firstExisting({
    "/System/Library/Fonts/MarkerFelt.ttc",
    "/System/Library/Fonts/Noteworthy.ttc",
    "/System/Library/Fonts/Symbol.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
    "/usr/share/fonts/dejavu-serif-fonts/DejaVuSerif.ttf",
  });
  if (!mono_path.has_value() || !alternate_path.has_value()) {
    std::cerr << "glyph font test skipped: no compatible system fonts found\n";
    return 0;
  }

  strok::GlyphFont mono(*mono_path);
  const strok::GlyphRaster& slash = mono.raster(U'/', 10, 14);
  const strok::GlyphRaster& slash_cached = mono.raster(U'/', 10, 14);
  expect(slash.width == 10 && slash.height == 14, "font raster dimensions");
  expect(slash.alpha.size() == 140, "font raster alpha size");
  expect(sumAlpha(slash) > 0.0, "font raster has ink");
  expect(&slash == &slash_cached, "font raster cache reused");

  strok::GlyphFont alternate(*alternate_path);
  const strok::GlyphShapeTable mono_table = strok::buildGlyphShapeTable(mono, strok::kDefaultStructureShapeGlyphs, 10, 14);
  const strok::GlyphShapeTable alternate_table = strok::buildGlyphShapeTable(alternate, strok::kDefaultStructureShapeGlyphs, 10, 14);
  expect(featureDistance(mono_table, alternate_table, U'/') > 0.05, "font changes glyph shape features");
  expect(findDifferentMatch(mono_table, alternate_table), "font changes at least one shape-match decision");

  std::u32string reversed_default(strok::kDefaultGlyphRamp.rbegin(), strok::kDefaultGlyphRamp.rend());
  const std::u32string sorted_default = strok::sortRampByInkDensity(strok::kDefaultGlyphRamp, mono, 10, 14);
  const std::u32string sorted_reversed = strok::sortRampByInkDensity(reversed_default, mono, 10, 14);
  expect(sorted_default == sorted_reversed, "ramp sort is independent of input order");
  expect(strok::sortRampByInkDensity(U"@ .", mono, 10, 14).front() == U' ', "ramp sort puts space first");
}
