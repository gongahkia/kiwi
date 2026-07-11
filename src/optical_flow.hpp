#pragma once

#include "structure_sampling.hpp"

#include <vector>

namespace strok {

struct FlowVector {
  double dx = 0.0;
  double dy = 0.0;
  double error = 0.0;
};

struct FlowField {
  int block_size = 0;
  int width = 0;
  int height = 0;
  int blocks_x = 0;
  int blocks_y = 0;
  std::vector<FlowVector> vectors;

  FlowVector at(int block_x, int block_y) const;
};

FlowField computeBlockOpticalFlow(const LuminanceField& previous, const LuminanceField& current, int block_size = 8, int search_radius = 8);

}  // namespace strok
