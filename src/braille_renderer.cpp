#include "braille_renderer.hpp"

#include "frame_sampling.hpp"
#include "luminance.hpp"

#include <array>
#include <cstdint>

namespace contourtty {
namespace {

constexpr std::array<std::array<uint8_t, 2>, 4> kBrailleBits {{
  std::array<uint8_t, 2>{0x01, 0x08},
  std::array<uint8_t, 2>{0x02, 0x10},
  std::array<uint8_t, 2>{0x04, 0x20},
  std::array<uint8_t, 2>{0x40, 0x80},
}};

}  // namespace

void renderBrailleFrame(const Frame& frame, int cols, int rows, CellBuffer* cells) {
  cells->resize(cols, rows);
  const int sample_cols = cols * 2;
  const int sample_rows = rows * 4;
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      uint8_t mask = 0;
      for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 2; ++x) {
          const Rgb sample = averageRegion(frame, sample_cols, sample_rows, col * 2 + x, row * 4 + y);
          if (relativeLuminance(sample) >= 0.5) {
            mask |= kBrailleBits[static_cast<std::size_t>(y)][static_cast<std::size_t>(x)];
          }
        }
      }
      Cell& cell = cells->at(col, row);
      cell.glyph = static_cast<char32_t>(0x2800U + mask);
      cell.fg = averageRegion(frame, cols, rows, col, row);
      cell.bg = Rgb{};
    }
  }
}

}  // namespace contourtty
