#pragma once

#include "structure_edges.hpp"

#include <optional>

namespace contourtty {

bool gpuSobelAvailable();
std::optional<GradientField> computeSobelGradientsGpu(const LuminanceField& field);

}  // namespace contourtty
