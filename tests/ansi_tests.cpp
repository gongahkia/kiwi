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
  strok::appendSgrFg(out, strok::Rgb{.r = 1, .g = 2, .b = 3});
  expectEqual(out, "\x1b[38;2;1;2;3m", "fg sgr");

  out.clear();
  strok::appendSgrBg(out, strok::Rgb{.r = 4, .g = 5, .b = 6});
  expectEqual(out, "\x1b[48;2;4;5;6m", "bg sgr");

  out.clear();
  strok::appendSgrFg256(out, 196);
  strok::appendSgrBg256(out, 16);
  expectEqual(out, "\x1b[38;5;196m\x1b[48;5;16m", "256 sgr");

  out.clear();
  strok::appendSgrFg16(out, 9);
  strok::appendSgrBg16(out, 4);
  expectEqual(out, "\x1b[91m\x1b[44m", "16 sgr");

  out.clear();
  strok::appendCursorMove(out, 12, 34);
  expectEqual(out, "\x1b[12;34H", "cursor");

  out.clear();
  strok::appendUtf8(out, U'@');
  strok::appendUtf8(out, U'█');
  strok::appendSgrReset(out);
  expectEqual(out, "@\xe2\x96\x88\x1b[0m", "utf8 reset");
}
