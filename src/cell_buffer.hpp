#pragma once

#include "luminance.hpp"

#include <cstddef>
#include <stdexcept>
#include <vector>

namespace strok {

struct Cell {
  char32_t glyph = U' ';
  Rgb fg {};
  Rgb bg {};
};

class CellBuffer {
 public:
  CellBuffer() = default;
  CellBuffer(int cols, int rows) {
    resize(cols, rows);
  }

  void resize(int cols, int rows) {
    if (cols <= 0 || rows <= 0) {
      throw std::invalid_argument("cell buffer dimensions must be positive");
    }
    if (cols == cols_ && rows == rows_) {
      return;
    }
    cols_ = cols;
    rows_ = rows;
    cells_.assign(static_cast<std::size_t>(cols_) * static_cast<std::size_t>(rows_), Cell{});
  }

  int cols() const noexcept {
    return cols_;
  }

  int rows() const noexcept {
    return rows_;
  }

  std::size_t size() const noexcept {
    return cells_.size();
  }

  const std::vector<Cell>& cells() const noexcept {
    return cells_;
  }

  std::vector<Cell>& cells() noexcept {
    return cells_;
  }

  const Cell& at(int col, int row) const {
    return cells_.at(index(col, row));
  }

  Cell& at(int col, int row) {
    return cells_.at(index(col, row));
  }

 private:
  std::size_t index(int col, int row) const {
    if (col < 0 || row < 0 || col >= cols_ || row >= rows_) {
      throw std::out_of_range("cell index out of range");
    }
    return static_cast<std::size_t>(row) * static_cast<std::size_t>(cols_) + static_cast<std::size_t>(col);
  }

  int cols_ = 0;
  int rows_ = 0;
  std::vector<Cell> cells_;
};

}  // namespace strok
