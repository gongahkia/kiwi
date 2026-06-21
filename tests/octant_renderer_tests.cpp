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

bool same(contourtty::Rgb lhs, contourtty::Rgb rhs) {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

}  // namespace

int main() {
  expect(contourtty::octantMaskForSamples({1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}) == 1, "octant bit 1");
  expect(contourtty::octantMaskForSamples({0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0}) == 128, "octant bit 8");
  expect(contourtty::octantGlyphForMask(4) == U'\U0001CD00', "first encoded octant");
  expect(contourtty::octantGlyphForMask(1) == U'\U0001CEA8', "reused octant 1");
  expect(contourtty::octantGlyphForMask(2) == U'\U0001CEAB', "reused octant 2");
  expect(contourtty::octantGlyphForMask(3) == U'\U0001FB82', "reused top quarter");
  expect(contourtty::octantGlyphForMask(15) == U'▀', "reused upper half");
  expect(contourtty::octantGlyphForMask(255) == U'█', "reused full block");

  contourtty::Frame frame{
    .w = 2,
    .h = 4,
    .rgb = {
      0, 255, 0,   0, 0, 0,
      0, 0, 0,     0, 0, 0,
      0, 0, 0,     0, 0, 0,
      0, 0, 0,     255, 255, 255,
    },
  };
  contourtty::CellBuffer cells;
  contourtty::renderOctantFrame(frame, 1, 1, &cells);

  expect(cells.cols() == 1 && cells.rows() == 1, "octant dimensions");
  const contourtty::Cell& cell = cells.at(0, 0);
  expect(cell.glyph == contourtty::octantGlyphForMask(129), "octant corner glyph");
  expect(same(cell.fg, contourtty::Rgb{.r = 127, .g = 255, .b = 127}), "octant fg average");
  expect(same(cell.bg, contourtty::Rgb{}), "octant bg average");
}
