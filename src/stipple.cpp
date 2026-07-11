#include "stipple.hpp"

#include "frame_sampling.hpp"
#include "luminance.hpp"
#include "octant_renderer.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace strok {
namespace {

namespace fs = std::filesystem;

constexpr int kTileSize = 64;
constexpr int kTilePixels = kTileSize * kTileSize;

constexpr std::array<std::array<uint8_t, 2>, 4> kBrailleBits {{
  std::array<uint8_t, 2>{0x01, 0x08},
  std::array<uint8_t, 2>{0x02, 0x10},
  std::array<uint8_t, 2>{0x04, 0x20},
  std::array<uint8_t, 2>{0x40, 0x80},
}};

std::vector<fs::path> blueNoiseTilePaths() {
  std::vector<fs::path> paths;
  if (const char* data_dir = std::getenv("STROK_DATA_DIR"); data_dir != nullptr && *data_dir != '\0') {
    paths.push_back(fs::path(data_dir) / "noise" / "blue_noise_64.bin");
  }
#ifdef STROK_SOURCE_DIR
  paths.push_back(fs::path(STROK_SOURCE_DIR) / "share" / "strok" / "noise" / "blue_noise_64.bin");
#endif
#ifdef STROK_DATA_DIR
  paths.push_back(fs::path(STROK_DATA_DIR) / "noise" / "blue_noise_64.bin");
#endif
  paths.push_back(fs::path("share") / "strok" / "noise" / "blue_noise_64.bin");
  return paths;
}

std::array<uint8_t, kTilePixels> loadBlueNoiseTile() {
  std::array<uint8_t, kTilePixels> ranks{};
  for (const fs::path& path : blueNoiseTilePaths()) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
      continue;
    }
    input.read(reinterpret_cast<char*>(ranks.data()), static_cast<std::streamsize>(ranks.size()));
    if (input.gcount() != static_cast<std::streamsize>(ranks.size())) {
      throw std::invalid_argument("invalid blue noise tile size: " + path.string());
    }
    char extra = 0;
    if (input.get(extra)) {
      throw std::invalid_argument("invalid blue noise tile size: " + path.string());
    }
    return ranks;
  }
  throw std::invalid_argument("missing blue noise tile: share/strok/noise/blue_noise_64.bin");
}

const std::array<uint8_t, kTilePixels>& blueNoiseTile() {
  static const std::array<uint8_t, kTilePixels> tile = loadBlueNoiseTile();
  return tile;
}

bool stippleDotEnabled(double luminance, uint8_t noise_rank) {
  const double shade = std::clamp(1.0 - luminance, 0.0, 1.0);
  const double threshold = static_cast<double>(noise_rank) / 255.0;
  return shade > threshold;
}

Rgb averageMasked(const std::array<Rgb, 8>& colors, uint8_t mask, bool selected, Rgb fallback) {
  uint64_t r = 0;
  uint64_t g = 0;
  uint64_t b = 0;
  uint64_t count = 0;
  for (std::size_t index = 0; index < colors.size(); ++index) {
    const bool on = (mask & (1U << index)) != 0;
    if (on != selected) {
      continue;
    }
    r += colors[index].r;
    g += colors[index].g;
    b += colors[index].b;
    ++count;
  }
  if (count == 0) {
    return fallback;
  }
  return Rgb{
    .r = static_cast<uint8_t>(r / count),
    .g = static_cast<uint8_t>(g / count),
    .b = static_cast<uint8_t>(b / count),
  };
}

Rgb sampleStippleColor(const Cell& cell, const Frame* source_frame, int sample_cols, int sample_rows, int col, int row) {
  if (source_frame == nullptr) {
    return cell.fg;
  }
  return averageRegion(*source_frame, sample_cols, sample_rows, col, row);
}

void applyCellStipple(CellBuffer* cells) {
  for (int row = 0; row < cells->rows(); ++row) {
    for (int col = 0; col < cells->cols(); ++col) {
      Cell& cell = cells->at(col, row);
      cell.glyph = stippleGlyphForLuminance(relativeLuminance(cell.fg), blueNoiseRank64(col, row));
    }
  }
}

