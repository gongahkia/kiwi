#include "structure_edges.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <utility>
#include <vector>

namespace {

constexpr double kPi = 3.14159265358979323846;

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

void expectNear(double actual, double expected, double tolerance, const char* label) {
  if (std::abs(actual - expected) > tolerance) {
    std::cerr << label << ": expected " << expected << ", got " << actual << '\n';
    std::exit(1);
  }
}

contourtty::LuminanceField fieldFromValues(int width, int height, std::vector<double> values) {
  contourtty::LuminanceField field;
  field.width = width;
  field.height = height;
  field.values = std::move(values);
  return field;
}

}  // namespace

int main() {
  {
    std::vector<double> values;
    for (int y = 0; y < 5; ++y) {
      for (int x = 0; x < 5; ++x) {
        values.push_back(x < 2 ? 0.0 : 1.0);
      }
    }
    const auto gradients = contourtty::computeSobelGradients(fieldFromValues(5, 5, values));
    const auto cell = contourtty::cellGradient(gradients, 1, 1, 0, 0);
    expect(cell.gx > 0.0, "vertical edge has positive horizontal gradient");
    expect(std::abs(cell.gy) < 1e-12, "vertical edge gy near zero");
    expectNear(cell.orientation, 0.0, 1e-12, "vertical edge orientation");
    expect(cell.magnitude > 0.0, "vertical edge magnitude");
  }

  {
    std::vector<double> values;
    for (int y = 0; y < 5; ++y) {
      for (int x = 0; x < 5; ++x) {
        values.push_back(y < 2 ? 0.0 : 1.0);
      }
    }
    const auto gradients = contourtty::computeSobelGradients(fieldFromValues(5, 5, values));
    const auto cell = contourtty::cellGradient(gradients, 1, 1, 0, 0);
    expect(std::abs(cell.gx) < 1e-12, "horizontal edge gx near zero");
    expect(cell.gy > 0.0, "horizontal edge has positive vertical gradient");
    expectNear(cell.orientation, kPi / 2.0, 1e-12, "horizontal edge orientation");
    expect(cell.magnitude > 0.0, "horizontal edge magnitude");
  }

  {
    std::vector<double> values;
    for (int y = 0; y < 5; ++y) {
      for (int x = 0; x < 5; ++x) {
        values.push_back(x + y < 4 ? 0.0 : 1.0);
      }
    }
    const auto gradients = contourtty::computeSobelGradients(fieldFromValues(5, 5, values));
    const auto cell = contourtty::cellGradient(gradients, 1, 1, 0, 0);
    expect(cell.gx > 0.0 && cell.gy > 0.0, "diagonal edge gradient points down-right");
    expectNear(cell.orientation, kPi / 4.0, 0.15, "diagonal edge orientation");
  }
}
