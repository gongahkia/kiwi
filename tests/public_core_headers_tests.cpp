#include <strok/cell_buffer.hpp>

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  strok::CellBuffer cells(2, 1);
  cells.at(1, 0) = strok::Cell{
    .glyph = U'X',
    .fg = strok::Rgb{.r = 12, .g = 34, .b = 56},
    .bg = strok::Rgb{.r = 78, .g = 90, .b = 123},
  };

  expect(cells.cols() == 2 && cells.rows() == 1, "public CellBuffer dimensions");
  expect(cells.at(1, 0).glyph == U'X', "public Cell glyph");
  expect(cells.at(1, 0).fg.g == 34 && cells.at(1, 0).bg.b == 123, "public Cell colors");
}
