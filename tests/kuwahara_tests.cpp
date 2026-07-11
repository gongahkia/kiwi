#include "kuwahara.hpp"

#include "luminance.hpp"

#include <cstdlib>
#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::Frame frameFromPixels(int width, int height, const std::vector<strok::Rgb>& pixels) {
  strok::Frame frame;
  frame.w = width;
  frame.h = height;
  frame.rgb.reserve(pixels.size() * 3U);
  for (const strok::Rgb pixel : pixels) {
    frame.rgb.push_back(pixel.r);
    frame.rgb.push_back(pixel.g);
    frame.rgb.push_back(pixel.b);
  }
  return frame;
}

strok::Rgb pixelAt(const strok::Frame& frame, int x, int y) {
  const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(x)) * 3U;
  return strok::Rgb{.r = frame.rgb[index], .g = frame.rgb[index + 1], .b = frame.rgb[index + 2]};
}

strok::Rgb gray(uint8_t value) {
  return strok::Rgb{.r = value, .g = value, .b = value};
}

bool throwsInvalid(const std::function<void()>& body) {
  try {
    body();
  } catch (const std::invalid_argument&) {
    return true;
  }
  return false;
}

}  // namespace

int main() {
  {
    const auto frame = frameFromPixels(3, 3, std::vector<strok::Rgb>(9, strok::Rgb{.r = 30, .g = 60, .b = 90}));
    const auto filtered = strok::applyKuwaharaFilter(frame, 2);
    expect(filtered.rgb == frame.rgb, "Kuwahara preserves flat regions");
  }

  {
    std::vector<strok::Rgb> pixels;
    for (int y = 0; y < 5; ++y) {
      for (int x = 0; x < 5; ++x) {
        pixels.push_back(x < 2 ? gray(0) : gray(255));
      }
    }
    const auto filtered = strok::applyKuwaharaFilter(frameFromPixels(5, 5, pixels), 2);
    expect(pixelAt(filtered, 1, 2).r < 80, "Kuwahara keeps dark side of edge");
    expect(pixelAt(filtered, 3, 2).r > 175, "Kuwahara keeps light side of edge");
  }

  {
    std::vector<strok::Rgb> pixels(25, gray(100));
    pixels[12] = gray(220);
    const auto filtered = strok::applyKuwaharaFilter(frameFromPixels(5, 5, pixels), 2);
    const auto center = pixelAt(filtered, 2, 2);
    expect(center.r < 150, "Kuwahara flattens isolated center noise");
  }

  {
    const auto frame = frameFromPixels(1, 1, {gray(100)});
    expect(throwsInvalid([&] { (void)strok::applyKuwaharaFilter(frame, 0); }), "Kuwahara rejects zero radius");
    expect(throwsInvalid([&] { (void)strok::applyKuwaharaFilter(frame, 9); }), "Kuwahara rejects excessive radius");
  }
}
