#include "sextant_renderer.hpp"

#include "frame_sampling.hpp"
#include "luminance.hpp"

#include <array>
#include <cstdint>

namespace strok {
namespace {

constexpr std::array<uint8_t, 4> kReusedMasks {0, 21, 42, 63};

int reusedMaskCountBefore(uint8_t mask) {
  int count = 0;
  for (const uint8_t reused : kReusedMasks) {
    if (reused == 0) {
      continue;
    }
    if (reused >= mask) {
      break;
    }
    ++count;
  }
  return count;
}

Rgb averageMasked(const std::array<Rgb, 6>& colors, uint8_t mask, bool selected) {
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

uint8_t sextantMaskForSamples(const std::array<double, 6>& samples, double threshold) {
  uint8_t mask = 0;
  for (std::size_t index = 0; index < samples.size(); ++index) {
    if (samples[index] >= threshold) {
      mask = static_cast<uint8_t>(mask | (1U << index));
    }
  }
  return mask;
}

char32_t sextantGlyphForMask(uint8_t mask) {
  switch (mask) {
    case 0: return U' ';
    case 21: return U'▌';
    case 42: return U'▐';
    case 63: return U'█';
    default: return static_cast<char32_t>(0x1FB00 + mask - 1 - reusedMaskCountBefore(mask));
  }
}

void renderSextantFrame(const Frame& frame, int cols, int rows, CellBuffer* cells) {
  renderSextantFrame(colorImageViewFromValidFrame(frame), cols, rows, cells);
}

void renderSextantFrame(const ColorImageView& image, int cols, int rows, CellBuffer* cells) {
  cells->resize(cols, rows);
  const int sample_cols = cols * 2;
  const int sample_rows = rows * 3;
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      std::array<Rgb, 6> colors{};
      std::array<double, 6> samples{};
      for (int y = 0; y < 3; ++y) {
        for (int x = 0; x < 2; ++x) {
          const std::size_t index = static_cast<std::size_t>(y * 2 + x);
          colors[index] = averageRegion(image, sample_cols, sample_rows, col * 2 + x, row * 3 + y);
          samples[index] = relativeLuminance(colors[index]);
        }
      }
      const uint8_t mask = sextantMaskForSamples(samples);
      Cell& cell = cells->at(col, row);
      cell.glyph = sextantGlyphForMask(mask);
      cell.fg = averageMasked(colors, mask, true);
      cell.bg = averageMasked(colors, mask, false);
    }
  }
}

}  // namespace strok
