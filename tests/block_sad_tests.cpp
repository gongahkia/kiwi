#include "block_sad.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

bool same(contourtty::Rgb lhs, contourtty::Rgb rhs) {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

}  // namespace

int main() {
  expect(contourtty::blockGlyphForSamples({1.0, 0.0, 0.0, 0.0}) == U'▘', "upper-left quadrant");
  expect(contourtty::blockGlyphForSamples({0.0, 1.0, 1.0, 0.0}) == U'▞', "diagonal quadrant");
  expect(contourtty::blockGlyphForSamples({0.5, 0.5, 0.5, 0.5}) == U'▒', "half shade");
  expect(contourtty::blockGlyphForSamples({1.0, 1.0, 1.0, 1.0}) == U'█', "full block");

  contourtty::Frame frame{
    .w = 2,
    .h = 2,
    .rgb = {
      255, 255, 255, 0, 0, 0,
      0, 0, 0,       0, 0, 0,
    },
  };
  contourtty::CellBuffer cells;
  contourtty::renderBlockSadFrame(frame, 1, 1, &cells);

  expect(cells.cols() == 1 && cells.rows() == 1, "block sad dimensions");
  const contourtty::Cell& cell = cells.at(0, 0);
  expect(cell.glyph == U'▘', "block sad glyph");
  expect(same(cell.fg, contourtty::Rgb{.r = 63, .g = 63, .b = 63}), "block sad average fg");
  expect(same(cell.bg, contourtty::Rgb{}), "block sad bg");
}
