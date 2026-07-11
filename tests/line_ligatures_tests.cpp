#include "line_ligatures.hpp"

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
  {
    strok::CellBuffer cells(1, 3);
    cells.at(0, 0).glyph = U'|';
    cells.at(0, 1).glyph = U'|';
    cells.at(0, 2).glyph = U'|';
    strok::applyLineLigatures(&cells);
    expect(cells.at(0, 0).glyph == U'│', "vertical top joins");
    expect(cells.at(0, 1).glyph == U'│', "vertical middle joins");
    expect(cells.at(0, 2).glyph == U'│', "vertical bottom joins");
  }

  {
    strok::CellBuffer cells(3, 1);
    cells.at(0, 0).glyph = U'-';
    cells.at(1, 0).glyph = U'_';
    cells.at(2, 0).glyph = U'-';
    strok::applyLineLigatures(&cells);
    expect(cells.at(0, 0).glyph == U'─', "horizontal left joins");
    expect(cells.at(1, 0).glyph == U'─', "horizontal middle joins");
    expect(cells.at(2, 0).glyph == U'─', "horizontal right joins");
  }

  {
    strok::CellBuffer cells(2, 2);
    cells.at(0, 0).glyph = U'|';
    cells.at(1, 0).glyph = U' ';
    cells.at(0, 1).glyph = U'+';
    cells.at(1, 1).glyph = U'-';
    cells.at(0, 1).fg = strok::Rgb{.r = 1, .g = 2, .b = 3};
    strok::applyLineLigatures(&cells);
    expect(cells.at(0, 0).glyph == U'│', "corner stem joins");
    expect(cells.at(0, 1).glyph == U'└', "corner joins");
    expect(cells.at(1, 1).glyph == U'─', "corner arm joins");
    expect(cells.at(0, 1).fg.r == 1 && cells.at(0, 1).fg.g == 2 && cells.at(0, 1).fg.b == 3, "ligature preserves color");
  }
}
