#include "captions.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>

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
    const contourtty::Frame frame{
      .w = 2,
      .h = 1,
      .rgb = {255, 0, 0, 255, 0, 0},
    };
    expect(contourtty::summariseFrameCaption(frame) == "dark, low contrast, red dominant", "red frame summary");
  }

  {
    const contourtty::Frame frame{
      .w = 2,
      .h = 1,
      .rgb = {0, 0, 0, 255, 255, 255},
    };
    expect(contourtty::summariseFrameCaption(frame) == "mid-tone, high contrast, balanced color", "contrast frame summary");
  }

  expect(contourtty::formatSrtTimestamp(3723004000) == "01:02:03,004", "srt timestamp");
  expect(contourtty::formatSrtCue(2, 1000000, 2500000, "mid-tone").find("00:00:01,000 --> 00:00:02,500") != std::string::npos, "srt cue timing");

  {
    bool threw = false;
    try {
      (void)contourtty::summariseFrameCaption(contourtty::Frame{.w = 1, .h = 1, .rgb = {0, 0}});
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "invalid frame rejected");
  }
}
