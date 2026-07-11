#include "glyph_hog.hpp"
#include "glyph_shape.hpp"

#include <algorithm>
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

std::vector<double> horizontalLine(int width, int height) {
  std::vector<double> values(static_cast<std::size_t>(width) * static_cast<std::size_t>(height), 0.0);
  const int row = height / 2;
  for (int x = 0; x < width; ++x) {
    values[static_cast<std::size_t>(row) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] = 1.0;
  }
  return values;
}

std::vector<double> diagonalLine(int width, int height) {
  std::vector<double> values(static_cast<std::size_t>(width) * static_cast<std::size_t>(height), 0.0);
  for (int y = 0; y < height; ++y) {
    const int x = y * width / height;
    values[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] = 1.0;
  }
  return values;
}

double binTotal(const std::vector<double>& hog, std::size_t bin) {
  double sum = 0.0;
  for (std::size_t block = 0; block < strok::kHogBlocksX * strok::kHogBlocksY; ++block) {
    sum += hog[block * strok::kHogBins + bin];
  }
  return sum;
}

std::size_t strongestBin(const std::vector<double>& hog) {
  std::size_t best = 0;
  double best_value = -1.0;
  for (std::size_t bin = 0; bin < strok::kHogBins; ++bin) {
    const double value = binTotal(hog, bin);
    if (value > best_value) {
      best_value = value;
      best = bin;
    }
  }
  return best;
}

double norm(const std::vector<double>& values) {
  double sum = 0.0;
  for (const double value : values) {
    sum += value * value;
  }
  return std::sqrt(sum);
}

}  // namespace

int main() {
  {
    const std::vector<double> hog = strok::hogVectorForValues(horizontalLine(9, 9), 9, 9);
    expect(hog.size() == strok::kHogFeatureCount, "HoG feature count");
    expect(std::abs(norm(hog) - 1.0) < 1e-12, "HoG vector normalized");
    expect(strongestBin(hog) == 4, "horizontal line produces vertical-gradient bin");
  }

  {
    const std::vector<double> hog = strok::hogVectorForValues(diagonalLine(9, 9), 9, 9);
    expect(std::abs(norm(hog) - 1.0) < 1e-12, "diagonal HoG normalized");
    expect(strongestBin(hog) != 0 && strongestBin(hog) != 4, "diagonal line produces diagonal-gradient bin");
  }

  {
    const std::vector<double> first = strok::hogVectorForValues(strok::renderPrecomputedGlyphBitmap(U'/', 10, 14), 10, 14);
    const std::vector<double> second = strok::hogVectorForValues(strok::renderPrecomputedGlyphBitmap(U'/', 10, 14), 10, 14);
    expect(first == second, "identical glyphs yield identical HoG vectors");
    const strok::GlyphShapeTable table = strok::buildHogGlyphShapeTable(strok::kDefaultStructureShapeGlyphs, 10, 14);
    expect(table.feature_count == strok::kHogFeatureCount, "HoG table feature count");
    expect(strok::matchGlyphShape(first, table) == U'/', "HoG slash matches slash glyph");
  }
}
