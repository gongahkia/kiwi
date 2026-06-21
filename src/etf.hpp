#pragma once

#include "structure_edges.hpp"

namespace contourtty {

GradientField smoothEtfGradients(const GradientField& gradients, int iterations);
LuminanceField coherentLineField(const GradientField& gradients, double threshold);

}  // namespace contourtty
