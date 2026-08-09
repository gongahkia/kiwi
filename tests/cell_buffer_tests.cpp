#include "cell_buffer.hpp"

#include <cstdlib>
#include <iostream>
#include <utility>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  const strok::CellBuffer empty;
  expect(empty.cols() == 0 && empty.rows() == 0 && empty.size() == 0, "default buffer is empty");

  strok::CellBuffer buffer(4, 3);
  expect(buffer.cols() == 4, "cols");
  expect(buffer.rows() == 3, "rows");
  expect(buffer.size() == 12, "size");

  buffer.at(2, 1).glyph = U'#';
  buffer.at(2, 1).fg = strok::Rgb{.r = 1, .g = 2, .b = 3};
  expect(buffer.at(2, 1).glyph == U'#', "glyph write");
  expect(buffer.at(2, 1).fg.g == 2, "fg write");
  expect(&buffer.at(2, 1) == &buffer.cells()[6], "row-major indexing");

  const auto* storage = buffer.cells().data();
  buffer.resize(4, 3);
  expect(buffer.cells().data() == storage, "same-size resize reuses storage");
  expect(buffer.at(2, 1).glyph == U'#', "same-size resize preserves cells");

  buffer.resize(2, 2);
  expect(buffer.cols() == 2 && buffer.rows() == 2 && buffer.size() == 4, "resize dimensions");
  expect(buffer.at(0, 0).glyph == U' ', "new cells default");

  buffer.at(1, 1).glyph = U'界';
  const strok::CellBuffer copied = buffer;
  expect(copied.at(1, 1).glyph == U'界', "copy preserves Unicode code point");
  expect(copied == buffer, "equal cell buffers compare equal");
  buffer.at(1, 1).glyph = U'X';
  expect(copied.at(1, 1).glyph == U'界', "copy owns independent cells");
  expect(copied != buffer, "different cells compare unequal");
  strok::CellBuffer moved = std::move(buffer);
  expect(moved.cols() == 2 && moved.rows() == 2 && moved.at(1, 1).glyph == U'X', "move transfers cell buffer");
  expect(moved != strok::CellBuffer(1, 4), "dimensions participate in equality");

  bool threw = false;
  try {
    (void)buffer.at(2, 0);
  } catch (const std::out_of_range&) {
    threw = true;
  }
  expect(threw, "bounds check");
}
