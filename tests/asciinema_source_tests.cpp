#include "asciinema_source.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

int pixelR(const strok::Frame& frame, int x, int y) {
  return frame.rgb[(static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(x)) * 3U];
}

}  // namespace

int main() {
  {
    strok::AsciinemaFrameSource source = strok::AsciinemaFrameSource::fromString(
      "{\"version\":2,\"width\":4,\"height\":2}\n"
      "[0.100000,\"o\",\"hi\"]\n"
      "[0.200000,\"i\",\"ignored\"]\n"
      "[0.300000,\"o\",\"\\r\\nx\"]\n");
    expect(source.header().width == 4 && source.header().height == 2, "header preserved");

    const std::optional<strok::Frame> first = source.nextFrame();
    expect(first.has_value(), "first frame exists");
    expect(first->pts_us == 100000, "first frame pts");
    expect(first->w == 4 && first->h == 4, "frame doubles cell rows");
    expect(pixelR(*first, 0, 0) == 255, "plain text visible");
    expect(pixelR(*first, 3, 0) == 0, "blank cell dark");

    const std::optional<strok::Frame> second = source.nextFrame();
    expect(second.has_value(), "second frame exists");
    expect(second->pts_us == 300000, "second frame pts skips input event");
    expect(pixelR(*second, 0, 2) == 255, "second row text visible");
    expect(!source.nextFrame().has_value(), "source exhausted");

    source.restart();
    const std::optional<strok::Frame> restarted = source.nextFrame();
    expect(restarted.has_value() && restarted->pts_us == 100000, "restart resets event cursor");
  }

  {
    strok::AsciinemaFrameSource source = strok::AsciinemaFrameSource::fromString(
      "{\"version\":2,\"width\":2,\"height\":1}\n"
      "[0.000000,\"o\",\"\\u001b[31mR\"]\n");
    const std::optional<strok::Frame> frame = source.nextFrame();
    expect(frame.has_value(), "sgr frame exists");
    expect(pixelR(*frame, 0, 0) == 128, "sgr red maps through frame");
  }
}
