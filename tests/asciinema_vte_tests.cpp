#include "asciinema_vte.hpp"

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
    contourtty::AsciinemaVteScreen screen(5, 2);
    screen.applyOutput("hi");
    expect(screen.cells().at(0, 0).glyph == U'h', "plain text glyph 0");
    expect(screen.cells().at(1, 0).glyph == U'i', "plain text glyph 1");
    expect(screen.cursorCol() == 2 && screen.cursorRow() == 0, "plain text cursor");
  }

  {
    contourtty::AsciinemaVteScreen screen(5, 2);
    screen.applyOutput("abc\x1b[2;3H@");
    expect(screen.cells().at(2, 1).glyph == U'@', "cursor position writes target");
  }

  {
    contourtty::AsciinemaVteScreen screen(3, 2);
    screen.applyOutput("a\r\nb\r\nc");
    expect(screen.cells().at(0, 0).glyph == U'b', "scroll keeps previous bottom row");
    expect(screen.cells().at(0, 1).glyph == U'c', "scroll writes new bottom row");
  }

  {
    contourtty::AsciinemaVteScreen screen(3, 2);
    screen.applyOutput("abc\nz");
    expect(screen.cells().at(0, 1).glyph == U'z', "lf after full line starts next row");
  }

  {
    contourtty::AsciinemaVteScreen screen(4, 2);
    screen.applyOutput("abcd\x1b[2D\x1b[K");
    expect(screen.cells().at(0, 0).glyph == U'a', "clear line keeps prefix");
    expect(screen.cells().at(2, 0).glyph == U' ', "clear line clears cursor");
    expect(screen.cells().at(3, 0).glyph == U' ', "clear line clears suffix");
  }

  {
    contourtty::AsciinemaVteScreen screen(4, 2);
    screen.applyOutput("abcd\x1b[2J");
    expect(screen.cells().at(0, 0).glyph == U' ', "clear display resets first cell");
    expect(screen.cells().at(3, 0).glyph == U' ', "clear display resets last written cell");
    expect(screen.cursorCol() == 0 && screen.cursorRow() == 0, "clear display homes cursor");
  }

  {
    contourtty::AsciinemaVteScreen screen(3, 1);
    screen.applyOutput("\x1b[31mR\x1b[0mN");
    expect(screen.cells().at(0, 0).fg.r == 128, "sgr red foreground r");
    expect(screen.cells().at(0, 0).fg.g == 0, "sgr red foreground g");
    expect(screen.cells().at(1, 0).fg.r == 0, "sgr reset foreground");
  }

  {
    contourtty::AsciinemaVteScreen screen(3, 1);
    screen.applyOutput("\x1b[38;2;1;2;3mT");
    expect(screen.cells().at(0, 0).fg.r == 1, "truecolor sgr r");
    expect(screen.cells().at(0, 0).fg.g == 2, "truecolor sgr g");
    expect(screen.cells().at(0, 0).fg.b == 3, "truecolor sgr b");
  }
}
