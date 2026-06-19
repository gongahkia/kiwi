#include "cell_buffer.hpp"

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
  contourtty::CellBuffer buffer(4, 3);
  expect(buffer.cols() == 4, "cols");
  expect(buffer.rows() == 3, "rows");
  expect(buffer.size() == 12, "size");

  buffer.at(2, 1).glyph = U'#';
  buffer.at(2, 1).fg = contourtty::Rgb{.r = 1, .g = 2, .b = 3};
  expect(buffer.at(2, 1).glyph == U'#', "glyph write");
  expect(buffer.at(2, 1).fg.g == 2, "fg write");

  const auto* storage = buffer.cells().data();
  buffer.resize(4, 3);
  expect(buffer.cells().data() == storage, "same-size resize reuses storage");
  expect(buffer.at(2, 1).glyph == U'#', "same-size resize preserves cells");

  buffer.resize(2, 2);
  expect(buffer.cols() == 2 && buffer.rows() == 2 && buffer.size() == 4, "resize dimensions");
  expect(buffer.at(0, 0).glyph == U' ', "new cells default");

  bool threw = false;
  try {
    (void)buffer.at(2, 0);
  } catch (...) {
    threw = true;
  }
  expect(threw, "bounds check");
}
