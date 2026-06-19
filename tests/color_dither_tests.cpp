#include "color_dither.hpp"

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
  expect(contourtty::supportsPaletteDither(contourtty::ColorMode::Color256), "256 supports palette dither");
  expect(contourtty::supportsPaletteDither(contourtty::ColorMode::Color16), "16 supports palette dither");
  expect(!contourtty::supportsPaletteDither(contourtty::ColorMode::Truecolor), "truecolor skips palette dither");

  contourtty::CellBuffer input(3, 1);
  for (int col = 0; col < input.cols(); ++col) {
    contourtty::Cell& cell = input.at(col, 0);
    cell.glyph = U'#';
    cell.fg = contourtty::Rgb{.r = 155, .g = 155, .b = 155};
    cell.bg = contourtty::Rgb{.r = 155, .g = 155, .b = 155};
  }
  const contourtty::CellBuffer output = contourtty::applyFloydSteinbergDither(input, contourtty::ColorMode::Color16);
  expect(same(output.at(0, 0).fg, contourtty::Rgb{.r = 128, .g = 128, .b = 128}), "fs first quantized gray");
  expect(same(output.at(1, 0).fg, contourtty::Rgb{.r = 192, .g = 192, .b = 192}), "fs diffused gray error");
  expect(output.at(1, 0).glyph == U'#', "fs preserves glyph");

  const contourtty::CellBuffer palette = contourtty::applyPaletteDither(input, contourtty::ColorMode::Color16, contourtty::DitherMode::None);
  expect(same(palette.at(0, 0).fg, contourtty::Rgb{.r = 128, .g = 128, .b = 128}), "palette dither quantizes fg before emit");
  expect(same(palette.at(0, 0).bg, contourtty::Rgb{.r = 128, .g = 128, .b = 128}), "palette dither quantizes bg before emit");
}
