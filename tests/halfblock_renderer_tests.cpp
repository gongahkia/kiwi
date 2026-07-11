#include "halfblock_renderer.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

bool same(strok::Rgb lhs, strok::Rgb rhs) {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

}  // namespace

int main() {
  strok::Frame frame{
    .w = 2,
    .h = 4,
    .rgb = {
      255, 0, 0,   255, 0, 0,
      255, 0, 0,   255, 0, 0,
      0, 0, 255,   0, 0, 255,
      0, 0, 255,   0, 0, 255,
    },
  };
  strok::CellBuffer cells;
  strok::renderHalfBlockFrame(frame, 1, 1, &cells);

  expect(cells.cols() == 1 && cells.rows() == 1, "halfblock dimensions");
  const strok::Cell& cell = cells.at(0, 0);
  expect(cell.glyph == U'▀', "halfblock glyph");
  expect(same(cell.fg, strok::Rgb{.r = 255, .g = 0, .b = 0}), "top half fg");
  expect(same(cell.bg, strok::Rgb{.r = 0, .g = 0, .b = 255}), "bottom half bg");
}
