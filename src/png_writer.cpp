#include "png_writer.hpp"

#include <algorithm>
#include <array>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <zlib.h>

namespace contourtty {
namespace {

void appendU32(std::vector<uint8_t>& bytes, uint32_t value) {
  bytes.push_back(static_cast<uint8_t>((value >> 24U) & 0xffU));
  bytes.push_back(static_cast<uint8_t>((value >> 16U) & 0xffU));
  bytes.push_back(static_cast<uint8_t>((value >> 8U) & 0xffU));
  bytes.push_back(static_cast<uint8_t>(value & 0xffU));
}

void appendChunk(std::vector<uint8_t>& png, std::array<char, 4> type, std::span<const uint8_t> payload) {
  appendU32(png, static_cast<uint32_t>(payload.size()));
  const auto type_start = png.size();
  for (char c : type) {
    png.push_back(static_cast<uint8_t>(c));
  }
  png.insert(png.end(), payload.begin(), payload.end());

  uLong crc = crc32(0L, Z_NULL, 0);
  crc = crc32(crc, png.data() + type_start, static_cast<uInt>(png.size() - type_start));
  appendU32(png, static_cast<uint32_t>(crc));
}

}  // namespace

std::vector<uint8_t> encodePngRgb24(int width, int height, std::span<const uint8_t> rgb) {
  if (width <= 0 || height <= 0) {
    throw std::runtime_error("invalid png dimensions");
  }
  const std::size_t row_bytes = static_cast<std::size_t>(width) * 3;
  if (rgb.size() != row_bytes * static_cast<std::size_t>(height)) {
    throw std::runtime_error("invalid RGB24 buffer size");
  }

  std::vector<uint8_t> filtered((row_bytes + 1) * static_cast<std::size_t>(height));
  for (int y = 0; y < height; ++y) {
    const std::size_t dst = static_cast<std::size_t>(y) * (row_bytes + 1);
    const std::size_t src = static_cast<std::size_t>(y) * row_bytes;
    filtered[dst] = 0;
    std::copy_n(rgb.data() + src, row_bytes, filtered.data() + dst + 1);
  }

  std::vector<uint8_t> compressed(compressBound(static_cast<uLong>(filtered.size())));
  uLongf compressed_size = static_cast<uLongf>(compressed.size());
  const int z_result = compress2(compressed.data(), &compressed_size, filtered.data(), static_cast<uLong>(filtered.size()), Z_BEST_SPEED);
  if (z_result != Z_OK) {
    throw std::runtime_error("png compression failed");
  }
  compressed.resize(compressed_size);

  std::vector<uint8_t> png;
  constexpr std::array<uint8_t, 8> signature {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
  png.insert(png.end(), signature.begin(), signature.end());

  std::vector<uint8_t> ihdr;
  appendU32(ihdr, static_cast<uint32_t>(width));
  appendU32(ihdr, static_cast<uint32_t>(height));
  ihdr.push_back(8);
  ihdr.push_back(2);
  ihdr.push_back(0);
  ihdr.push_back(0);
  ihdr.push_back(0);

  appendChunk(png, {'I', 'H', 'D', 'R'}, ihdr);
  appendChunk(png, {'I', 'D', 'A', 'T'}, compressed);
  appendChunk(png, {'I', 'E', 'N', 'D'}, {});
  return png;
}

void writePngRgb24(const std::filesystem::path& path, int width, int height, std::span<const uint8_t> rgb) {
  const std::vector<uint8_t> png = encodePngRgb24(width, height, rgb);
  std::ofstream out(path, std::ios::binary);
  if (!out) {
    throw std::runtime_error("failed to open png output: " + path.string());
  }
  out.write(reinterpret_cast<const char*>(png.data()), static_cast<std::streamsize>(png.size()));
  if (!out) {
    throw std::runtime_error("failed to write png output: " + path.string());
  }
}

}  // namespace contourtty
