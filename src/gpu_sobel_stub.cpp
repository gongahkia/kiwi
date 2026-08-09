#include "gpu_sobel.hpp"

namespace strok {

std::unique_ptr<GpuSobelContext> createGpuSobelContext() {
  return nullptr;
}

bool gpuSobelAvailable() {
  return false;
}

const char* gpuSobelBackendName() {
  return "none";
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

}  // namespace strok
