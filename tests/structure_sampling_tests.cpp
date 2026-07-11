#include "structure_sampling.hpp"

#include "luminance.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

void expectNear(double actual, double expected, const char* label) {
  if (std::abs(actual - expected) > 1e-12) {
    std::cerr << label << ": expected " << expected << ", got " << actual << '\n';
    std::exit(1);
  }
}

strok::Frame grayFrame(int width, int height) {
  strok::Frame frame;
  frame.w = width;
  frame.h = height;
  frame.rgb.reserve(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 3);
  for (int i = 0; i < width * height; ++i) {
    const auto value = static_cast<uint8_t>(i);
    frame.rgb.push_back(value);
    frame.rgb.push_back(value);
    frame.rgb.push_back(value);
  }
  return frame;
}

}  // namespace

int main() {
  const strok::Frame frame = grayFrame(4, 4);
  const auto field = strok::makeLuminanceField(frame);
  expect(field.width == 4 && field.height == 4, "field dimensions");
  expect(field.values.size() == 16, "field stores every source pixel");

  const auto top_left = strok::sampleCellRegion(field, 2, 2, 0, 0);
  expect(top_left.source.x0 == 0 && top_left.source.x1 == 2, "top-left x range");
  expect(top_left.source.y0 == 0 && top_left.source.y1 == 2, "top-left y range");
  expect(top_left.values.size() == 4, "top-left keeps full 2x2 block");
  expectNear(top_left.at(0, 0), strok::relativeLuminance(strok::Rgb{.r = 0, .g = 0, .b = 0}), "top-left sample 0");
  expectNear(top_left.at(1, 0), strok::relativeLuminance(strok::Rgb{.r = 1, .g = 1, .b = 1}), "top-left sample 1");
  expectNear(top_left.at(0, 1), strok::relativeLuminance(strok::Rgb{.r = 4, .g = 4, .b = 4}), "top-left sample 4");
  expectNear(top_left.at(1, 1), strok::relativeLuminance(strok::Rgb{.r = 5, .g = 5, .b = 5}), "top-left sample 5");

  const auto bottom_right_uneven = strok::cellSourceRegion(5, 3, 2, 2, 1, 1);
  expect(bottom_right_uneven.x0 == 2 && bottom_right_uneven.x1 == 5, "uneven x range covers remainder");
  expect(bottom_right_uneven.y0 == 1 && bottom_right_uneven.y1 == 3, "uneven y range covers remainder");
  expect(bottom_right_uneven.width() == 3 && bottom_right_uneven.height() == 2, "uneven region size");
}
