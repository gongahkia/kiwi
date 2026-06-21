#include "video_decoder.hpp"

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <optional>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  const std::filesystem::path fixture = std::filesystem::path(CONTOURTTY_SOURCE_DIR) / "docs/v0.5-structure-demo.gif";
  contourtty::VideoDecoder decoder(fixture);
  const std::optional<contourtty::Frame> first = decoder.nextFrame();
  expect(first.has_value(), "first frame exists");
  expect(first->pts_us == 0, "first frame starts at zero");

  decoder.seekToUs(300000);
  const std::optional<contourtty::Frame> sought = decoder.nextFrame();
  expect(sought.has_value(), "sought frame exists");
  expect(sought->pts_us >= 300000, "seek returns requested-or-later frame");
  expect(sought->pts_us < 450000, "seek stays near requested timestamp");
  expect(sought->pts_us != first->pts_us, "seek skips earlier keyframe");

  const std::optional<contourtty::Frame> next = decoder.nextFrame();
  expect(next.has_value(), "next frame exists after pending seek frame");
  expect(next->pts_us > sought->pts_us, "decoder advances after pending seek frame");
}
