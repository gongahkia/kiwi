#include "glyph_kdtree.hpp"
#include "glyph_shape.hpp"

#include <chrono>
#include <cmath>
#include <cstdint>
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

std::vector<double> normalizedVector(std::size_t seed, std::size_t dims) {
  std::vector<double> values(dims, 0.0);
  double norm = 0.0;
  uint32_t state = static_cast<uint32_t>(seed + 1U) * 747796405U + 2891336453U;
  for (std::size_t dim = 0; dim < dims; ++dim) {
    state = state * 1664525U + 1013904223U;
    const double value = static_cast<double>((state & 0xffffU) + 1U);
    values[dim] = value;
    norm += value * value;
  }
  const double inv_norm = 1.0 / std::sqrt(norm);
  for (double& value : values) {
    value *= inv_norm;
  }
  return values;
}

strok::GlyphShapeTable syntheticHogTable(std::size_t count) {
  strok::GlyphShapeTable table;
  table.cell_width = 10;
  table.cell_height = 14;
  table.feature_count = 32;
  table.feature_kind = strok::GlyphFeatureKind::Hog;
  for (std::size_t i = 0; i < count; ++i) {
    table.entries.push_back(strok::GlyphShapeVector{
      .glyph = static_cast<char32_t>(0x2500U + i),
      .features = normalizedVector(i, table.feature_count),
    });
  }
  return table;
}

template <typename Body>
int64_t timeNs(Body body, uint64_t* checksum) {
  const auto start = std::chrono::steady_clock::now();
  *checksum += body();
  return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - start).count();
}

}  // namespace

int main() {
  strok::GlyphShapeTable table = syntheticHogTable(64);
  std::vector<std::vector<double>> queries;
  for (std::size_t i = 0; i < 4096; ++i) {
    queries.push_back(table.entries[i % table.entries.size()].features);
  }

  strok::attachGlyphKdTree(&table);
  int matches = 0;
  for (const std::vector<double>& query : queries) {
    if (strok::matchGlyphShape(query, table) == strok::matchGlyphShapeLinear(query, table)) {
      ++matches;
    }
  }
  expect(matches * 100 >= static_cast<int>(queries.size()) * 99, "kd-tree match-rate below 99%");

  uint64_t linear_checksum = 0;
  const int64_t linear_ns = timeNs([&] {
    uint64_t sum = 0;
    for (const std::vector<double>& query : queries) {
      sum += static_cast<uint32_t>(strok::matchGlyphShapeLinear(query, table));
    }
    return sum;
  }, &linear_checksum);

  uint64_t kd_checksum = 0;
  const int64_t kd_ns = timeNs([&] {
    uint64_t sum = 0;
    for (const std::vector<double>& query : queries) {
      sum += static_cast<uint32_t>(strok::matchGlyphShape(query, table));
    }
    return sum;
  }, &kd_checksum);

  expect(linear_checksum == kd_checksum, "kd-tree checksum mismatch");
  expect(kd_ns > 0, "kd-tree timing invalid");
  if (std::getenv("STROK_KD_TREE_BENCH") != nullptr) {
    if (linear_ns < kd_ns * 10) {
      std::cerr << "kd-tree speedup below 10x: linear_ns=" << linear_ns << " kd_ns=" << kd_ns << '\n';
      return 1;
    }
    std::cout << "queries=" << queries.size() << " entries=" << table.entries.size()
              << " linear_ns=" << linear_ns << " kd_ns=" << kd_ns
              << " speedup=" << static_cast<double>(linear_ns) / static_cast<double>(kd_ns) << '\n';
  }
}
