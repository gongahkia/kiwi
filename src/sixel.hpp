#pragma once

#include "raster_compose.hpp"

#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace strok {

struct SixelImage {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> palette_indices;
  std::vector<uint8_t> palette_rgb;
};

SixelImage quantizeSixelOklab(std::span<const uint8_t> rgb, int width, int height);
std::string encodeSixelRgb24(std::span<const uint8_t> rgb, int width, int height);
std::string encodeSixelRgb24(const RasterImage& image);

}  // namespace strok
