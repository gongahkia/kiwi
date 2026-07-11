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
    const strok::Frame frame{
      .w = 2,
      .h = 1,
      .rgb = {255, 0, 0, 255, 0, 0},
    };
    expect(strok::summariseFrameCaption(frame) == "dark, low contrast, red dominant", "red frame summary");
  }

  {
    const strok::Frame frame{
      .w = 2,
      .h = 1,
      .rgb = {0, 0, 0, 255, 255, 255},
    };
    expect(strok::summariseFrameCaption(frame) == "mid-tone, high contrast, balanced color", "contrast frame summary");
  }

  expect(strok::formatSrtTimestamp(3723004000) == "01:02:03,004", "srt timestamp");
  expect(strok::formatSrtCue(2, 1000000, 2500000, "mid-tone").find("00:00:01,000 --> 00:00:02,500") != std::string::npos, "srt cue timing");

  {
    const strok::Frame red{
      .w = 2,
      .h = 1,
      .rgb = {255, 0, 0, 255, 0, 0},
    };
    const strok::Frame contrast{
      .w = 2,
      .h = 1,
      .rgb = {0, 0, 0, 255, 255, 255},
    };
    strok::CaptionSrtBuilder builder(200000);
    builder.recordFrame(red, 0);
    builder.recordFrame(contrast, 200000);
    const std::string expected =
      "1\n"
      "00:00:00,000 --> 00:00:00,200\n"
      "dark, low contrast, red dominant\n"
      "\n"
      "2\n"
      "00:00:00,200 --> 00:00:00,400\n"
      "mid-tone, high contrast, balanced color\n"
      "\n";
    expect(builder.finish() == expected, "caption track golden");
    expect(builder.cueCount() == 2, "caption track cue count");
    expect(builder.finish() == expected, "caption track finish idempotent");
  }

  {
    bool threw = false;
    try {
      (void)strok::summariseFrameCaption(strok::Frame{.w = 1, .h = 1, .rgb = {0, 0}});
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "invalid frame rejected");
  }
}
