#include "braille_renderer.hpp"

#include "frame_sampling.hpp"
#include "luminance.hpp"

#include <array>
#include <cstddef>
#include <cstdint>

namespace strok {
namespace {

constexpr std::array<std::array<uint8_t, 2>, 4> kBrailleBits {{
  std::array<uint8_t, 2>{0x01, 0x08},
  std::array<uint8_t, 2>{0x02, 0x10},
  std::array<uint8_t, 2>{0x04, 0x20},
  std::array<uint8_t, 2>{0x40, 0x80},
}};

Rgb averageMasked(const std::array<Rgb, 8>& colors, uint8_t mask, bool selected) {
  uint64_t r = 0;
  uint64_t g = 0;
  uint64_t b = 0;
  uint64_t count = 0;
  for (std::size_t index = 0; index < colors.size(); ++index) {
    const uint8_t bit = kBrailleBits[index / 2][index % 2];
    const bool on = (mask & bit) != 0;
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

void renderBrailleFrame(const Frame& frame, int cols, int rows, CellBuffer* cells) {
  renderBrailleFrame(colorImageViewFromValidFrame(frame), cols, rows, cells);
}

void renderBrailleFrame(const ColorImageView& image, int cols, int rows, CellBuffer* cells) {
  cells->resize(cols, rows);
  const int sample_cols = cols * 2;
  const int sample_rows = rows * 4;
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      uint8_t mask = 0;
      std::array<Rgb, 8> colors{};
      for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 2; ++x) {
          const std::size_t index = static_cast<std::size_t>(y * 2 + x);
          colors[index] = averageRegion(image, sample_cols, sample_rows, col * 2 + x, row * 4 + y);
          const Rgb sample = colors[index];
          if (relativeLuminance(sample) >= 0.5) {
            mask |= kBrailleBits[static_cast<std::size_t>(y)][static_cast<std::size_t>(x)];
          }
        }
      }
      Cell& cell = cells->at(col, row);
      cell.glyph = static_cast<char32_t>(0x2800U + mask);
      cell.fg = averageMasked(colors, mask, true);
      cell.bg = averageMasked(colors, mask, false);
    }
  }
}

}  // namespace strok
