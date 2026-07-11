#include "octant_renderer.hpp"

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
  expect(strok::octantMaskForSamples({1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}) == 1, "octant bit 1");
  expect(strok::octantMaskForSamples({0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0}) == 128, "octant bit 8");
  expect(strok::octantGlyphForMask(4) == U'\U0001CD00', "first encoded octant");
  expect(strok::octantGlyphForMask(1) == U'\U0001CEA8', "reused octant 1");
  expect(strok::octantGlyphForMask(2) == U'\U0001CEAB', "reused octant 2");
  expect(strok::octantGlyphForMask(3) == U'\U0001FB82', "reused top quarter");
  expect(strok::octantGlyphForMask(15) == U'▀', "reused upper half");
  expect(strok::octantGlyphForMask(255) == U'█', "reused full block");

  strok::Frame frame{
    .w = 2,
    .h = 4,
    .rgb = {
      0, 255, 0,   0, 0, 0,
      0, 0, 0,     0, 0, 0,
      0, 0, 0,     0, 0, 0,
      0, 0, 0,     255, 255, 255,
    },
  };
  strok::CellBuffer cells;
  strok::renderOctantFrame(frame, 1, 1, &cells);

  expect(cells.cols() == 1 && cells.rows() == 1, "octant dimensions");
  const strok::Cell& cell = cells.at(0, 0);
  expect(cell.glyph == strok::octantGlyphForMask(129), "octant corner glyph");
  expect(same(cell.fg, strok::Rgb{.r = 127, .g = 255, .b = 127}), "octant fg average");
  expect(same(cell.bg, strok::Rgb{}), "octant bg average");
}
