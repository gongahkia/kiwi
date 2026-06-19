#include "gpu_sobel.hpp"
#include "structure_edges.hpp"

#include <cmath>
#include <cstddef>
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
    const auto glyph = contourtty::directionalGlyphForGradient(cell, 0.01);
    expect(glyph.has_value() && *glyph == U'|', "vertical edge maps to vertical glyph");
  }

  {
    std::vector<double> values;
    for (int y = 0; y < 8; ++y) {
      for (int x = 0; x < 8; ++x) {
        values.push_back(static_cast<double>((x * 17 + y * 23) % 31) / 30.0);
      }
    }
    const auto field = fieldFromValues(8, 8, values);
    const auto cpu = contourtty::computeSobelGradients(field);
    const auto gpu = contourtty::computeSobelGradientsGpu(field);
    expect(gpu.has_value() == contourtty::gpuSobelAvailable(), "gpu sobel availability matches result");
    if (gpu.has_value()) {
      expect(gpu->width == cpu.width && gpu->height == cpu.height, "gpu sobel dimensions");
      expect(gpu->values.size() == cpu.values.size(), "gpu sobel value count");
      for (std::size_t index = 0; index < cpu.values.size(); ++index) {
        expectNear(gpu->values[index].gx, cpu.values[index].gx, 1e-5, "gpu sobel gx");
        expectNear(gpu->values[index].gy, cpu.values[index].gy, 1e-5, "gpu sobel gy");
      }
    }
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
    const auto glyph = contourtty::directionalGlyphForGradient(cell, 0.01);
    expect(glyph.has_value() && *glyph == U'_', "positive horizontal edge maps to low horizontal glyph");
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
    const auto glyph = contourtty::directionalGlyphForGradient(cell, 0.01);
    expect(glyph.has_value() && *glyph == U'/', "positive diagonal edge maps to slash glyph");
  }

  {
    const auto glyph = contourtty::directionalGlyphForGradient(
      contourtty::CellGradient{
        .gx = 1.0,
        .gy = -1.0,
        .magnitude = std::sqrt(2.0),
        .orientation = -kPi / 4.0,
        .horizontal_energy = 1.0,
        .vertical_energy = 1.0,
      },
      0.01);
    expect(glyph.has_value() && *glyph == U'\\', "negative diagonal edge maps to backslash glyph");
  }

  {
    const auto glyph = contourtty::directionalGlyphForGradient(
      contourtty::CellGradient{
        .gx = 0.55,
        .gy = 0.55,
        .magnitude = std::hypot(0.55, 0.55),
        .orientation = kPi / 4.0,
        .horizontal_energy = 1.0,
        .vertical_energy = 1.0,
      },
      0.2);
    expect(glyph.has_value() && *glyph == U'+', "mixed strong axes map to plus glyph");
  }

  {
    const auto glyph = contourtty::directionalGlyphForGradient(
      contourtty::CellGradient{
        .gx = 0.01,
        .gy = 0.0,
        .magnitude = 0.01,
        .orientation = 0.0,
        .horizontal_energy = 0.01,
        .vertical_energy = 0.0,
      },
      0.2);
    expect(!glyph.has_value(), "weak edge falls back to luminance glyph");
  }

  {
    auto flat = fieldFromValues(5, 5, std::vector<double>(25, 0.5));
    const auto dog = contourtty::differenceOfGaussians(flat, contourtty::DogOptions{.sigma1 = 0.6, .sigma2 = 1.2, .threshold = 0.01});
    for (const double value : dog.values) {
      expectNear(value, 0.0, 1e-12, "flat DoG suppresses constant field");
    }
  }

  {
    std::vector<double> impulse(25, 0.0);
    impulse[12] = 1.0;
    auto field = fieldFromValues(5, 5, impulse);
    const auto dog = contourtty::differenceOfGaussians(field, contourtty::DogOptions{.sigma1 = 0.5, .sigma2 = 1.4, .threshold = 0.02});
    expect(dog.at(2, 2) > 0.0, "DoG keeps isolated line/point response above threshold");
    expectNear(dog.at(0, 0), 0.0, 1e-12, "DoG thresholds weak far response");
  }

  {
    auto field = fieldFromValues(2, 1, {0.45, 0.55});
    const auto off = contourtty::applyStructureContrast(field, 0.0);
    expectNear(off.at(0, 0), 0.45, 1e-12, "zero contrast preserves low value");
    expectNear(off.at(1, 0), 0.55, 1e-12, "zero contrast preserves high value");
    const auto boosted = contourtty::applyStructureContrast(field, 2.0);
    expect(boosted.at(0, 0) < 0.45, "contrast pushes low value lower");
    expect(boosted.at(1, 0) > 0.55, "contrast pushes high value higher");
    expect(boosted.at(1, 0) - boosted.at(0, 0) > 0.10, "contrast increases separation");
  }

  {
    contourtty::GradientField gradients;
    gradients.width = 2;
    gradients.height = 1;
    gradients.values = {
      contourtty::Gradient{.gx = 3.0, .gy = 4.0},
      contourtty::Gradient{.gx = 0.1, .gy = 0.0},
    };
    const auto magnitudes = contourtty::gradientMagnitudeField(gradients, 1.0);
    expectNear(magnitudes.at(0, 0), 5.0, 1e-12, "gradient magnitude retained above threshold");
    expectNear(magnitudes.at(1, 0), 0.0, 1e-12, "gradient magnitude suppressed below threshold");
  }
}
