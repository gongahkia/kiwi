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

struct DogOptions {
  double sigma1 = 0.0;
  double sigma2 = 0.0;
  double threshold = 0.0;

  bool enabled() const noexcept {
    return sigma1 > 0.0 && sigma2 > sigma1;
  }
};

LuminanceField gaussianBlur(const LuminanceField& field, double sigma);
LuminanceField differenceOfGaussians(const LuminanceField& field, DogOptions options);
GradientField computeSobelGradients(const LuminanceField& field);
CellGradient cellGradient(const GradientField& gradients, int cols, int rows, int col, int row);

}  // namespace contourtty
