#include "stipple.hpp"

#include "luminance.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <numeric>
#include <stdexcept>
#include <vector>

namespace contourtty {
namespace {

constexpr int kTileSize = 64;
constexpr int kTilePixels = kTileSize * kTileSize;

uint32_t hashCoord(int x, int y) {
  uint32_t value = static_cast<uint32_t>(x) * 0x9E3779B1U ^ static_cast<uint32_t>(y) * 0x85EBCA77U;
  value ^= value >> 16U;
  value *= 0x7FEB352DU;
  value ^= value >> 15U;
  value *= 0x846CA68BU;
  value ^= value >> 16U;
  return value;
}

std::array<uint8_t, kTilePixels> makeBlueNoiseTile() {
  std::array<uint8_t, kTilePixels> ranks{};
  std::vector<int> order(kTilePixels);
  std::iota(order.begin(), order.end(), 0);
  std::sort(order.begin(), order.end(), [](int lhs, int rhs) {
    return hashCoord(lhs % kTileSize, lhs / kTileSize) < hashCoord(rhs % kTileSize, rhs / kTileSize);
  });
  for (int rank = 0; rank < kTilePixels; ++rank) {
    ranks[static_cast<std::size_t>(order[static_cast<std::size_t>(rank)])] = static_cast<uint8_t>((rank * 255) / (kTilePixels - 1));
  }
  return ranks;
}

const std::array<uint8_t, kTilePixels>& blueNoiseTile() {
  static const std::array<uint8_t, kTilePixels> tile = makeBlueNoiseTile();
  return tile;
}

}  // namespace

uint8_t blueNoiseRank64(int x, int y) {
  const int tx = ((x % kTileSize) + kTileSize) % kTileSize;
  const int ty = ((y % kTileSize) + kTileSize) % kTileSize;
  return blueNoiseTile()[static_cast<std::size_t>(ty * kTileSize + tx)];
}

char32_t stippleGlyphForLuminance(double luminance, uint8_t noise_rank) {
  const double shade = std::clamp(1.0 - luminance, 0.0, 1.0);
  const double threshold = static_cast<double>(noise_rank) / 255.0;
  if (shade <= threshold) {
    return U' ';
  }
  if (shade > 0.82) {
    return U'●';
  }
  if (shade > 0.62) {
    return U'•';
  }
  if (shade > 0.42) {
    return U'∙';
  }
  return U'·';
}

void applyStipple(CellBuffer* cells) {
  if (cells == nullptr) {
    throw std::invalid_argument("cells must not be null");
  }
  for (int row = 0; row < cells->rows(); ++row) {
    for (int col = 0; col < cells->cols(); ++col) {
      Cell& cell = cells->at(col, row);
      cell.glyph = stippleGlyphForLuminance(relativeLuminance(cell.fg), blueNoiseRank64(col, row));
    }
  }
}

}  // namespace contourtty
