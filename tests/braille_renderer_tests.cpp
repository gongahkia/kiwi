#include "braille_renderer.hpp"

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
      0, 255, 0, 0, 0, 255,
      0, 255, 0, 0, 0, 255,
      0, 255, 0, 0, 0, 255,
      0, 255, 0, 0, 0, 255,
    },
  };
  strok::CellBuffer cells;
  strok::renderBrailleFrame(frame, 1, 1, &cells);

  expect(cells.cols() == 1 && cells.rows() == 1, "braille dimensions");
  expect(cells.at(0, 0).glyph == U'\u2847', "left column braille dots packed");
  expect(same(cells.at(0, 0).fg, strok::Rgb{.r = 0, .g = 255, .b = 0}), "braille fg averages on dots");
  expect(same(cells.at(0, 0).bg, strok::Rgb{.r = 0, .g = 0, .b = 255}), "braille bg averages off dots");

  frame.rgb.assign(2 * 4 * 3, 255);
  strok::renderBrailleFrame(frame, 1, 1, &cells);
  expect(cells.at(0, 0).glyph == U'\u28ff', "full braille cell");
  expect(same(cells.at(0, 0).fg, strok::Rgb{.r = 255, .g = 255, .b = 255}), "full braille fg");
  expect(same(cells.at(0, 0).bg, strok::Rgb{}), "full braille bg");
}
