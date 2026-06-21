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

}  // namespace

int main() {
  {
    const auto grid = contourtty::parseImageGridSpec("4x3");
    expect(grid.has_value(), "grid spec parses");
    expect(grid->cols == 4 && grid->rows == 3, "grid spec dimensions");
    expect(!contourtty::parseImageGridSpec("4").has_value(), "grid spec rejects missing rows");
    expect(!contourtty::parseImageGridSpec("0x3").has_value(), "grid spec rejects zero");
  }

  {
    expect(contourtty::imageGridGlobMatch("*.png", "a.png"), "glob star match");
    expect(contourtty::imageGridGlobMatch("tile-?.png", "tile-a.png"), "glob question match");
    expect(!contourtty::imageGridGlobMatch("tile-?.png", "tile-ab.png"), "glob question reject");
  }

  const fs::path root = fs::temp_directory_path() / "contourtty-image-grid-tests";
  fs::remove_all(root);
  fs::create_directories(root);
  touch(root / "b.png");
  touch(root / "a.png");
  touch(root / "c.jpg");

  {
    const std::vector<fs::path> paths = contourtty::expandImageGridPattern(root / "*.png");
    expect(paths.size() == 2, "glob expands png files");
    expect(paths[0].filename() == "a.png", "glob expansion sorted first");
    expect(paths[1].filename() == "b.png", "glob expansion sorted second");
  }

  {
    const std::vector<fs::path> paths{root / "a.png", root / "b.png", root / "c.jpg"};
    const std::vector<contourtty::ImageGridTile> tiles = contourtty::layoutImageGridTiles(paths, contourtty::ImageGridSpec{.cols = 2, .rows = 1});
    expect(tiles.size() == 2, "tile layout caps to slots");
    expect(tiles[0].col == 0 && tiles[0].row == 0, "first tile position");
    expect(tiles[1].col == 1 && tiles[1].row == 0, "second tile position");
  }

  fs::remove_all(root);
}
