#pragma once

#include <cstdint>
#include <filesystem>
#include <span>

namespace contourtty {

void writePngRgb24(const std::filesystem::path& path, int width, int height, std::span<const uint8_t> rgb);

}  // namespace contourtty
