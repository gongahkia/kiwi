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

bool same(strok::Rgb lhs, strok::Rgb rhs) {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

}  // namespace

int main() {
  expect(strok::sextantMaskForSamples({1.0, 0.0, 0.0, 0.0, 0.0, 0.0}) == 1, "sextant bit 1");
  expect(strok::sextantMaskForSamples({0.0, 0.0, 0.0, 0.0, 0.0, 1.0}) == 32, "sextant bit 6");
  expect(strok::sextantGlyphForMask(1) == U'\U0001FB00', "first sextant");
  expect(strok::sextantGlyphForMask(22) == U'\U0001FB14', "post-left-half sextant");
  expect(strok::sextantGlyphForMask(43) == U'\U0001FB28', "post-right-half sextant");
  expect(strok::sextantGlyphForMask(21) == U'▌', "reused left half");
  expect(strok::sextantGlyphForMask(42) == U'▐', "reused right half");
  expect(strok::sextantGlyphForMask(63) == U'█', "reused full block");

  strok::Frame frame{
    .w = 2,
    .h = 3,
    .rgb = {
      0, 255, 0,   0, 0, 0,
      0, 0, 0,     0, 0, 0,
      0, 0, 0,     255, 255, 255,
    },
  };
  strok::CellBuffer cells;
  strok::renderSextantFrame(frame, 1, 1, &cells);

  expect(cells.cols() == 1 && cells.rows() == 1, "sextant dimensions");
  const strok::Cell& cell = cells.at(0, 0);
  expect(cell.glyph == strok::sextantGlyphForMask(33), "sextant corner glyph");
  expect(same(cell.fg, strok::Rgb{.r = 127, .g = 255, .b = 127}), "sextant fg average");
  expect(same(cell.bg, strok::Rgb{}), "sextant bg average");
}
