#include "gpu_sobel.hpp"

#include "glyph_shape.hpp"
#include "luminance.hpp"
#include "structure_edges.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
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
    std::cerr << label << ": actual=" << actual << " expected=" << expected << '\n';
    std::exit(1);
  }
}

strok::LuminanceField fieldFromValues(int width, int height, const std::vector<double>& values) {
  return strok::LuminanceField{.width = width, .height = height, .values = values};
}

}  // namespace

int main() {
  std::unique_ptr<strok::GpuSobelContext> context = strok::createGpuSobelContext();
  if (!context) {
    std::cout << "Vulkan backend unavailable; skipping Vulkan backend smoke\n";
    return 77;
  }

  const strok::LuminanceField field = fieldFromValues(5, 5, {
    0.0, 0.0, 1.0, 0.0, 0.0,
    0.0, 0.2, 1.0, 0.2, 0.0,
    0.0, 0.4, 1.0, 0.4, 0.0,
    0.0, 0.2, 1.0, 0.2, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0,
  });

  const auto cpu_gradients = strok::computeSobelGradients(field);
  const auto gpu_gradients = context->sobelGradients(field);
  expect(gpu_gradients.has_value(), "Vulkan Sobel result");
  expect(gpu_gradients->values.size() == cpu_gradients.values.size(), "Vulkan Sobel value count");
  for (std::size_t index = 0; index < cpu_gradients.values.size(); ++index) {
    expectNear(gpu_gradients->values[index].gx, cpu_gradients.values[index].gx, 1e-5, "Vulkan Sobel gx");
    expectNear(gpu_gradients->values[index].gy, cpu_gradients.values[index].gy, 1e-5, "Vulkan Sobel gy");
  }
  const auto repeated_gradients = context->sobelGradients(field);
  expect(repeated_gradients.has_value(), "persistent Vulkan Sobel result");
  expect(repeated_gradients->values.size() == gpu_gradients->values.size(), "persistent Vulkan Sobel value count");

  const strok::DogOptions dog_options{.sigma1 = 0.5, .sigma2 = 1.4, .threshold = 0.02};
  const auto cpu_dog = strok::differenceOfGaussians(field, dog_options);
  const auto gpu_dog = context->differenceOfGaussians(field, dog_options);
  expect(gpu_dog.has_value(), "Vulkan DoG result");
  expect(gpu_dog->values.size() == cpu_dog.values.size(), "Vulkan DoG value count");
  for (std::size_t index = 0; index < cpu_dog.values.size(); ++index) {
    expectNear(gpu_dog->values[index], cpu_dog.values[index], 1e-5, "Vulkan DoG value");
  }

  const strok::GlyphShapeTable table = strok::buildGlyphShapeTable(strok::kDefaultStructureShapeGlyphs, 5, 5);
  const auto gpu_glyphs = context->structureGlyphs(field, 5, 5, 0.02, &table);
  expect(gpu_glyphs.has_value(), "Vulkan structure glyph result");
  expect(gpu_glyphs->glyphs.size() == 25U, "Vulkan structure glyph count");
  expect(gpu_glyphs->shape_match_cells > 0, "Vulkan structure shape cells");
  const std::u32string glyphs(gpu_glyphs->glyphs.begin(), gpu_glyphs->glyphs.end());
  expect(glyphs.find(U'|') != std::u32string::npos || glyphs.find(U'+') != std::u32string::npos, "Vulkan structure edge glyph");

  context.reset();
  expect(strok::createGpuSobelContext() != nullptr, "Vulkan context recreates after renderer-owned teardown");
}
