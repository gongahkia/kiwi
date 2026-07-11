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
  expect(strok::quantizeXterm256(strok::Rgb{.r = 255, .g = 0, .b = 0}) == 196, "red maps to xterm red");
  expect(strok::quantizeXterm256(strok::Rgb{.r = 0, .g = 255, .b = 0}) == 46, "green maps to xterm green");
  expect(strok::quantizeXterm256(strok::Rgb{.r = 128, .g = 128, .b = 128}) >= 232, "gray maps to grayscale ramp");
  expect(strok::quantizeAnsi16(strok::Rgb{.r = 255, .g = 0, .b = 0}) == 9, "red maps to bright ansi red");
  expect(strok::quantizeAnsi16(strok::Rgb{.r = 0, .g = 0, .b = 255}) == 12, "blue maps to bright ansi blue");
  expect(strok::xterm256Color(196).r == 255 && strok::xterm256Color(196).g == 0, "xterm index maps back to rgb");
  expect(strok::ansi16Color(12).b == 255, "ansi index maps back to rgb");

  const auto dithered = strok::applyOrderedDither(strok::Rgb{.r = 128, .g = 128, .b = 128}, 0, 0, 16);
  expect(dithered.r < 128 && dithered.g < 128 && dithered.b < 128, "ordered dither adjusts channel");
  expect(strok::ditherModeFromString("ordered") == strok::DitherMode::Ordered, "ordered dither parses");
  expect(strok::ditherModeFromString("fs") == strok::DitherMode::FloydSteinberg, "fs dither parses");
}
