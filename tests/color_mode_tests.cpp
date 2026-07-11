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
  expect(strok::detectColorMode("xterm-256color", nullptr, nullptr) == strok::ColorMode::Color256, "TERM 256 detected");
  expect(strok::detectColorMode("xterm", "truecolor", nullptr) == strok::ColorMode::Truecolor, "COLORTERM truecolor detected");
  expect(strok::detectColorMode("xterm", "24bit", nullptr) == strok::ColorMode::Truecolor, "COLORTERM 24bit detected");
  expect(strok::detectColorMode("vt100", nullptr, nullptr) == strok::ColorMode::Color16, "plain TERM falls back to 16");
  expect(strok::detectColorMode("xterm-256color", "truecolor", "1") == strok::ColorMode::Mono, "NO_COLOR forces mono");

  expect(strok::resolveColorMode("auto", "xterm-256color", nullptr, nullptr) == strok::ColorMode::Color256, "auto resolves");
  expect(strok::resolveColorMode("truecolor", "vt100", nullptr, nullptr) == strok::ColorMode::Truecolor, "truecolor override");
  expect(strok::resolveColorMode("256", "vt100", nullptr, nullptr) == strok::ColorMode::Color256, "256 override");
  expect(strok::resolveColorMode("16", "xterm-256color", "truecolor", nullptr) == strok::ColorMode::Color16, "16 override");
  expect(strok::resolveColorMode("mono", "xterm-256color", "truecolor", nullptr) == strok::ColorMode::Mono, "mono override");
  expect(strok::resolveColorMode("truecolor", "xterm-256color", "truecolor", "1") == strok::ColorMode::Mono, "NO_COLOR wins over override");

  expect(strok::emitsTruecolor(strok::ColorMode::Truecolor), "truecolor emits sgr color");
  expect(!strok::emitsTruecolor(strok::ColorMode::Color256), "256 color waits for quantization");
  expect(strok::colorModeName(strok::ColorMode::Color16) == "16", "mode name");
}
