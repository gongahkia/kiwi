#include "gpu_sobel.hpp"

namespace contourtty {

bool gpuSobelAvailable() {
  return false;
}

std::optional<LuminanceField> differenceOfGaussiansGpu(const LuminanceField&, DogOptions) {
  return std::nullopt;
}

std::optional<GradientField> computeSobelGradientsGpu(const LuminanceField&) {
  return std::nullopt;
}

std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const LuminanceField&, int, int, double, const GlyphShapeTable*) {
  return std::nullopt;
}

std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const Frame&, const LuminanceField&, int, int, double, const GlyphShapeTable*) {
  return std::nullopt;
}

}  // namespace contourtty
