#include "color_mode.hpp"

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
  expect(contourtty::detectColorMode("xterm-256color", nullptr, nullptr) == contourtty::ColorMode::Color256, "TERM 256 detected");
  expect(contourtty::detectColorMode("xterm", "truecolor", nullptr) == contourtty::ColorMode::Truecolor, "COLORTERM truecolor detected");
  expect(contourtty::detectColorMode("xterm", "24bit", nullptr) == contourtty::ColorMode::Truecolor, "COLORTERM 24bit detected");
  expect(contourtty::detectColorMode("vt100", nullptr, nullptr) == contourtty::ColorMode::Color16, "plain TERM falls back to 16");
  expect(contourtty::detectColorMode("xterm-256color", "truecolor", "1") == contourtty::ColorMode::Mono, "NO_COLOR forces mono");

  expect(contourtty::resolveColorMode("auto", "xterm-256color", nullptr, nullptr) == contourtty::ColorMode::Color256, "auto resolves");
  expect(contourtty::resolveColorMode("truecolor", "vt100", nullptr, nullptr) == contourtty::ColorMode::Truecolor, "truecolor override");
  expect(contourtty::resolveColorMode("256", "vt100", nullptr, nullptr) == contourtty::ColorMode::Color256, "256 override");
  expect(contourtty::resolveColorMode("16", "xterm-256color", "truecolor", nullptr) == contourtty::ColorMode::Color16, "16 override");
  expect(contourtty::resolveColorMode("mono", "xterm-256color", "truecolor", nullptr) == contourtty::ColorMode::Mono, "mono override");
  expect(contourtty::resolveColorMode("truecolor", "xterm-256color", "truecolor", "1") == contourtty::ColorMode::Mono, "NO_COLOR wins over override");

  expect(contourtty::emitsTruecolor(contourtty::ColorMode::Truecolor), "truecolor emits sgr color");
  expect(!contourtty::emitsTruecolor(contourtty::ColorMode::Color256), "256 color waits for quantization");
  expect(contourtty::colorModeName(contourtty::ColorMode::Color16) == "16", "mode name");
}
