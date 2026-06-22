#pragma once

#include "raster_compose.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>

namespace contourtty {

struct KittyImageOptions {
  uint32_t image_id = 1;
  uint32_t placement_id = 1;
  int columns = 0;
  int rows = 0;
  std::size_t chunk_size = 4096;
  bool suppress_response = true;
  bool leave_cursor = true;
};

struct KittyAnimationFrameOptions {
  uint32_t image_id = 1;
  uint32_t frame_number = 1;
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
  std::size_t chunk_size = 4096;
  bool suppress_response = true;
  bool replace = true;
};

std::string encodeKittyRgb24(std::span<const uint8_t> rgb, int width, int height, const KittyImageOptions& options = {});
std::string encodeKittyRgb24(const RasterImage& image, const KittyImageOptions& options = {});
std::string encodeKittyAnimationFrameRgb24(std::span<const uint8_t> rgb, const KittyAnimationFrameOptions& options);
std::string controlKittyAnimationFrame(uint32_t image_id, uint32_t frame_number, bool suppress_response = true);
std::string deleteKittyImage(uint32_t image_id, uint32_t placement_id = 0, bool suppress_response = true);

}  // namespace contourtty
