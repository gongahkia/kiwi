#include "halfblock_renderer.hpp"

#include "frame_sampling.hpp"

namespace strok {

void renderHalfBlockFrame(const Frame& frame, int cols, int rows, CellBuffer* cells) {
  cells->resize(cols, rows);
  const int sample_rows = rows * 2;
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      Cell& cell = cells->at(col, row);
      cell.glyph = U'▀';
      cell.fg = averageRegion(frame, cols, sample_rows, col, row * 2);
      cell.bg = averageRegion(frame, cols, sample_rows, col, row * 2 + 1);
    }
  }
}

}  // namespace strok
