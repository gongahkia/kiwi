#pragma once

#include "color.hpp"

#include <cstddef>
#include <stdexcept>
#include <vector>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
// A terminal-independent reconstructed cell. glyph stores one Unicode code point in
// char32_t; callers must provide a Unicode scalar value. Width, encoding, combining,
// and terminal cursor behavior are presentation concerns and are not represented here.
struct Cell {
  char32_t glyph = U' ';
  Rgb fg {};
  Rgb bg {};

  bool operator==(const Cell&) const = default;
};

// An owning, contiguous row-major grid of cells. Copying duplicates cells; moving
// transfers its storage, leaving the source valid with unspecified value. A default
// buffer is empty. resize requires positive dimensions; changing dimensions resets all
// cells to their defaults, while resizing to the same dimensions preserves storage and
// contents. at(col, row) uses zero-based coordinates and throws std::out_of_range when
// either coordinate is outside [0, cols) x [0, rows). cells()[row * cols() + col]
// addresses the same cell for valid coordinates. Equality compares dimensions and every
// Cell value in row-major order exactly.
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

  bool operator==(const CellBuffer&) const = default;

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
