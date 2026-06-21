#pragma once

#include "frame.hpp"

#include <filesystem>
#include <optional>
#include <string_view>
#include <vector>

namespace contourtty {

struct ImageGridSpec {
  int cols = 0;
  int rows = 0;
};

struct ImageGridTile {
  std::filesystem::path path;
  int col = 0;
  int row = 0;
};

std::optional<ImageGridSpec> parseImageGridSpec(std::string_view value);
bool imageGridPatternHasGlob(std::string_view value) noexcept;
bool imageGridGlobMatch(std::string_view pattern, std::string_view text);
std::vector<std::filesystem::path> expandImageGridPattern(const std::filesystem::path& pattern);
std::vector<ImageGridTile> layoutImageGridTiles(const std::vector<std::filesystem::path>& paths, ImageGridSpec grid);
Frame composeImageGridFrame(const std::vector<Frame>& frames, ImageGridSpec grid, int tile_width, int tile_height, int64_t pts_us = 0);

}  // namespace contourtty