void applyBrailleStipple(CellBuffer* cells, const Frame* source_frame) {
  const int sample_cols = cells->cols() * 2;
  const int sample_rows = cells->rows() * 4;
  for (int row = 0; row < cells->rows(); ++row) {
    for (int col = 0; col < cells->cols(); ++col) {
      Cell& cell = cells->at(col, row);
      std::array<Rgb, 8> colors{};
      uint8_t mask = 0;
      uint8_t color_mask = 0;
      for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 2; ++x) {
          const std::size_t index = static_cast<std::size_t>(y * 2 + x);
          colors[index] = sampleStippleColor(cell, source_frame, sample_cols, sample_rows, col * 2 + x, row * 4 + y);
          if (stippleDotEnabled(relativeLuminance(colors[index]), blueNoiseRank64(col * 2 + x, row * 4 + y))) {
            mask |= kBrailleBits[static_cast<std::size_t>(y)][static_cast<std::size_t>(x)];
            color_mask = static_cast<uint8_t>(color_mask | (1U << index));
          }
        }
      }
      cell.glyph = mask == 0 ? U' ' : static_cast<char32_t>(0x2800U + mask);
      cell.fg = averageMasked(colors, color_mask, true, cell.fg);
      cell.bg = averageMasked(colors, color_mask, false, cell.bg);
    }
  }
}

void applyOctantStipple(CellBuffer* cells, const Frame* source_frame) {
  const int sample_cols = cells->cols() * 2;
  const int sample_rows = cells->rows() * 4;
  for (int row = 0; row < cells->rows(); ++row) {
    for (int col = 0; col < cells->cols(); ++col) {
      Cell& cell = cells->at(col, row);
      std::array<Rgb, 8> colors{};
      uint8_t mask = 0;
      for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 2; ++x) {
          const std::size_t index = static_cast<std::size_t>(y * 2 + x);
          colors[index] = sampleStippleColor(cell, source_frame, sample_cols, sample_rows, col * 2 + x, row * 4 + y);
          if (stippleDotEnabled(relativeLuminance(colors[index]), blueNoiseRank64(col * 2 + x, row * 4 + y))) {
            mask = static_cast<uint8_t>(mask | (1U << index));
          }
        }
      }
      cell.glyph = octantGlyphForMask(mask);
      cell.fg = averageMasked(colors, mask, true, cell.fg);
      cell.bg = averageMasked(colors, mask, false, cell.bg);
    }
  }
}

}  // namespace

uint8_t blueNoiseRank64(int x, int y) {
  const int tx = ((x % kTileSize) + kTileSize) % kTileSize;
  const int ty = ((y % kTileSize) + kTileSize) % kTileSize;
  return blueNoiseTile()[static_cast<std::size_t>(ty * kTileSize + tx)];
}

StippleCarrier stippleCarrierFromMode(std::string_view mode) noexcept {
  if (mode == "braille") {
    return StippleCarrier::Braille;
  }
  if (mode == "octant") {
    return StippleCarrier::Octant;
  }
  return StippleCarrier::Cell;
}

char32_t stippleGlyphForLuminance(double luminance, uint8_t noise_rank) {
  if (!stippleDotEnabled(luminance, noise_rank)) {
    return U' ';
  }
  const double shade = std::clamp(1.0 - luminance, 0.0, 1.0);
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

void applyStipple(CellBuffer* cells, StippleCarrier carrier, const Frame* source_frame) {
  if (cells == nullptr) {
    throw std::invalid_argument("cells must not be null");
  }
  switch (carrier) {
    case StippleCarrier::Braille:
      applyBrailleStipple(cells, source_frame);
      return;
    case StippleCarrier::Octant:
      applyOctantStipple(cells, source_frame);
      return;
    case StippleCarrier::Cell:
      applyCellStipple(cells);
      return;
  }
}

}  // namespace strok
