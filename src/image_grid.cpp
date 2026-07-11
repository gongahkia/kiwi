#include "image_grid.hpp"

#include <algorithm>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

namespace strok {
namespace {

std::optional<int> parsePositiveInt(std::string_view value) {
  int parsed = 0;
  const char* first = value.data();
  const char* last = value.data() + value.size();
  const auto result = std::from_chars(first, last, parsed);
  if (result.ec != std::errc{} || result.ptr != last || parsed <= 0) {
    return std::nullopt;
  }
  return parsed;
}

}  // namespace

std::optional<ImageGridSpec> parseImageGridSpec(std::string_view value) {
  const std::size_t x = value.find_first_of("xX");
  if (x == std::string_view::npos) {
    return std::nullopt;
  }
  const auto cols = parsePositiveInt(value.substr(0, x));
  const auto rows = parsePositiveInt(value.substr(x + 1));
  if (!cols.has_value() || !rows.has_value()) {
    return std::nullopt;
  }
  return ImageGridSpec{.cols = *cols, .rows = *rows};
}

bool imageGridPatternHasGlob(std::string_view value) noexcept {
  return value.find('*') != std::string_view::npos || value.find('?') != std::string_view::npos;
}

bool imageGridGlobMatch(std::string_view pattern, std::string_view text) {
  std::size_t pattern_index = 0;
  std::size_t text_index = 0;
  std::size_t star_index = std::string_view::npos;
  std::size_t star_text_index = 0;
  while (text_index < text.size()) {
    if (pattern_index < pattern.size() && (pattern[pattern_index] == '?' || pattern[pattern_index] == text[text_index])) {
      ++pattern_index;
      ++text_index;
      continue;
    }
    if (pattern_index < pattern.size() && pattern[pattern_index] == '*') {
      star_index = pattern_index++;
      star_text_index = text_index;
      continue;
    }
    if (star_index != std::string_view::npos) {
      pattern_index = star_index + 1;
      text_index = ++star_text_index;
      continue;
    }
    return false;
  }
  while (pattern_index < pattern.size() && pattern[pattern_index] == '*') {
    ++pattern_index;
  }
  return pattern_index == pattern.size();
}

std::vector<std::filesystem::path> expandImageGridPattern(const std::filesystem::path& pattern) {
  if (!imageGridPatternHasGlob(pattern.string())) {
    if (std::filesystem::exists(pattern)) {
      return {pattern};
    }
    return {};
  }

  const std::filesystem::path parent = pattern.has_parent_path() ? pattern.parent_path() : std::filesystem::path(".");
  const std::string filename_pattern = pattern.filename().string();
  std::vector<std::filesystem::path> paths;
  if (!std::filesystem::exists(parent)) {
    return paths;
  }
  for (const std::filesystem::directory_entry& entry : std::filesystem::directory_iterator(parent)) {
    if (!entry.is_regular_file()) {
      continue;
    }
    if (imageGridGlobMatch(filename_pattern, entry.path().filename().string())) {
      paths.push_back(entry.path());
    }
  }
  std::sort(paths.begin(), paths.end());
  return paths;
}

std::vector<ImageGridTile> layoutImageGridTiles(const std::vector<std::filesystem::path>& paths, ImageGridSpec grid) {
  if (grid.cols <= 0 || grid.rows <= 0) {
    throw std::invalid_argument("image grid dimensions must be positive");
  }
  const int slots = grid.cols * grid.rows;
  std::vector<ImageGridTile> tiles;
  tiles.reserve(std::min<std::size_t>(paths.size(), static_cast<std::size_t>(slots)));
  for (int index = 0; index < slots && static_cast<std::size_t>(index) < paths.size(); ++index) {
    tiles.push_back(ImageGridTile{
      .path = paths[static_cast<std::size_t>(index)],
      .col = index % grid.cols,
      .row = index / grid.cols,
    });
  }
  return tiles;
}

Frame composeImageGridFrame(const std::vector<Frame>& frames, ImageGridSpec grid, int tile_width, int tile_height, int64_t pts_us) {
  if (grid.cols <= 0 || grid.rows <= 0 || tile_width <= 0 || tile_height <= 0) {
    throw std::invalid_argument("image grid dimensions must be positive");
  }
  Frame output{
    .w = grid.cols * tile_width,
    .h = grid.rows * tile_height,
    .pts_us = pts_us,
  };
  output.rgb.assign(static_cast<std::size_t>(output.w) * static_cast<std::size_t>(output.h) * 3U, 0);
  const int slots = grid.cols * grid.rows;
  const int count = std::min<int>(slots, static_cast<int>(frames.size()));
  for (int index = 0; index < count; ++index) {
    const Frame& frame = frames[static_cast<std::size_t>(index)];
    if (frame.w <= 0 || frame.h <= 0 || frame.rgb.size() != static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h) * 3U) {
      throw std::invalid_argument("image grid frame dimensions are invalid");
    }
    const int tile_col = index % grid.cols;
    const int tile_row = index / grid.cols;
    const double scale = std::min(static_cast<double>(tile_width) / static_cast<double>(frame.w), static_cast<double>(tile_height) / static_cast<double>(frame.h));
    const int draw_w = std::max(1, static_cast<int>(static_cast<double>(frame.w) * scale));
    const int draw_h = std::max(1, static_cast<int>(static_cast<double>(frame.h) * scale));
    const int origin_x = tile_col * tile_width + (tile_width - draw_w) / 2;
    const int origin_y = tile_row * tile_height + (tile_height - draw_h) / 2;
    for (int y = 0; y < draw_h; ++y) {
      const int src_y = std::clamp(static_cast<int>((static_cast<int64_t>(y) * frame.h) / draw_h), 0, frame.h - 1);
      for (int x = 0; x < draw_w; ++x) {
        const int src_x = std::clamp(static_cast<int>((static_cast<int64_t>(x) * frame.w) / draw_w), 0, frame.w - 1);
        const std::size_t src = (static_cast<std::size_t>(src_y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(src_x)) * 3U;
        const std::size_t dst = (static_cast<std::size_t>(origin_y + y) * static_cast<std::size_t>(output.w) + static_cast<std::size_t>(origin_x + x)) * 3U;
        output.rgb[dst] = frame.rgb[src];
        output.rgb[dst + 1U] = frame.rgb[src + 1U];
        output.rgb[dst + 2U] = frame.rgb[src + 2U];
      }
    }
  }
  return output;
}

}  // namespace strok
