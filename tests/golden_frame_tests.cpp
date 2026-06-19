#include "glyph_ramp.hpp"
#include "glyph_shape.hpp"
#include "renderer.hpp"

#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

void expectEqual(const std::string& actual, const std::string& expected, const char* label) {
  if (actual != expected) {
    std::cerr << label << "\nexpected:\n" << expected << "\nactual:\n" << actual << '\n';
    std::exit(1);
  }
}

contourtty::Frame frameFromPixels(int width, int height, const std::vector<contourtty::Rgb>& pixels) {
  contourtty::Frame frame;
  frame.w = width;
  frame.h = height;
  frame.rgb.reserve(pixels.size() * 3U);
  for (const contourtty::Rgb pixel : pixels) {
    frame.rgb.push_back(pixel.r);
    frame.rgb.push_back(pixel.g);
    frame.rgb.push_back(pixel.b);
  }
  return frame;
}

contourtty::Rgb gray(uint8_t value) {
  return contourtty::Rgb{.r = value, .g = value, .b = value};
}

std::string serializeCells(const contourtty::CellBuffer& cells) {
  std::ostringstream out;
  out << cells.cols() << 'x' << cells.rows() << '\n';
  for (int row = 0; row < cells.rows(); ++row) {
    for (int col = 0; col < cells.cols(); ++col) {
      const contourtty::Cell& cell = cells.at(col, row);
      out << static_cast<uint32_t>(cell.glyph) << ':'
          << static_cast<int>(cell.fg.r) << ',' << static_cast<int>(cell.fg.g) << ',' << static_cast<int>(cell.fg.b) << ':'
          << static_cast<int>(cell.bg.r) << ',' << static_cast<int>(cell.bg.g) << ',' << static_cast<int>(cell.bg.b) << '|';
    }
    out << '\n';
  }
  return out.str();
}

contourtty::TerminalSize terminal(int cols, int rows) {
  return contourtty::TerminalSize{.cols = cols, .rows = rows, .xpixel = 0, .ypixel = 0};
}

}  // namespace

int main() {
  {
    const contourtty::Frame frame = frameFromPixels(2, 2, {
      gray(0), gray(255),
      gray(255), gray(0),
    });
    contourtty::CliOptions options;
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, U" @", options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "32:0,0,0:0,0,0|64:255,255,255:0,0,0|\n"
                "64:255,255,255:0,0,0|32:0,0,0:0,0,0|\n",
                "luminance golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(1, 2, {
      contourtty::Rgb{.r = 255, .g = 0, .b = 0},
      contourtty::Rgb{.r = 0, .g = 0, .b = 255},
    });
    contourtty::CliOptions options;
    options.mode = "halfblock";
    options.width = 1;
    options.height = 1;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "9600:255,0,0:0,0,255|\n",
                "halfblock golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(2, 4, {
      gray(255), gray(0),
      gray(0), gray(0),
      gray(0), gray(0),
      gray(0), gray(255),
    });
    contourtty::CliOptions options;
    options.charset = "braille";
    options.width = 1;
    options.height = 1;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "10369:63,63,63:0,0,0|\n",
                "braille golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
    });
    contourtty::CliOptions options;
    options.mode = "structure";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "124:0,0,0:0,0,0|124:255,255,255:0,0,0|\n"
                "124:0,0,0:0,0,0|124:255,255,255:0,0,0|\n",
                "structure directional golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
    });
    contourtty::CliOptions options;
    options.mode = "structure";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    const contourtty::GlyphShapeTable shape_table = contourtty::buildGlyphShapeTable(contourtty::kDefaultStructureShapeGlyphs, 10, 14);
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(2, 2), &shape_table, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "43:0,0,0:0,0,0|43:255,255,255:0,0,0|\n"
                "43:0,0,0:0,0,0|43:255,255,255:0,0,0|\n",
                "structure shape-match golden frame");
  }
}
