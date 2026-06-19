#pragma once

#include "structure_sampling.hpp"

#include <vector>

namespace contourtty {

struct Gradient {
  double gx = 0.0;
  double gy = 0.0;
};

struct GradientField {
  int width = 0;
  int height = 0;
  std::vector<Gradient> values;

  Gradient at(int x, int y) const;
};

struct CellGradient {
  double gx = 0.0;
  double gy = 0.0;
  double magnitude = 0.0;
  double orientation = 0.0;
};

GradientField computeSobelGradients(const LuminanceField& field);
CellGradient cellGradient(const GradientField& gradients, int cols, int rows, int col, int row);

}  // namespace contourtty
