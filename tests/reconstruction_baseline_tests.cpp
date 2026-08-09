#include "glyph_ramp.hpp"
#include "glyph_shape.hpp"
#include "renderer.hpp"
#include "renderer_cli_adapter.hpp"
#include "scene_source.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

void expectEqual(const std::string& actual, const std::string& expected, const char* label) {
  if (actual != expected) {
    std::cerr << label << "\nexpected:\n" << expected << "\nactual:\n" << actual << '\n';
    std::exit(1);
  }
}

strok::Frame frameFromPixels(int width, int height, const std::vector<strok::Rgb>& pixels) {
  expect(pixels.size() == static_cast<std::size_t>(width * height), "frame pixel count");
  strok::Frame frame;
  frame.w = width;
  frame.h = height;
  frame.rgb.reserve(pixels.size() * 3U);
  for (const strok::Rgb pixel : pixels) {
    frame.rgb.push_back(pixel.r);
    frame.rgb.push_back(pixel.g);
    frame.rgb.push_back(pixel.b);
  }
  return frame;
}

strok::Rgb gray(uint8_t value) {
  return strok::Rgb{.r = value, .g = value, .b = value};
}

strok::TerminalSize terminal(int cols, int rows) {
  return strok::TerminalSize{.cols = cols, .rows = rows, .xpixel = 0, .ypixel = 0};
}

void expectDimensions(const strok::CellBuffer& cells, int cols, int rows, const char* label) {
  expect(cells.cols() == cols && cells.rows() == rows, label);
  expect(cells.size() == static_cast<std::size_t>(cols * rows), label);
}

std::string serializeCells(const strok::CellBuffer& cells) {
  std::ostringstream out;
  out << cells.cols() << 'x' << cells.rows() << '\n';
  for (int row = 0; row < cells.rows(); ++row) {
    for (int col = 0; col < cells.cols(); ++col) {
      const strok::Cell& cell = cells.at(col, row);
      out << static_cast<uint32_t>(cell.glyph) << ':'
          << static_cast<int>(cell.fg.r) << ',' << static_cast<int>(cell.fg.g) << ',' << static_cast<int>(cell.fg.b) << ':'
          << static_cast<int>(cell.bg.r) << ',' << static_cast<int>(cell.bg.g) << ',' << static_cast<int>(cell.bg.b) << '|';
    }
    out << '\n';
  }
  return out.str();
}

strok::CliOptions reconstructionOptions(int width, int height) {
  strok::CliOptions options;
  options.width = width;
  options.height = height;
  options.cell_aspect = 1.0;
  options.glyph_stickiness = 0.0;
  options.orient_stickiness = 0.0;
  options.temporal_supersample = 1;
  return options;
}

}  // namespace

int main() {
  {
    const strok::Frame frame = frameFromPixels(2, 2, {
      gray(0), gray(255),
      gray(255), gray(0),
    });
    strok::CliOptions options = reconstructionOptions(2, 2);
    strok::CellBuffer cells;
    strok::renderFrame(frame, U" @", options, terminal(2, 2), nullptr, &cells);
    expectDimensions(cells, 2, 2, "luminance fixture dimensions");
    expectEqual(serializeCells(cells),
                "2x2\n"
                "32:0,0,0:0,0,0|64:255,255,255:0,0,0|\n"
                "64:255,255,255:0,0,0|32:0,0,0:0,0,0|\n",
                "luminance reconstruction baseline");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
    });
    strok::CliOptions options = reconstructionOptions(2, 2);
    options.mode = "structure";
    options.edge_threshold = 0.01;
    const strok::GlyphShapeTable shape_table = strok::buildGlyphShapeTable(strok::kDefaultStructureShapeGlyphs, 10, 14);
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), &shape_table, &cells);
    expectDimensions(cells, 2, 2, "shape fixture dimensions");
    expectEqual(serializeCells(cells),
                "2x2\n"
                "43:0,0,0:0,0,0|43:255,255,255:0,0,0|\n"
                "43:0,0,0:0,0,0|43:255,255,255:0,0,0|\n",
                "shape-aware reconstruction baseline");
  }

  {
    const strok::SceneMesh mesh = strok::parseObjScene(
      "v -1 -1 0\n"
      "v 1 -1 0\n"
      "v 0 1 0\n"
      "vn 0 0 1\n"
      "f 1//1 2//1 3//1\n");
    const strok::SceneGBuffer gbuffer = strok::renderSceneGBuffer(mesh, strok::SceneRenderOptions{.width = 4, .height = 4});
    strok::CliOptions options = reconstructionOptions(2, 2);
    options.style = "cell-shade";
    strok::CellBuffer cells;
    strok::renderFrame(gbuffer.albedo, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells, nullptr, nullptr, &gbuffer);
    expectDimensions(cells, 2, 2, "scene fixture dimensions");
    expectEqual(serializeCells(cells),
                "2x2\n"
                "58:127,127,255:0,0,0|32:0,0,0:0,0,0|\n"
                "58:127,127,255:0,0,0|58:127,127,255:0,0,0|\n",
                "scene cell-shade reconstruction baseline");
  }

  return 0;
}
