#pragma once

#include <filesystem>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace contourtty {

struct GlyphRaster {
  int width = 0;
  int height = 0;
  std::vector<double> alpha;
};

class GlyphFont {
 public:
  explicit GlyphFont(std::filesystem::path path);
  ~GlyphFont();

  GlyphFont(const GlyphFont&) = delete;
  GlyphFont& operator=(const GlyphFont&) = delete;
  GlyphFont(GlyphFont&&) noexcept;
  GlyphFont& operator=(GlyphFont&&) noexcept;

  const std::filesystem::path& path() const noexcept;
  const GlyphRaster& raster(char32_t glyph, int cell_width, int cell_height) const;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

double glyphInkDensity(const GlyphFont& font, char32_t glyph, int cell_width, int cell_height);
std::u32string sortRampByInkDensity(std::u32string_view ramp, const GlyphFont& font, int cell_width, int cell_height);

}  // namespace contourtty
