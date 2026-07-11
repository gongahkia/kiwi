#include "posterize.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <stdexcept>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

void expectNear(double actual, double expected, double epsilon, const char* label) {
  if (std::abs(actual - expected) > epsilon) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

bool throwsInvalidLevels() {
  try {
    (void)strok::posterizeOklab(strok::Rgb{.r = 128, .g = 128, .b = 128}, 1);
  } catch (const std::invalid_argument&) {
    return true;
  }
  return false;
}

}  // namespace

int main() {
  const strok::Rgb gray{.r = 128, .g = 128, .b = 128};
  const strok::Oklab lab = strok::rgbToOklab(gray);
  const strok::Rgb round_trip = strok::oklabToRgb(lab);
  expect(std::abs(static_cast<int>(round_trip.r) - 128) <= 1, "OKLab gray round-trip red");
  expect(std::abs(static_cast<int>(round_trip.g) - 128) <= 1, "OKLab gray round-trip green");
  expect(std::abs(static_cast<int>(round_trip.b) - 128) <= 1, "OKLab gray round-trip blue");

  const strok::Rgb posterized = strok::posterizeOklab(gray, 4);
  const double l = strok::rgbToOklab(posterized).l;
  expectNear(l, std::round(l * 3.0) / 3.0, 0.01, "posterize snaps OKLab L to 4 levels");

  strok::Frame frame;
  frame.w = 2;
  frame.h = 1;
  frame.pts_us = 123;
  frame.rgb = {32, 32, 32, 220, 220, 220};
  const strok::Frame output = strok::posterizeFrameOklab(frame, 4);
  expect(output.w == 2 && output.h == 1 && output.pts_us == 123, "posterize preserves frame metadata");
  expect(output.rgb.size() == frame.rgb.size(), "posterize preserves frame buffer size");
  expect(output.rgb != frame.rgb, "posterize changes non-bucketed colors");
  expect(throwsInvalidLevels(), "posterize rejects invalid levels");
}
