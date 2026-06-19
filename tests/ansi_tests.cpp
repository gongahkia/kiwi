#include "ansi.hpp"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

void expectEqual(const std::string& actual, const std::string& expected, const char* label) {
  if (actual != expected) {
    std::cerr << label << ": expected size " << expected.size() << ", got size " << actual.size() << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  std::string out;
  contourtty::appendSgrFg(out, contourtty::Rgb{.r = 1, .g = 2, .b = 3});
  expectEqual(out, "\x1b[38;2;1;2;3m", "fg sgr");

  out.clear();
  contourtty::appendSgrBg(out, contourtty::Rgb{.r = 4, .g = 5, .b = 6});
  expectEqual(out, "\x1b[48;2;4;5;6m", "bg sgr");

  out.clear();
  contourtty::appendCursorMove(out, 12, 34);
  expectEqual(out, "\x1b[12;34H", "cursor");

  out.clear();
  contourtty::appendUtf8(out, U'@');
  contourtty::appendUtf8(out, U'█');
  contourtty::appendSgrReset(out);
  expectEqual(out, "@\xe2\x96\x88\x1b[0m", "utf8 reset");
}
