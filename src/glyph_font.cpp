#include "glyph_font.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>

#include <ft2build.h>
#include FT_FREETYPE_H

namespace contourtty {
namespace {

struct RasterKey {
  char32_t glyph = U'\0';
  int width = 0;
  int height = 0;

  bool operator==(const RasterKey& other) const noexcept {
    return glyph == other.glyph && width == other.width && height == other.height;
  }
};

struct RasterKeyHash {
  std::size_t operator()(const RasterKey& key) const noexcept {
    std::size_t hash = std::hash<uint32_t>{}(static_cast<uint32_t>(key.glyph));
    hash ^= std::hash<int>{}(key.width + 0x9e3779b9 + (hash << 6) + (hash >> 2));
    hash ^= std::hash<int>{}(key.height + 0x9e3779b9 + (hash << 6) + (hash >> 2));
    return hash;
  }
};

std::string ftError(std::string_view action, FT_Error error) {
  return std::string(action) + " failed: FreeType error " + std::to_string(error);
}

void writeGrayBitmap(const FT_Bitmap& bitmap, int src_x, int src_y, double* alpha) {
  const int pitch = std::abs(bitmap.pitch);
  const unsigned char value = bitmap.buffer[static_cast<std::size_t>(src_y) * static_cast<std::size_t>(pitch) + static_cast<std::size_t>(src_x)];
  const unsigned int max_value = bitmap.num_grays > 1 ? bitmap.num_grays - 1U : 255U;
  *alpha = std::clamp(static_cast<double>(value) / static_cast<double>(max_value), 0.0, 1.0);
}

void writeMonoBitmap(const FT_Bitmap& bitmap, int src_x, int src_y, double* alpha) {
  const int pitch = std::abs(bitmap.pitch);
  const unsigned char byte = bitmap.buffer[static_cast<std::size_t>(src_y) * static_cast<std::size_t>(pitch) + static_cast<std::size_t>(src_x / 8)];
  *alpha = (byte & (0x80U >> (src_x % 8))) != 0 ? 1.0 : 0.0;
}

}  // namespace

struct GlyphFont::Impl {
  explicit Impl(std::filesystem::path font_path) : font_path(std::move(font_path)) {
    FT_Error error = FT_Init_FreeType(&library);
    if (error != 0) {
      throw std::runtime_error(ftError("FT_Init_FreeType", error));
    }
    error = FT_New_Face(library, this->font_path.string().c_str(), 0, &face);
    if (error != 0) {
      FT_Done_FreeType(library);
      library = nullptr;
      throw std::runtime_error(ftError("FT_New_Face", error) + ": " + this->font_path.string());
    }
  }

  ~Impl() {
    if (face != nullptr) {
      FT_Done_Face(face);
    }
    if (library != nullptr) {
      FT_Done_FreeType(library);
    }
  }

  const GlyphRaster& raster(char32_t glyph, int cell_width, int cell_height) const {
    if (cell_width <= 0 || cell_height <= 0) {
      throw std::invalid_argument("glyph raster dimensions must be positive");
    }
    const RasterKey key{.glyph = glyph, .width = cell_width, .height = cell_height};
    if (const auto found = cache.find(key); found != cache.end()) {
      return found->second;
    }

    FT_Error error = FT_Set_Pixel_Sizes(face, static_cast<FT_UInt>(cell_width), static_cast<FT_UInt>(cell_height));
    if (error != 0) {
      throw std::runtime_error(ftError("FT_Set_Pixel_Sizes", error));
    }
    error = FT_Load_Char(face, static_cast<FT_ULong>(glyph), FT_LOAD_RENDER | FT_LOAD_NO_HINTING | FT_LOAD_TARGET_NORMAL);
    if (error != 0) {
      throw std::runtime_error(ftError("FT_Load_Char", error));
    }

    GlyphRaster result;
    result.width = cell_width;
    result.height = cell_height;
    result.alpha.assign(static_cast<std::size_t>(cell_width) * static_cast<std::size_t>(cell_height), 0.0);

    const FT_Bitmap& bitmap = face->glyph->bitmap;
    const int dest_left = (cell_width - static_cast<int>(bitmap.width)) / 2;
    const int dest_top = (cell_height - static_cast<int>(bitmap.rows)) / 2;
    for (int src_y = 0; src_y < static_cast<int>(bitmap.rows); ++src_y) {
      const int dest_y = dest_top + src_y;
      if (dest_y < 0 || dest_y >= cell_height) {
        continue;
      }
      for (int src_x = 0; src_x < static_cast<int>(bitmap.width); ++src_x) {
        const int dest_x = dest_left + src_x;
        if (dest_x < 0 || dest_x >= cell_width) {
          continue;
        }
        double& alpha = result.alpha[static_cast<std::size_t>(dest_y) * static_cast<std::size_t>(cell_width) + static_cast<std::size_t>(dest_x)];
        if (bitmap.pixel_mode == FT_PIXEL_MODE_GRAY) {
          writeGrayBitmap(bitmap, src_x, src_y, &alpha);
        } else if (bitmap.pixel_mode == FT_PIXEL_MODE_MONO) {
          writeMonoBitmap(bitmap, src_x, src_y, &alpha);
        } else {
          throw std::runtime_error("unsupported FreeType pixel mode: " + std::to_string(bitmap.pixel_mode));
        }
      }
    }
    const auto inserted = cache.emplace(key, std::move(result));
    return inserted.first->second;
  }

  std::filesystem::path font_path;
  FT_Library library = nullptr;
  FT_Face face = nullptr;
  mutable std::unordered_map<RasterKey, GlyphRaster, RasterKeyHash> cache;
};

GlyphFont::GlyphFont(std::filesystem::path path) : impl_(std::make_unique<Impl>(std::move(path))) {}

GlyphFont::~GlyphFont() = default;

GlyphFont::GlyphFont(GlyphFont&&) noexcept = default;

GlyphFont& GlyphFont::operator=(GlyphFont&&) noexcept = default;

const std::filesystem::path& GlyphFont::path() const noexcept {
  return impl_->font_path;
}

const GlyphRaster& GlyphFont::raster(char32_t glyph, int cell_width, int cell_height) const {
  return impl_->raster(glyph, cell_width, cell_height);
}

}  // namespace contourtty
