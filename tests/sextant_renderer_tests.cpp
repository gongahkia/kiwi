#include "sextant_renderer.hpp"

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
  expect(contourtty::sextantMaskForSamples({1.0, 0.0, 0.0, 0.0, 0.0, 0.0}) == 1, "sextant bit 1");
  expect(contourtty::sextantMaskForSamples({0.0, 0.0, 0.0, 0.0, 0.0, 1.0}) == 32, "sextant bit 6");
  expect(contourtty::sextantGlyphForMask(1) == U'\U0001FB00', "first sextant");
  expect(contourtty::sextantGlyphForMask(22) == U'\U0001FB14', "post-left-half sextant");
  expect(contourtty::sextantGlyphForMask(43) == U'\U0001FB28', "post-right-half sextant");
  expect(contourtty::sextantGlyphForMask(21) == U'▌', "reused left half");
  expect(contourtty::sextantGlyphForMask(42) == U'▐', "reused right half");
  expect(contourtty::sextantGlyphForMask(63) == U'█', "reused full block");

  contourtty::Frame frame{
    .w = 2,
    .h = 3,
    .rgb = {
      0, 255, 0,   0, 0, 0,
      0, 0, 0,     0, 0, 0,
      0, 0, 0,     255, 255, 255,
    },
  };
  contourtty::CellBuffer cells;
  contourtty::renderSextantFrame(frame, 1, 1, &cells);

  expect(cells.cols() == 1 && cells.rows() == 1, "sextant dimensions");
  const contourtty::Cell& cell = cells.at(0, 0);
  expect(cell.glyph == contourtty::sextantGlyphForMask(33), "sextant corner glyph");
  expect(same(cell.fg, contourtty::Rgb{.r = 127, .g = 255, .b = 127}), "sextant fg average");
  expect(same(cell.bg, contourtty::Rgb{}), "sextant bg average");
}
