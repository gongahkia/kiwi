#include "sixel.hpp"

#include "color_quantization.hpp"
#include "posterize.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace strok {
namespace {

struct PaletteColor {
  uint8_t index = 0;
  Rgb rgb {};
  Oklab lab {};
};

std::size_t checkedRgbByteCount(int width, int height) {
  if (width <= 0 || height <= 0) {
    throw std::invalid_argument("sixel image dimensions must be positive");
  }
  const std::size_t w = static_cast<std::size_t>(width);
  const std::size_t h = static_cast<std::size_t>(height);
  if (w > std::numeric_limits<std::size_t>::max() / h / 3U) {
    throw std::invalid_argument("sixel image dimensions overflow");
  }
  return w * h * 3U;
}

double distanceSquared(Oklab lhs, Oklab rhs) noexcept {
  const double dl = lhs.l - rhs.l;
  const double da = lhs.a - rhs.a;
  const double db = lhs.b - rhs.b;
  return dl * dl + da * da + db * db;
}

const std::array<PaletteColor, 256>& sixelPalette() {
  static const std::array<PaletteColor, 256> palette = [] {
    std::array<PaletteColor, 256> colors {};
    for (std::size_t index = 0; index < colors.size(); ++index) {
      const Rgb rgb = xterm256Color(static_cast<uint8_t>(index));
      colors[index] = PaletteColor{
        .index = static_cast<uint8_t>(index),
        .rgb = rgb,
        .lab = rgbToOklab(rgb),
      };
    }
    return colors;
  }();
  return palette;
}

uint8_t nearestPaletteIndex(Rgb rgb) {
  const Oklab lab = rgbToOklab(rgb);
  const auto& palette = sixelPalette();
  uint8_t best = 0;
  double best_distance = distanceSquared(lab, palette[0].lab);
  for (std::size_t index = 1; index < palette.size(); ++index) {
    const double distance = distanceSquared(lab, palette[index].lab);
    if (distance < best_distance) {
      best_distance = distance;
      best = static_cast<uint8_t>(index);
    }
  }
  return best;
}

int percent(uint8_t value) noexcept {
  return std::clamp(static_cast<int>(std::lround(static_cast<double>(value) * 100.0 / 255.0)), 0, 100);
}

void appendRun(std::string* out, char ch, int count) {
  if (count <= 0) {
    return;
  }
  if (count >= 4) {
    *out += '!';
    *out += std::to_string(count);
    *out += ch;
    return;
  }
  out->append(static_cast<std::size_t>(count), ch);
}

}  // namespace

SixelImage quantizeSixelOklab(std::span<const uint8_t> rgb, int width, int height) {
  const std::size_t expected = checkedRgbByteCount(width, height);
  if (rgb.size() != expected) {
    throw std::invalid_argument("sixel RGB24 payload size does not match dimensions");
  }

  SixelImage image;
  image.width = width;
  image.height = height;
  image.palette_indices.resize(static_cast<std::size_t>(width) * static_cast<std::size_t>(height));
  image.palette_rgb.assign(256U * 3U, 0);

  const auto& palette = sixelPalette();
  for (const PaletteColor& color : palette) {
    const std::size_t offset = static_cast<std::size_t>(color.index) * 3U;
    image.palette_rgb[offset] = color.rgb.r;
    image.palette_rgb[offset + 1U] = color.rgb.g;
    image.palette_rgb[offset + 2U] = color.rgb.b;
  }

  std::unordered_map<uint32_t, uint8_t> cache;
  cache.reserve(256);
  for (std::size_t offset = 0, pixel = 0; offset < rgb.size(); offset += 3U, ++pixel) {
    const uint32_t key = (static_cast<uint32_t>(rgb[offset]) << 16U) |
                         (static_cast<uint32_t>(rgb[offset + 1U]) << 8U) |
                         static_cast<uint32_t>(rgb[offset + 2U]);
    auto found = cache.find(key);
    if (found == cache.end()) {
      const uint8_t index = nearestPaletteIndex(Rgb{.r = rgb[offset], .g = rgb[offset + 1U], .b = rgb[offset + 2U]});
      found = cache.emplace(key, index).first;
    }
    image.palette_indices[pixel] = found->second;
  }
  return image;
}

std::string encodeSixelRgb24(std::span<const uint8_t> rgb, int width, int height) {
  const SixelImage image = quantizeSixelOklab(rgb, width, height);
  std::vector<bool> used(256, false);
  for (const uint8_t index : image.palette_indices) {
    used[index] = true;
  }

  std::string out;
  out.reserve(rgb.size());
  out += "\x1bPq";
  for (int index = 0; index < 256; ++index) {
    if (!used[static_cast<std::size_t>(index)]) {
      continue;
    }
    const std::size_t offset = static_cast<std::size_t>(index) * 3U;
    out += '#';
    out += std::to_string(index);
    out += ";2;";
    out += std::to_string(percent(image.palette_rgb[offset]));
    out += ';';
    out += std::to_string(percent(image.palette_rgb[offset + 1U]));
    out += ';';
    out += std::to_string(percent(image.palette_rgb[offset + 2U]));
  }

  const std::size_t w = static_cast<std::size_t>(image.width);
  for (int band_y = 0; band_y < image.height; band_y += 6) {
    bool emitted_color = false;
    for (int color = 0; color < 256; ++color) {
      if (!used[static_cast<std::size_t>(color)]) {
        continue;
      }
      std::string line;
      line.reserve(static_cast<std::size_t>(image.width));
      char run_char = '\0';
      int run_count = 0;
      bool has_pixels = false;
      for (int x = 0; x < image.width; ++x) {
        int bits = 0;
        for (int bit = 0; bit < 6; ++bit) {
          const int y = band_y + bit;
          if (y >= image.height) {
            continue;
          }
          const std::size_t pixel = static_cast<std::size_t>(y) * w + static_cast<std::size_t>(x);
          if (image.palette_indices[pixel] == static_cast<uint8_t>(color)) {
            bits |= 1 << bit;
          }
        }
        const char ch = static_cast<char>('?' + bits);
        if (bits != 0) {
          has_pixels = true;
        }
        if (run_count == 0) {
          run_char = ch;
          run_count = 1;
        } else if (run_char == ch) {
          ++run_count;
        } else {
          appendRun(&line, run_char, run_count);
          run_char = ch;
          run_count = 1;
        }
      }
      appendRun(&line, run_char, run_count);
      if (!has_pixels) {
        continue;
      }
      out += '#';
      out += std::to_string(color);
      out += line;
      out += '$';
      emitted_color = true;
    }
    if (emitted_color && !out.empty() && out.back() == '$') {
      out.back() = '-';
    } else {
      out += '-';
    }
  }
  if (!out.empty() && out.back() == '-') {
    out.pop_back();
  }
  out += "\x1b\\";
  return out;
}

std::string encodeSixelRgb24(const RasterImage& image) {
  return encodeSixelRgb24(image.rgb, image.width, image.height);
}

}  // namespace strok
