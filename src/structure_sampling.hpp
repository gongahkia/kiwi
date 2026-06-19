#pragma once

#include "frame.hpp"

#include <cstddef>
#include <vector>

namespace contourtty {

struct SourceRegion {
  int x0 = 0;
  int x1 = 0;
  int y0 = 0;
  int y1 = 0;

  int width() const noexcept {
    return x1 - x0;
  }

  int height() const noexcept {
    return y1 - y0;
  }
};

struct LuminanceField {
  int width = 0;
  int height = 0;
  std::vector<double> values;

  double at(int x, int y) const;
};

struct CellLuminanceRegion {
  SourceRegion source;
  std::vector<double> values;

  int width() const noexcept {
    return source.width();
  }

  int height() const noexcept {
    return source.height();
  }

  double at(int x, int y) const;
};

LuminanceField makeLuminanceField(const Frame& frame);
SourceRegion cellSourceRegion(int source_width, int source_height, int cols, int rows, int col, int row);
CellLuminanceRegion sampleCellRegion(const LuminanceField& field, int cols, int rows, int col, int row);

}  // namespace contourtty
