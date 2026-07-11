#pragma once

#include "structure_edges.hpp"

namespace strok {

GradientField smoothEtfGradients(const GradientField& gradients, int iterations);
LuminanceField coherentLineField(const GradientField& gradients, double threshold);

}  // namespace strok
