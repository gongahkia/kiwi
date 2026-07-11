#include "image_grid.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

namespace fs = std::filesystem;

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

void touch(const fs::path& path) {
  std::ofstream out(path);
  out << "x";
}

int pixelR(const strok::Frame& frame, int x, int y) {
  return frame.rgb[(static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(x)) * 3U];
}

}  // namespace

int main() {
  {
    const auto grid = strok::parseImageGridSpec("4x3");
    expect(grid.has_value(), "grid spec parses");
    expect(grid->cols == 4 && grid->rows == 3, "grid spec dimensions");
    expect(!strok::parseImageGridSpec("4").has_value(), "grid spec rejects missing rows");
    expect(!strok::parseImageGridSpec("0x3").has_value(), "grid spec rejects zero");
  }

  {
    expect(strok::imageGridGlobMatch("*.png", "a.png"), "glob star match");
    expect(strok::imageGridGlobMatch("tile-?.png", "tile-a.png"), "glob question match");
    expect(!strok::imageGridGlobMatch("tile-?.png", "tile-ab.png"), "glob question reject");
  }

  const fs::path root = fs::temp_directory_path() / "strok-image-grid-tests";
  fs::remove_all(root);
  fs::create_directories(root);
  touch(root / "b.png");
  touch(root / "a.png");
  touch(root / "c.jpg");

  {
    const std::vector<fs::path> paths = strok::expandImageGridPattern(root / "*.png");
    expect(paths.size() == 2, "glob expands png files");
    expect(paths[0].filename() == "a.png", "glob expansion sorted first");
    expect(paths[1].filename() == "b.png", "glob expansion sorted second");
  }

  {
    const std::vector<fs::path> paths{root / "a.png", root / "b.png", root / "c.jpg"};
    const std::vector<strok::ImageGridTile> tiles = strok::layoutImageGridTiles(paths, strok::ImageGridSpec{.cols = 2, .rows = 1});
    expect(tiles.size() == 2, "tile layout caps to slots");
    expect(tiles[0].col == 0 && tiles[0].row == 0, "first tile position");
    expect(tiles[1].col == 1 && tiles[1].row == 0, "second tile position");
  }

  {
    const strok::Frame red{.w = 1, .h = 1, .rgb = {255, 0, 0}, .pts_us = 10};
    const strok::Frame blue{.w = 1, .h = 1, .rgb = {0, 0, 255}, .pts_us = 20};
    const strok::Frame sheet = strok::composeImageGridFrame({red, blue}, strok::ImageGridSpec{.cols = 2, .rows = 1}, 2, 2, 30);
    expect(sheet.w == 4 && sheet.h == 2, "sheet dimensions");
    expect(sheet.pts_us == 30, "sheet pts");
    expect(pixelR(sheet, 0, 0) == 255, "first tile copied");
    expect(pixelR(sheet, 2, 0) == 0, "second tile copied");
  }

  {
    const strok::Frame wide{.w = 2, .h = 1, .rgb = {255, 0, 0, 255, 0, 0}};
    const strok::Frame sheet = strok::composeImageGridFrame({wide}, strok::ImageGridSpec{.cols = 1, .rows = 1}, 4, 4);
    expect(pixelR(sheet, 0, 0) == 0, "letterbox top row remains blank");
    expect(pixelR(sheet, 0, 1) == 255, "letterboxed image centered");
  }

  fs::remove_all(root);
}
