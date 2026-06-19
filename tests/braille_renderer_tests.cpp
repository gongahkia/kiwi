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

}  // namespace

int main() {
  contourtty::Frame frame{
    .w = 2,
    .h = 4,
    .rgb = {
      255, 255, 255, 0, 0, 0,
      255, 255, 255, 0, 0, 0,
      255, 255, 255, 0, 0, 0,
      255, 255, 255, 0, 0, 0,
    },
  };
  contourtty::CellBuffer cells;
  contourtty::renderBrailleFrame(frame, 1, 1, &cells);

  expect(cells.cols() == 1 && cells.rows() == 1, "braille dimensions");
  expect(cells.at(0, 0).glyph == U'\u2847', "left column braille dots packed");

  frame.rgb.assign(2 * 4 * 3, 255);
  contourtty::renderBrailleFrame(frame, 1, 1, &cells);
  expect(cells.at(0, 0).glyph == U'\u28ff', "full braille cell");
}
