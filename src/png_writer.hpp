#pragma once

#include <cstdint>
#include <filesystem>
#include <span>
#include <vector>

namespace strok {

void writePngRgb24(const std::filesystem::path& path, int width, int height, std::span<const uint8_t> rgb);
std::vector<uint8_t> encodePngRgb24(int width, int height, std::span<const uint8_t> rgb);

}  // namespace strok
