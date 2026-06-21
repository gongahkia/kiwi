#pragma once

#include "raster_compose.hpp"

#include <cstdint>
#include <span>
#include <string>

namespace contourtty {

struct ITermInlineOptions {
  std::string name = "contourtty.png";
  std::string width;
  std::string height;
  bool preserve_aspect_ratio = false;
  bool use_st_terminator = false;
};

std::string encodeITermInlinePng(std::span<const uint8_t> png, const ITermInlineOptions& options = {});
std::string encodeITermInlineRgb24(std::span<const uint8_t> rgb, int width, int height, const ITermInlineOptions& options = {});
std::string encodeITermInlineRgb24(const RasterImage& image, const ITermInlineOptions& options = {});

}  // namespace contourtty
