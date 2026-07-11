#include "luminance.hpp"

#include <array>
#include <cmath>
#include <cstdlib>
#include <iostream>

namespace {

void expectNear(double actual, double expected, double tolerance, const char* label) {
  if (std::abs(actual - expected) > tolerance) {
    std::cerr << label << ": expected " << expected << ", got " << actual << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  using strok::Rgb;
  expectNear(strok::relativeLuminance(Rgb{.r = 0, .g = 0, .b = 0}), 0.0, 1e-12, "black");
  expectNear(strok::relativeLuminance(Rgb{.r = 255, .g = 255, .b = 255}), 1.0, 1e-12, "white");
  expectNear(strok::relativeLuminance(Rgb{.r = 255, .g = 0, .b = 0}), 0.2126, 1e-12, "red");
  expectNear(strok::relativeLuminance(Rgb{.r = 0, .g = 255, .b = 0}), 0.7152, 1e-12, "green");
  expectNear(strok::relativeLuminance(Rgb{.r = 0, .g = 0, .b = 255}), 0.0722, 1e-12, "blue");
  expectNear(strok::relativeLuminance(Rgb{.r = 128, .g = 128, .b = 128}), 0.2158605, 1e-6, "mid gray linear");

  const std::array<Rgb, 2> samples {
    Rgb{.r = 0, .g = 0, .b = 0},
    Rgb{.r = 255, .g = 255, .b = 255},
  };
  expectNear(strok::cellLuminance(samples), 0.2158605, 1e-6, "averaged cell");
}
