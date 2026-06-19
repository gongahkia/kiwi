#include "gpu_sobel.hpp"

namespace contourtty {

bool gpuSobelAvailable() {
  return false;
}

std::optional<GradientField> computeSobelGradientsGpu(const LuminanceField&) {
  return std::nullopt;
}

}  // namespace contourtty
