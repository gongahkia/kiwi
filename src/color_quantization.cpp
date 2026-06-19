#include "color_quantization.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <stdexcept>

namespace contourtty {
namespace {

constexpr std::array<int, 6> kXtermCubeLevels {0, 95, 135, 175, 215, 255};
constexpr std::array<Rgb, 16> kAnsi16Palette {{
  Rgb{.r = 0, .g = 0, .b = 0},
  Rgb{.r = 128, .g = 0, .b = 0},
  Rgb{.r = 0, .g = 128, .b = 0},
  Rgb{.r = 128, .g = 128, .b = 0},
  Rgb{.r = 0, .g = 0, .b = 128},
  Rgb{.r = 128, .g = 0, .b = 128},
  Rgb{.r = 0, .g = 128, .b = 128},
  Rgb{.r = 192, .g = 192, .b = 192},
  Rgb{.r = 128, .g = 128, .b = 128},
  Rgb{.r = 255, .g = 0, .b = 0},
  Rgb{.r = 0, .g = 255, .b = 0},
  Rgb{.r = 255, .g = 255, .b = 0},
  Rgb{.r = 0, .g = 0, .b = 255},
  Rgb{.r = 255, .g = 0, .b = 255},
  Rgb{.r = 0, .g = 255, .b = 255},
  Rgb{.r = 255, .g = 255, .b = 255},
}};
constexpr int kBayer4[4][4] {
  {0, 8, 2, 10},
  {12, 4, 14, 6},
  {3, 11, 1, 9},
  {15, 7, 13, 5},
};

int distanceSquared(Rgb lhs, Rgb rhs) noexcept {
  const int dr = static_cast<int>(lhs.r) - static_cast<int>(rhs.r);
  const int dg = static_cast<int>(lhs.g) - static_cast<int>(rhs.g);
  const int db = static_cast<int>(lhs.b) - static_cast<int>(rhs.b);
  return dr * dr + dg * dg + db * db;
}

int nearestCubeLevel(uint8_t value) noexcept {
  int best = 0;
  int best_distance = 256;
  for (int i = 0; i < static_cast<int>(kXtermCubeLevels.size()); ++i) {
    const int distance = std::abs(static_cast<int>(value) - kXtermCubeLevels[static_cast<std::size_t>(i)]);
    if (distance < best_distance) {
      best = i;
      best_distance = distance;
    }
  }
  return best;
}

uint8_t clampChannel(int value) noexcept {
  return static_cast<uint8_t>(std::clamp(value, 0, 255));
}

}  // namespace

DitherMode ditherModeFromString(const std::string& value) {
  if (value == "none") {
    return DitherMode::None;
  }
  if (value == "ordered") {
    return DitherMode::Ordered;
  }
  if (value == "fs") {
    return DitherMode::FloydSteinberg;
  }
  throw std::invalid_argument("unknown dither mode");
}

Rgb applyOrderedDither(Rgb color, int row, int col, int amplitude) {
  const int threshold = kBayer4[row & 3][col & 3] - 8;
  const int delta = threshold * amplitude / 8;
  return Rgb{
    .r = clampChannel(static_cast<int>(color.r) + delta),
    .g = clampChannel(static_cast<int>(color.g) + delta),
    .b = clampChannel(static_cast<int>(color.b) + delta),
  };
}

uint8_t quantizeXterm256(Rgb color) {
  const int r = nearestCubeLevel(color.r);
  const int g = nearestCubeLevel(color.g);
  const int b = nearestCubeLevel(color.b);
  const Rgb cube_color {
    .r = static_cast<uint8_t>(kXtermCubeLevels[static_cast<std::size_t>(r)]),
    .g = static_cast<uint8_t>(kXtermCubeLevels[static_cast<std::size_t>(g)]),
    .b = static_cast<uint8_t>(kXtermCubeLevels[static_cast<std::size_t>(b)]),
  };
  uint8_t best_index = static_cast<uint8_t>(16 + 36 * r + 6 * g + b);
  int best_distance = distanceSquared(color, cube_color);

  for (int i = 0; i < 24; ++i) {
    const uint8_t gray = static_cast<uint8_t>(8 + i * 10);
    const Rgb gray_color{.r = gray, .g = gray, .b = gray};
    const int distance = distanceSquared(color, gray_color);
    if (distance < best_distance) {
      best_index = static_cast<uint8_t>(232 + i);
      best_distance = distance;
    }
  }
  return best_index;
}

uint8_t quantizeAnsi16(Rgb color) {
  uint8_t best_index = 0;
  int best_distance = distanceSquared(color, kAnsi16Palette[0]);
  for (uint8_t i = 1; i < kAnsi16Palette.size(); ++i) {
    const int distance = distanceSquared(color, kAnsi16Palette[i]);
    if (distance < best_distance) {
      best_index = i;
      best_distance = distance;
    }
  }
  return best_index;
}

Rgb xterm256Color(uint8_t index) {
  if (index < 16) {
    return kAnsi16Palette[index];
  }
  if (index < 232) {
    const int offset = static_cast<int>(index) - 16;
    const int r = offset / 36;
    const int g = (offset / 6) % 6;
    const int b = offset % 6;
    return Rgb{
      .r = static_cast<uint8_t>(kXtermCubeLevels[static_cast<std::size_t>(r)]),
      .g = static_cast<uint8_t>(kXtermCubeLevels[static_cast<std::size_t>(g)]),
      .b = static_cast<uint8_t>(kXtermCubeLevels[static_cast<std::size_t>(b)]),
    };
  }
  const uint8_t gray = static_cast<uint8_t>(8 + (static_cast<int>(index) - 232) * 10);
  return Rgb{.r = gray, .g = gray, .b = gray};
}

Rgb ansi16Color(uint8_t index) {
  return kAnsi16Palette[index % kAnsi16Palette.size()];
}

}  // namespace contourtty
