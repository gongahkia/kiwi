#include "iterm_inline.hpp"

#include "base64.hpp"
#include "png_writer.hpp"

#include <algorithm>
#include <stdexcept>
#include <vector>

namespace strok {
namespace {

bool validDimension(const std::string& value) {
  if (value.empty() || value == "auto") {
    return true;
  }
  const auto digit_end = std::find_if_not(value.begin(), value.end(), [](char c) {
    return c >= '0' && c <= '9';
  });
  if (digit_end == value.begin()) {
    return false;
  }
  const std::string suffix(digit_end, value.end());
  return suffix.empty() || suffix == "px" || suffix == "%";
}

std::string base64EncodeText(const std::string& text) {
  std::vector<uint8_t> bytes(text.begin(), text.end());
  return base64Encode(bytes);
}

void validateOptions(const ITermInlineOptions& options) {
  if (!validDimension(options.width) || !validDimension(options.height)) {
    throw std::invalid_argument("invalid iTerm inline image dimension");
  }
}

}  // namespace

std::string encodeITermInlinePng(std::span<const uint8_t> png, const ITermInlineOptions& options) {
  if (png.empty()) {
    throw std::invalid_argument("iTerm inline PNG payload cannot be empty");
  }
  validateOptions(options);

  std::string escape = "\x1b]1337;File=inline=1";
  if (!options.name.empty()) {
    escape += ";name=" + base64EncodeText(options.name);
  }
  escape += ";size=" + std::to_string(png.size());
  if (!options.width.empty()) {
    escape += ";width=" + options.width;
  }
  if (!options.height.empty()) {
    escape += ";height=" + options.height;
  }
  if (!options.preserve_aspect_ratio) {
    escape += ";preserveAspectRatio=0";
  }
  escape.push_back(':');
  escape += base64Encode(png);
  escape += options.use_st_terminator ? "\x1b\\" : "\a";
  return escape;
}

std::string encodeITermInlineRgb24(std::span<const uint8_t> rgb, int width, int height, const ITermInlineOptions& options) {
  return encodeITermInlinePng(encodePngRgb24(width, height, rgb), options);
}

std::string encodeITermInlineRgb24(const RasterImage& image, const ITermInlineOptions& options) {
  return encodeITermInlineRgb24(image.rgb, image.width, image.height, options);
}

}  // namespace strok
