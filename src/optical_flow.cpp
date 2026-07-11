#include "optical_flow.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <stdexcept>

namespace strok {
namespace {

void validateFieldPair(const LuminanceField& previous, const LuminanceField& current) {
  if (previous.width <= 0 || previous.height <= 0 ||
      previous.values.size() != static_cast<std::size_t>(previous.width) * static_cast<std::size_t>(previous.height)) {
    throw std::invalid_argument("invalid previous luminance field");
  }
  if (current.width != previous.width || current.height != previous.height ||
      current.values.size() != previous.values.size()) {
    throw std::invalid_argument("luminance fields must have matching dimensions");
  }
}

double sampleClamped(const LuminanceField& field, int x, int y) {
  const int sx = std::clamp(x, 0, field.width - 1);
  const int sy = std::clamp(y, 0, field.height - 1);
  return field.values[static_cast<std::size_t>(sy) * static_cast<std::size_t>(field.width) + static_cast<std::size_t>(sx)];
}

double blockSad(const LuminanceField& previous, const LuminanceField& current, int x0, int y0, int block_size, int dx, int dy) {
  double sad = 0.0;
  for (int y = 0; y < block_size; ++y) {
    for (int x = 0; x < block_size; ++x) {
      sad += std::abs(sampleClamped(previous, x0 + x, y0 + y) - sampleClamped(current, x0 + x + dx, y0 + y + dy));
    }
  }
  return sad;
}

FlowVector matchBlock(const LuminanceField& previous, const LuminanceField& current, int x0, int y0, int block_size, int search_radius) {
  FlowVector best{.error = std::numeric_limits<double>::infinity()};
  int best_distance = std::numeric_limits<int>::max();
  for (int dy = -search_radius; dy <= search_radius; ++dy) {
    for (int dx = -search_radius; dx <= search_radius; ++dx) {
      const double sad = blockSad(previous, current, x0, y0, block_size, dx, dy);
      const int distance = std::abs(dx) + std::abs(dy);
      if (sad < best.error - 1.0e-12 || (std::abs(sad - best.error) <= 1.0e-12 && distance < best_distance)) {
        best = FlowVector{.dx = static_cast<double>(dx), .dy = static_cast<double>(dy), .error = sad};
        best_distance = distance;
      }
    }
  }
  return best;
}

}  // namespace

FlowVector FlowField::at(int block_x, int block_y) const {
  if (block_x < 0 || block_y < 0 || block_x >= blocks_x || block_y >= blocks_y) {
    throw std::out_of_range("flow block index out of range");
  }
  return vectors.at(static_cast<std::size_t>(block_y) * static_cast<std::size_t>(blocks_x) + static_cast<std::size_t>(block_x));
}

FlowField computeBlockOpticalFlow(const LuminanceField& previous, const LuminanceField& current, int block_size, int search_radius) {
  validateFieldPair(previous, current);
  if (block_size <= 0 || search_radius < 0) {
    throw std::invalid_argument("invalid optical flow block/search size");
  }
  FlowField field;
  field.block_size = block_size;
  field.width = previous.width;
  field.height = previous.height;
  field.blocks_x = (previous.width + block_size - 1) / block_size;
  field.blocks_y = (previous.height + block_size - 1) / block_size;
  field.vectors.reserve(static_cast<std::size_t>(field.blocks_x) * static_cast<std::size_t>(field.blocks_y));
  for (int by = 0; by < field.blocks_y; ++by) {
    for (int bx = 0; bx < field.blocks_x; ++bx) {
      field.vectors.push_back(matchBlock(previous, current, bx * block_size, by * block_size, block_size, search_radius));
    }
  }
  return field;
}

}  // namespace strok
