#include "image_grid.hpp"

#include <algorithm>
#include <charconv>
#include <stdexcept>

namespace contourtty {
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

}  // namespace contourtty
