#include "color_quantization.hpp"

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
  expect(contourtty::quantizeXterm256(contourtty::Rgb{.r = 255, .g = 0, .b = 0}) == 196, "red maps to xterm red");
  expect(contourtty::quantizeXterm256(contourtty::Rgb{.r = 0, .g = 255, .b = 0}) == 46, "green maps to xterm green");
  expect(contourtty::quantizeXterm256(contourtty::Rgb{.r = 128, .g = 128, .b = 128}) >= 232, "gray maps to grayscale ramp");
  expect(contourtty::quantizeAnsi16(contourtty::Rgb{.r = 255, .g = 0, .b = 0}) == 9, "red maps to bright ansi red");
  expect(contourtty::quantizeAnsi16(contourtty::Rgb{.r = 0, .g = 0, .b = 255}) == 12, "blue maps to bright ansi blue");

  const auto dithered = contourtty::applyOrderedDither(contourtty::Rgb{.r = 128, .g = 128, .b = 128}, 0, 0, 16);
  expect(dithered.r < 128 && dithered.g < 128 && dithered.b < 128, "ordered dither adjusts channel");
  expect(contourtty::ditherModeFromString("ordered") == contourtty::DitherMode::Ordered, "ordered dither parses");
  expect(contourtty::ditherModeFromString("fs") == contourtty::DitherMode::FloydSteinberg, "fs dither parses");
}
