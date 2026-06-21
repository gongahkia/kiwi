#include "glyph_ramp.hpp"
#include "glyph_shape.hpp"
#include "frame_sampling.hpp"
#include "gpu_sobel.hpp"
#include "graph_yaml.hpp"
#include "renderer.hpp"
#include "scene_source.hpp"

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
    contourtty::Frame frame = frameFromPixels(3, 2, {
      contourtty::Rgb{.r = 1, .g = 2, .b = 3},
      contourtty::Rgb{.r = 4, .g = 5, .b = 6},
      contourtty::Rgb{.r = 7, .g = 8, .b = 9},
      contourtty::Rgb{.r = 10, .g = 11, .b = 12},
      contourtty::Rgb{.r = 13, .g = 14, .b = 15},
      contourtty::Rgb{.r = 16, .g = 17, .b = 18},
    });
    contourtty::mirrorFrameHorizontally(frame);
    const std::vector<uint8_t> expected {
      7, 8, 9, 4, 5, 6, 1, 2, 3,
      16, 17, 18, 13, 14, 15, 10, 11, 12,
    };
    if (frame.rgb != expected) {
      std::cerr << "mirror frame failed\n";
      return 1;
    }
  }

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
    const contourtty::Frame frame = frameFromPixels(2, 2, {
      gray(0), gray(255),
      gray(255), gray(0),
    });
    contourtty::CliOptions options;
    options.mode = "blocks";
    options.width = 1;
    options.height = 1;
    options.cell_aspect = 1.0;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "9630:127,127,127:0,0,0|\n",
                "blocks golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(2, 4, {
      contourtty::Rgb{.r = 0, .g = 255, .b = 0}, gray(0),
      gray(0), gray(0),
      gray(0), gray(0),
      gray(0), gray(0),
    });
    contourtty::CliOptions options;
    options.mode = "octant";
    options.width = 1;
    options.height = 1;
    options.cell_aspect = 1.0;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "118440:0,255,0:0,0,0|\n",
                "octant golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(2, 3, {
      contourtty::Rgb{.r = 0, .g = 255, .b = 0}, gray(0),
      gray(0), gray(0),
      gray(0), gray(0),
    });
    contourtty::CliOptions options;
    options.mode = "sextant";
    options.width = 1;
    options.height = 1;
    options.cell_aspect = 1.0;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "129792:0,255,0:0,0,0|\n",
                "sextant golden frame");
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
                "10369:255,255,255:0,0,0|\n",
                "braille golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(2, 4, {
      contourtty::Rgb{.r = 0, .g = 255, .b = 0}, contourtty::Rgb{.r = 0, .g = 0, .b = 255},
      contourtty::Rgb{.r = 0, .g = 255, .b = 0}, contourtty::Rgb{.r = 0, .g = 0, .b = 255},
      contourtty::Rgb{.r = 0, .g = 255, .b = 0}, contourtty::Rgb{.r = 0, .g = 0, .b = 255},
      contourtty::Rgb{.r = 0, .g = 255, .b = 0}, contourtty::Rgb{.r = 0, .g = 0, .b = 255},
    });
    contourtty::CliOptions options;
    options.mode = "braille";
    options.width = 1;
    options.height = 1;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "10311:0,255,0:0,0,255|\n",
                "braille mode color golden frame");
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
    contourtty::CliOptions direct_options;
    direct_options.mode = "structure";
    direct_options.width = 2;
    direct_options.height = 2;
    direct_options.cell_aspect = 1.0;
    direct_options.edge_threshold = 0.01;
    contourtty::CellBuffer direct_cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, direct_options, terminal(2, 2), nullptr, &direct_cells);

    contourtty::CliOptions graph_options;
    graph_options.width = 2;
    graph_options.height = 2;
    graph_options.cell_aspect = 1.0;
    contourtty::applyGraphYamlToOptions(contourtty::parseGraphYaml(
                                          "passes:\n"
                                          "  - id: decode\n"
                                          "  - id: luminance\n"
                                          "  - id: contrast\n"
                                          "  - id: dog\n"
                                          "  - id: sobel\n"
                                          "  - id: edge-field\n"
                                          "    params: { threshold: 0.01 }\n"
                                          "  - id: cell-average\n"
                                          "  - id: ramp-pick\n"
                                          "  - id: cell-shape\n"
                                          "  - id: overlay-structure\n"
                                          "  - id: emit\n"),
                                        &graph_options);
    contourtty::CellBuffer graph_cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, graph_options, terminal(2, 2), nullptr, &graph_cells);
    expectEqual(serializeCells(graph_cells), serializeCells(direct_cells), "graph yaml structure golden parity");
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

  {
    const contourtty::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
    });
    contourtty::CliOptions options;
    options.mode = "octant";
    options.structure_overlay = "on";
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
                "octant structure overlay golden frame");
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
    options.line_ligatures = true;
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "9474:0,0,0:0,0,0|9474:255,255,255:0,0,0|\n"
                "9474:0,0,0:0,0,0|9474:255,255,255:0,0,0|\n",
                "line ligature golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(64), gray(192), gray(255),
      gray(0), gray(64), gray(192), gray(255),
      gray(255), gray(192), gray(64), gray(0),
      gray(255), gray(192), gray(64), gray(0),
    });
    contourtty::CliOptions options;
    options.style = "painterly";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "32:32,32,32:0,0,0|35:223,223,223:0,0,0|\n"
                "35:223,223,223:0,0,0|32:32,32,32:0,0,0|\n",
                "painterly style golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(255), gray(255), gray(0), gray(0),
      gray(255), gray(255), gray(0), gray(0),
    });
    contourtty::CliOptions options;
    options.style = "hatch";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "9587:0,0,0:0,0,0|9586:255,255,255:0,0,0|\n"
                "9586:255,255,255:0,0,0|9587:0,0,0:0,0,0|\n",
                "hatch style golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(2, 2, {
      gray(0), gray(96),
      gray(160), gray(255),
    });
    contourtty::CliOptions options;
    options.style = "stipple";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "9679:0,0,0:0,0,0|9679:96,96,96:0,0,0|\n"
                "8226:160,160,160:0,0,0|32:255,255,255:0,0,0|\n",
                "stipple style golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(255), gray(255), gray(0), gray(0),
      gray(255), gray(255), gray(0), gray(0),
    });
    contourtty::CliOptions options;
    options.style = "flow";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    options.lic_length = 3;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "9585:0,0,0:0,0,0|32:255,255,255:0,0,0|\n"
                "32:255,255,255:0,0,0|9585:0,0,0:0,0,0|\n",
                "flow style golden frame");
  }

  {
    const contourtty::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(64), gray(128), gray(255),
      gray(255), gray(128), gray(64), gray(0),
      gray(32), gray(96), gray(160), gray(224),
      gray(224), gray(160), gray(96), gray(32),
    });
    const std::vector<std::string> styles {"painterly", "hatch", "stipple", "flow"};
    const std::vector<std::string> modes {"luminance", "structure", "halfblock", "blocks", "octant", "sextant", "braille"};
    for (const std::string& style : styles) {
      for (const std::string& mode : modes) {
        contourtty::CliOptions options;
        options.style = style;
        options.mode = mode;
        options.width = 2;
        options.height = 2;
        options.cell_aspect = 1.0;
        options.edge_threshold = 0.01;
        options.lic_length = 3;
        contourtty::CellBuffer cells;
        contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
        expect(cells.cols() == 2 && cells.rows() == 2, "style/blitter matrix renders expected dimensions");
        for (const contourtty::Cell& cell : cells.cells()) {
          expect(cell.glyph != U'\0', "style/blitter matrix writes glyphs");
        }
      }
    }
  }

  {
    contourtty::SceneGBuffer gbuffer;
    gbuffer.albedo = frameFromPixels(4, 2, {
      gray(220), gray(220), gray(220), gray(220),
      gray(220), gray(220), gray(220), gray(220),
    });
    gbuffer.depth.assign(8, 0.0);
    gbuffer.normals = {
      contourtty::SceneVec3{.x = 1.0}, contourtty::SceneVec3{.x = 1.0}, contourtty::SceneVec3{.y = 1.0}, contourtty::SceneVec3{.y = 1.0},
      contourtty::SceneVec3{.x = 1.0}, contourtty::SceneVec3{.x = 1.0}, contourtty::SceneVec3{.y = 1.0}, contourtty::SceneVec3{.y = 1.0},
    };
    contourtty::CliOptions options;
    options.style = "cell-shade";
    options.width = 2;
    options.height = 1;
    options.cell_aspect = 1.0;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(gbuffer.albedo, contourtty::kDefaultGlyphRamp, options, terminal(2, 1), nullptr, &cells, nullptr, nullptr, &gbuffer);
    expect(cells.at(0, 0).glyph == U'─', "scene normal-orient uses x normal");
    expect(cells.at(1, 0).glyph == U'│', "scene normal-orient uses y normal");
  }

  {
    contourtty::SceneGBuffer gbuffer;
    gbuffer.albedo = frameFromPixels(4, 2, {
      gray(255), gray(255), gray(255), gray(255),
      gray(255), gray(255), gray(255), gray(255),
    });
    gbuffer.depth = {
      0.0, 0.0, 1.0, 1.0,
      0.0, 0.0, 1.0, 1.0,
    };
    gbuffer.normals.assign(8, contourtty::SceneVec3{.z = 1.0});
    contourtty::CliOptions options;
    options.style = "cell-shade";
    options.width = 2;
    options.height = 1;
    options.cell_aspect = 1.0;
    contourtty::CellBuffer cells;
    contourtty::renderFrame(gbuffer.albedo, contourtty::kDefaultGlyphRamp, options, terminal(2, 1), nullptr, &cells, nullptr, nullptr, &gbuffer);
    expect(cells.at(0, 0).fg.r > cells.at(1, 0).fg.r, "scene depth-shade darkens far cell");
    expect(cells.at(0, 0).glyph != cells.at(1, 0).glyph, "scene depth-shade shifts ramp glyph");
  }

  {
    const contourtty::Frame frame = frameFromPixels(8, 8, {
      gray(0), gray(0), gray(0), gray(255), gray(255), gray(255), gray(255), gray(255),
      gray(0), gray(0), gray(0), gray(0), gray(255), gray(255), gray(255), gray(255),
      gray(0), gray(0), gray(0), gray(0), gray(0), gray(255), gray(255), gray(255),
      gray(255), gray(0), gray(0), gray(0), gray(0), gray(0), gray(255), gray(255),
      gray(255), gray(255), gray(0), gray(0), gray(0), gray(0), gray(0), gray(255),
      gray(255), gray(255), gray(255), gray(0), gray(0), gray(0), gray(0), gray(0),
      gray(255), gray(255), gray(255), gray(255), gray(0), gray(0), gray(0), gray(0),
      gray(255), gray(255), gray(255), gray(255), gray(255), gray(0), gray(0), gray(0),
    });
    contourtty::CliOptions options;
    options.mode = "structure";
    options.width = 4;
    options.height = 4;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    const contourtty::GlyphShapeTable shape_table = contourtty::buildGlyphShapeTable(contourtty::kDefaultStructureShapeGlyphs, 10, 14);
    contourtty::CellBuffer cpu_cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(4, 4), &shape_table, &cpu_cells);
    options.gpu = true;
    contourtty::CellBuffer gpu_cells;
    contourtty::renderFrame(frame, contourtty::kDefaultGlyphRamp, options, terminal(4, 4), &shape_table, &gpu_cells);
    if (contourtty::gpuSobelAvailable()) {
      expectEqual(serializeCells(gpu_cells), serializeCells(cpu_cells), "gpu structure render parity");
    }
  }

  {
    contourtty::CliOptions options;
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "cell-average(cpu)  frame:RgbFrame -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "luminance graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.mode = "blocks";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "blocks(cpu)  frame:RgbFrame -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "blocks graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.mode = "octant";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "octant(cpu)  frame:RgbFrame -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "octant graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.mode = "octant";
    options.edge_threshold = 0.01;
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "octant(cpu)  frame:RgbFrame -> base-cells:CellGlyphs\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> gradients:GradientField\n"
                "optical-flow(cpu)  structure-luminance:LuminanceField -> flow:OpticalFlow\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs -> warped-history:CellGlyphs\n"
                "cell-shape(cpu)  edge-field:EdgeField, base-cells:CellGlyphs -> cell-shapes:CellShapeVectors\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "octant auto structure overlay graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.mode = "octant";
    options.structure_overlay = "on";
    options.line_ligatures = true;
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "octant(cpu)  frame:RgbFrame -> base-cells:CellGlyphs\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> gradients:GradientField\n"
                "optical-flow(cpu)  structure-luminance:LuminanceField -> flow:OpticalFlow\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs -> warped-history:CellGlyphs\n"
                "cell-shape(cpu)  edge-field:EdgeField, base-cells:CellGlyphs -> cell-shapes:CellShapeVectors\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "line-ligatures(cpu)  cells:CellGlyphs -> ligature-cells:CellGlyphs\n"
                "emit(cpu)  ligature-cells:CellGlyphs -> \n",
                "line ligature graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.mode = "sextant";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "sextant(cpu)  frame:RgbFrame -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "sextant graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.mode = "braille";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "braille(cpu)  frame:RgbFrame -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "braille graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.mode = "structure";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> gradients:GradientField\n"
                "optical-flow(cpu)  structure-luminance:LuminanceField -> flow:OpticalFlow\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "cell-average(cpu)  frame:RgbFrame, gradients:GradientField -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> base-cells:CellGlyphs\n"
                "cell-shape(cpu)  edge-field:EdgeField, base-cells:CellGlyphs -> cell-shapes:CellShapeVectors\n"
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs -> warped-history:CellGlyphs\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "structure graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.mode = "structure";
    options.style = "painterly";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "kuwahara(cpu)  frame:RgbFrame -> styled-frame:RgbFrame\n"
                "luminance(cpu)  styled-frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> gradients:GradientField\n"
                "optical-flow(cpu)  structure-luminance:LuminanceField -> flow:OpticalFlow\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "cell-average(cpu)  styled-frame:RgbFrame, gradients:GradientField -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> base-cells:CellGlyphs\n"
                "cell-shape(cpu)  edge-field:EdgeField, base-cells:CellGlyphs -> cell-shapes:CellShapeVectors\n"
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs -> warped-history:CellGlyphs\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "painterly graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.style = "hatch";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> raw-gradients:GradientField\n"
                "etf(cpu)  raw-gradients:GradientField -> gradients:GradientField\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "cell-average(cpu)  frame:RgbFrame, gradients:GradientField -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> base-cells:CellGlyphs\n"
                "crosshatch(cpu)  gradients:GradientField, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "hatch graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.style = "stipple";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "cell-average(cpu)  frame:RgbFrame -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> cells:CellGlyphs\n"
                "stipple(cpu)  cells:CellGlyphs, frame:RgbFrame -> stipple-cells:CellGlyphs\n"
                "emit(cpu)  stipple-cells:CellGlyphs -> \n",
                "stipple graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.style = "flow";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> raw-gradients:GradientField\n"
                "optical-flow(cpu)  structure-luminance:LuminanceField -> flow:OpticalFlow\n"
                "etf(cpu)  raw-gradients:GradientField -> gradients:GradientField\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "cell-average(cpu)  frame:RgbFrame, gradients:GradientField -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> base-cells:CellGlyphs\n"
                "lic(cpu)  gradients:GradientField, flow:OpticalFlow, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "flow graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.style = "hatch";
    options.posterize = 4;
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "posterize(cpu)  frame:RgbFrame -> posterized-frame:RgbFrame\n"
                "luminance(cpu)  posterized-frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> raw-gradients:GradientField\n"
                "etf(cpu)  raw-gradients:GradientField -> gradients:GradientField\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "cell-average(cpu)  posterized-frame:RgbFrame, gradients:GradientField -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> base-cells:CellGlyphs\n"
                "crosshatch(cpu)  gradients:GradientField, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "posterize hatch graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.style = "cell-shade";
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "posterize(cpu)  frame:RgbFrame -> posterized-frame:RgbFrame\n"
                "luminance(cpu)  posterized-frame:RgbFrame -> luminance:LuminanceField\n"
                "cell-average(cpu)  posterized-frame:RgbFrame -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> cells:CellGlyphs\n"
                "normal-orient(cpu)  scene-normals:NormalBuffer, cells:CellGlyphs -> normal-cells:CellGlyphs\n"
                "depth-shade(cpu)  scene-depth:DepthBuffer, scene-normals:NormalBuffer, normal-cells:CellGlyphs -> scene-cells:CellGlyphs\n"
                "emit(cpu)  scene-cells:CellGlyphs -> \n",
                "cell-shade graph dump golden");
  }

  {
    contourtty::CliOptions options;
    options.mode = "structure";
    options.etf_iters = 2;
    expectEqual(contourtty::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> raw-gradients:GradientField\n"
                "optical-flow(cpu)  structure-luminance:LuminanceField -> flow:OpticalFlow\n"
                "etf(cpu)  raw-gradients:GradientField -> gradients:GradientField\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "cell-average(cpu)  frame:RgbFrame, gradients:GradientField -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> base-cells:CellGlyphs\n"
                "cell-shape(cpu)  edge-field:EdgeField, base-cells:CellGlyphs -> cell-shapes:CellShapeVectors\n"
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs -> warped-history:CellGlyphs\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "ETF graph dump golden");
  }
}
