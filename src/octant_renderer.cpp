#include "octant_renderer.hpp"

#include "frame_sampling.hpp"
#include "luminance.hpp"

#include <array>
#include <cstdint>

namespace strok {
namespace {

constexpr std::array<uint8_t, 26> kReusedMasks {
  0, 1, 2, 3, 5, 10, 15, 20, 40, 63, 64, 80, 85,
  90, 95, 128, 160, 165, 170, 175, 192, 240, 245, 250, 252, 255,
};

int reusedMaskCountBefore(uint8_t mask) {
  int count = 0;
  for (const uint8_t reused : kReusedMasks) {
    if (reused >= mask) {
      break;
    }
    ++count;
  }
  return count;
}

Rgb averageMasked(const std::array<Rgb, 8>& colors, uint8_t mask, bool selected) {
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
    return Rgb{};
  }
  return Rgb{
    .r = static_cast<uint8_t>(r / count),
    .g = static_cast<uint8_t>(g / count),
    .b = static_cast<uint8_t>(b / count),
  };
}

}  // namespace

uint8_t octantMaskForSamples(const std::array<double, 8>& samples, double threshold) {
  uint8_t mask = 0;
  for (std::size_t index = 0; index < samples.size(); ++index) {
    if (samples[index] >= threshold) {
      mask = static_cast<uint8_t>(mask | (1U << index));
    }
  }
  return mask;
}

char32_t octantGlyphForMask(uint8_t mask) {
  switch (mask) {
    case 0: return U' ';
    case 1: return U'\U0001CEA8';
    case 2: return U'\U0001CEAB';
    case 3: return U'\U0001FB82';
    case 5: return U'▘';
    case 10: return U'▝';
    case 15: return U'▀';
    case 20: return U'\U0001FBE6';
    case 40: return U'\U0001FBE7';
    case 63: return U'\U0001FB85';
    case 64: return U'\U0001CEA3';
    case 80: return U'▖';
    case 85: return U'▌';
    case 90: return U'▞';
    case 95: return U'▛';
    case 128: return U'\U0001CEA0';
    case 160: return U'▗';
    case 165: return U'▚';
    case 170: return U'▐';
    case 175: return U'▜';
    case 192: return U'▂';
    case 240: return U'▄';
    case 245: return U'▙';
    case 250: return U'▟';
    case 252: return U'▆';
    case 255: return U'█';
    default: return static_cast<char32_t>(0x1CD00 + mask - reusedMaskCountBefore(mask));
  }
}

void renderOctantFrame(const Frame& frame, int cols, int rows, CellBuffer* cells) {
  cells->resize(cols, rows);
  const int sample_cols = cols * 2;
  const int sample_rows = rows * 4;
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      std::array<Rgb, 8> colors{};
      std::array<double, 8> samples{};
      for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 2; ++x) {
          const std::size_t index = static_cast<std::size_t>(y * 2 + x);
          colors[index] = averageRegion(frame, sample_cols, sample_rows, col * 2 + x, row * 4 + y);
          samples[index] = relativeLuminance(colors[index]);
        }
      }
      const uint8_t mask = octantMaskForSamples(samples);
      Cell& cell = cells->at(col, row);
      cell.glyph = octantGlyphForMask(mask);
      cell.fg = averageMasked(colors, mask, true);
      cell.bg = averageMasked(colors, mask, false);
    }
  }
}

}  // namespace strok
