#include "etf.hpp"

#include <cmath>
#include <cstdlib>
#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

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

contourtty::GradientField gradientsFromValues(int width, int height, std::vector<contourtty::Gradient> values) {
  contourtty::GradientField gradients;
  gradients.width = width;
  gradients.height = height;
  gradients.values = std::move(values);
  return gradients;
}

bool throwsInvalid(const std::function<void()>& body) {
  try {
    body();
  } catch (const std::invalid_argument&) {
    return true;
  }
  return false;
}

}  // namespace

int main() {
  {
    auto gradients = gradientsFromValues(3, 3, std::vector<contourtty::Gradient>(9, contourtty::Gradient{.gx = 2.0, .gy = 0.0}));
    const auto smoothed = contourtty::smoothEtfGradients(gradients, 4);
    for (const contourtty::Gradient gradient : smoothed.values) {
      expectNear(gradient.gx, 2.0, 1e-12, "uniform ETF preserves gx");
      expectNear(gradient.gy, 0.0, 1e-12, "uniform ETF preserves gy");
    }
  }

  {
    std::vector<contourtty::Gradient> values(9, contourtty::Gradient{.gx = 2.0, .gy = 0.0});
    values[4] = contourtty::Gradient{.gx = 1.0, .gy = 1.0};
    auto gradients = gradientsFromValues(3, 3, std::move(values));
    const auto smoothed = contourtty::smoothEtfGradients(gradients, 2);
    expect(std::abs(smoothed.values[4].gy) < 0.25, "ETF smooths noisy center orientation");
    expect(smoothed.values[4].gx > 1.35, "ETF keeps center magnitude while aligning orientation");
  }

  {
    auto gradients = gradientsFromValues(2, 1, {
      contourtty::Gradient{.gx = 0.5, .gy = 0.5},
      contourtty::Gradient{.gx = 2.0, .gy = 0.0},
    });
    const auto unchanged = contourtty::smoothEtfGradients(gradients, 0);
    expectNear(unchanged.values[0].gx, 0.5, 1e-12, "zero ETF iterations preserve gx");
    expectNear(unchanged.values[0].gy, 0.5, 1e-12, "zero ETF iterations preserve gy");
    expectNear(unchanged.values[1].gx, 2.0, 1e-12, "zero ETF iterations preserve neighbor gx");
  }

  {
    std::vector<contourtty::Gradient> values(9, contourtty::Gradient{});
    values[1] = contourtty::Gradient{.gx = 2.0, .gy = 0.0};
    values[4] = contourtty::Gradient{.gx = 2.0, .gy = 0.0};
    values[7] = contourtty::Gradient{.gx = 2.0, .gy = 0.0};
    auto gradients = gradientsFromValues(3, 3, std::move(values));
    const auto lines = contourtty::coherentLineField(gradients, 0.5);
    expect(lines.values[4] > 1.0, "CLD keeps coherent tangent line");
    expectNear(lines.values[3], 0.0, 1e-12, "CLD suppresses weak off-line cell");
  }

  {
    auto gradients = gradientsFromValues(1, 1, {contourtty::Gradient{.gx = 1.0, .gy = 0.0}});
    expect(throwsInvalid([&] { (void)contourtty::smoothEtfGradients(gradients, -1); }), "ETF rejects negative iterations");
    expect(throwsInvalid([&] { (void)contourtty::coherentLineField(gradients, -0.1); }), "CLD rejects negative threshold");
  }
}
