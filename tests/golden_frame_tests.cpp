#include "asciinema_source.hpp"
#include "diff_emitter.hpp"
#include "glyph_ramp.hpp"
#include "glyph_shape.hpp"
#include "frame_sampling.hpp"
#include "gpu_sobel.hpp"
#include "graph_yaml.hpp"
#include "image_grid.hpp"
#include "raster_compose.hpp"
#include "renderer.hpp"
#include "renderer_cli_adapter.hpp"
#include "scene_source.hpp"
#include "stdin_data.hpp"

#include <cctype>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
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

std::vector<int> parseCsiParams(std::string_view bytes, std::size_t* index, char* final) {
  std::vector<int> params;
  int value = 0;
  bool have_value = false;
  for (; *index < bytes.size(); ++*index) {
    const unsigned char ch = static_cast<unsigned char>(bytes[*index]);
    if (std::isdigit(ch) != 0) {
      value = value * 10 + static_cast<int>(ch - '0');
      have_value = true;
      continue;
    }
    if (ch == ';') {
      params.push_back(have_value ? value : 0);
      value = 0;
      have_value = false;
      continue;
    }
    params.push_back(have_value ? value : 0);
    *final = static_cast<char>(ch);
    ++*index;
    return params;
  }
  expect(false, "unterminated CSI");
  return {};
}

char32_t decodeUtf8(std::string_view bytes, std::size_t* index) {
  const auto lead = static_cast<unsigned char>(bytes.at(*index));
  if (lead <= 0x7fU) {
    ++*index;
    return lead;
  }
  int extra = 0;
  char32_t codepoint = 0;
  if ((lead & 0xe0U) == 0xc0U) {
    extra = 1;
    codepoint = lead & 0x1fU;
  } else if ((lead & 0xf0U) == 0xe0U) {
    extra = 2;
    codepoint = lead & 0x0fU;
  } else if ((lead & 0xf8U) == 0xf0U) {
    extra = 3;
    codepoint = lead & 0x07U;
  } else {
    expect(false, "invalid UTF-8 lead byte");
  }
  ++*index;
  for (int i = 0; i < extra; ++i) {
    expect(*index < bytes.size(), "truncated UTF-8");
    const auto next = static_cast<unsigned char>(bytes[*index]);
    expect((next & 0xc0U) == 0x80U, "invalid UTF-8 continuation");
    codepoint = (codepoint << 6U) | (next & 0x3fU);
    ++*index;
  }
  return codepoint;
}

uint8_t sgrByte(int value, const char* label) {
  expect(value >= 0 && value <= 255, label);
  return static_cast<uint8_t>(value);
}

void applySgr(const std::vector<int>& params, strok::Rgb* fg, strok::Rgb* bg) {
  for (std::size_t i = 0; i < params.size();) {
    const int code = params[i];
    if (code == 0) {
      *fg = strok::Rgb{.r = 255, .g = 255, .b = 255};
      *bg = strok::Rgb{};
      ++i;
    } else if ((code == 38 || code == 48) && i + 4 < params.size() && params[i + 1] == 2) {
      strok::Rgb color{
        .r = sgrByte(params[i + 2], "SGR red range"),
        .g = sgrByte(params[i + 3], "SGR green range"),
        .b = sgrByte(params[i + 4], "SGR blue range"),
      };
      if (code == 38) {
        *fg = color;
      } else {
        *bg = color;
      }
      i += 5;
    } else {
      expect(false, "unexpected SGR code");
    }
  }
}

strok::CellBuffer captureAnsiCells(std::string_view bytes, int cols, int rows) {
  strok::CellBuffer captured(cols, rows);
  strok::Rgb fg{.r = 255, .g = 255, .b = 255};
  strok::Rgb bg{};
  int cursor_col = 0;
  int cursor_row = 0;
  for (std::size_t i = 0; i < bytes.size();) {
    if (bytes[i] == '\x1b') {
      expect(i + 1 < bytes.size() && bytes[i + 1] == '[', "expected CSI");
      i += 2;
      char final = 0;
      const std::vector<int> params = parseCsiParams(bytes, &i, &final);
      if (final == 'H') {
        expect(params.size() >= 2, "cursor position params");
        cursor_row = params[0] - 1;
        cursor_col = params[1] - 1;
        expect(cursor_row >= 0 && cursor_row < rows && cursor_col >= 0 && cursor_col < cols, "cursor position range");
      } else if (final == 'm') {
        applySgr(params, &fg, &bg);
      } else if (final == 'J') {
        expect(params.size() == 1 && params[0] == 2, "clear screen CSI");
      } else {
        expect(false, "unexpected CSI final byte");
      }
      continue;
    }
    const char32_t glyph = decodeUtf8(bytes, &i);
    expect(cursor_row >= 0 && cursor_row < rows && cursor_col >= 0 && cursor_col < cols, "glyph cursor range");
    captured.at(cursor_col, cursor_row) = strok::Cell{.glyph = glyph, .fg = fg, .bg = bg};
    ++cursor_col;
  }
  return captured;
}

void expectSameRaster(const strok::RasterImage& lhs, const strok::RasterImage& rhs, const char* label) {
  expect(lhs.width == rhs.width && lhs.height == rhs.height, label);
  if (lhs.rgb != rhs.rgb) {
    std::cerr << label << '\n';
    for (std::size_t i = 0; i < lhs.rgb.size() && i < rhs.rgb.size(); ++i) {
      if (lhs.rgb[i] != rhs.rgb[i]) {
        std::cerr << "first differing byte " << i << ": " << static_cast<int>(lhs.rgb[i]) << " != " << static_cast<int>(rhs.rgb[i]) << '\n';
        break;
      }
    }
    std::exit(1);
  }
}

strok::TerminalSize terminal(int cols, int rows) {
  return strok::TerminalSize{.cols = cols, .rows = rows, .xpixel = 0, .ypixel = 0};
}

}  // namespace

int main() {
  {
    strok::Frame frame = frameFromPixels(3, 2, {
      strok::Rgb{.r = 1, .g = 2, .b = 3},
      strok::Rgb{.r = 4, .g = 5, .b = 6},
      strok::Rgb{.r = 7, .g = 8, .b = 9},
      strok::Rgb{.r = 10, .g = 11, .b = 12},
      strok::Rgb{.r = 13, .g = 14, .b = 15},
      strok::Rgb{.r = 16, .g = 17, .b = 18},
    });
    strok::mirrorFrameHorizontally(frame);
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
    const strok::Frame frame = frameFromPixels(2, 2, {
      gray(0), gray(255),
      gray(255), gray(0),
    });
    strok::CliOptions options;
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(frame, U" @", options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "32:0,0,0:0,0,0|64:255,255,255:0,0,0|\n"
                "64:255,255,255:0,0,0|32:0,0,0:0,0,0|\n",
                "luminance golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 2, {
      gray(0), gray(85), gray(170), gray(255),
      strok::Rgb{.r = 255, .g = 32, .b = 0}, strok::Rgb{.r = 0, .g = 220, .b = 40}, strok::Rgb{.r = 32, .g = 64, .b = 255}, gray(20),
    });
    strok::CliOptions options;
    options.width = 4;
    options.height = 2;
    options.cell_aspect = 1.0;
    strok::CellBuffer rendered_cells;
    strok::renderFrame(frame, U" .#@", options, terminal(4, 2), nullptr, &rendered_cells);

    strok::DiffEmitter emitter;
    const strok::EmissionResult terminal_output = emitter.emit(rendered_cells, strok::EmissionOptions{.color_mode = strok::ColorMode::Truecolor});
    const strok::CellBuffer captured_cells = captureAnsiCells(terminal_output.bytes, rendered_cells.cols(), rendered_cells.rows());
    expectEqual(serializeCells(captured_cells), serializeCells(rendered_cells), "terminal capture matches luminance cells");

    const strok::RasterImage direct_raster = strok::rasterComposeCells(rendered_cells, strok::ColorMode::Truecolor, strok::DitherMode::None);
    const strok::RasterImage captured_raster = strok::rasterComposeCells(captured_cells, strok::ColorMode::Truecolor, strok::DitherMode::None);
    expectSameRaster(captured_raster, direct_raster, "raster compose matches captured terminal output");
  }

  {
    const strok::Frame frame = frameFromPixels(1, 2, {
      strok::Rgb{.r = 255, .g = 0, .b = 0},
      strok::Rgb{.r = 0, .g = 0, .b = 255},
    });
    strok::CliOptions options;
    options.mode = "halfblock";
    options.width = 1;
    options.height = 1;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "9600:255,0,0:0,0,255|\n",
                "halfblock golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(2, 2, {
      gray(0), gray(255),
      gray(255), gray(0),
    });
    strok::CliOptions options;
    options.mode = "blocks";
    options.width = 1;
    options.height = 1;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "9630:127,127,127:0,0,0|\n",
                "blocks golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(2, 4, {
      strok::Rgb{.r = 0, .g = 255, .b = 0}, gray(0),
      gray(0), gray(0),
      gray(0), gray(0),
      gray(0), gray(0),
    });
    strok::CliOptions options;
    options.mode = "octant";
    options.width = 1;
    options.height = 1;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "118440:0,255,0:0,0,0|\n",
                "octant golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(2, 3, {
      strok::Rgb{.r = 0, .g = 255, .b = 0}, gray(0),
      gray(0), gray(0),
      gray(0), gray(0),
    });
    strok::CliOptions options;
    options.mode = "sextant";
    options.width = 1;
    options.height = 1;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "129792:0,255,0:0,0,0|\n",
                "sextant golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(2, 4, {
      gray(255), gray(0),
      gray(0), gray(0),
      gray(0), gray(0),
      gray(0), gray(255),
    });
    strok::CliOptions options;
    options.charset = "braille";
    options.width = 1;
    options.height = 1;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "10369:255,255,255:0,0,0|\n",
                "braille golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(2, 4, {
      strok::Rgb{.r = 0, .g = 255, .b = 0}, strok::Rgb{.r = 0, .g = 0, .b = 255},
      strok::Rgb{.r = 0, .g = 255, .b = 0}, strok::Rgb{.r = 0, .g = 0, .b = 255},
      strok::Rgb{.r = 0, .g = 255, .b = 0}, strok::Rgb{.r = 0, .g = 0, .b = 255},
      strok::Rgb{.r = 0, .g = 255, .b = 0}, strok::Rgb{.r = 0, .g = 0, .b = 255},
    });
    strok::CliOptions options;
    options.mode = "braille";
    options.width = 1;
    options.height = 1;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(1, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "1x1\n"
                "10311:0,255,0:0,0,255|\n",
                "braille mode color golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
    });
    strok::CliOptions options;
    options.mode = "structure";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "124:0,0,0:0,0,0|124:255,255,255:0,0,0|\n"
                "124:0,0,0:0,0,0|124:255,255,255:0,0,0|\n",
                "structure directional golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
    });
    strok::CliOptions direct_options;
    direct_options.mode = "structure";
    direct_options.width = 2;
    direct_options.height = 2;
    direct_options.cell_aspect = 1.0;
    direct_options.edge_threshold = 0.01;
    strok::CellBuffer direct_cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, direct_options, terminal(2, 2), nullptr, &direct_cells);

    strok::CliOptions graph_options;
    graph_options.width = 2;
    graph_options.height = 2;
    graph_options.cell_aspect = 1.0;
    strok::applyGraphYamlToOptions(strok::parseGraphYaml(
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
    strok::CellBuffer graph_cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, graph_options, terminal(2, 2), nullptr, &graph_cells);
    expectEqual(serializeCells(graph_cells), serializeCells(direct_cells), "graph yaml structure golden parity");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
    });
    strok::CliOptions options;
    options.mode = "structure";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    const strok::GlyphShapeTable shape_table = strok::buildGlyphShapeTable(strok::kDefaultStructureShapeGlyphs, 10, 14);
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), &shape_table, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "43:0,0,0:0,0,0|43:255,255,255:0,0,0|\n"
                "43:0,0,0:0,0,0|43:255,255,255:0,0,0|\n",
                "structure shape-match golden frame");
  }

  {
    const strok::Frame first = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(0), gray(0),
      gray(0), gray(0), gray(0), gray(0),
      gray(255), gray(255), gray(255), gray(255),
      gray(255), gray(255), gray(255), gray(255),
    });
    const strok::Frame second = frameFromPixels(4, 4, {
      gray(255), gray(255), gray(255), gray(255),
      gray(255), gray(255), gray(255), gray(255),
      gray(0), gray(0), gray(0), gray(0),
      gray(0), gray(0), gray(0), gray(0),
    });
    strok::CliOptions options;
    options.mode = "structure";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    options.temporal_supersample = 2;
    strok::CellBuffer cells;
    strok::RenderTemporalState temporal_state;
    strok::RenderStats stats;
    temporal_state.next_supersample_frame = second;
    strok::renderFrame(first, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells, &stats, &temporal_state);
    expect(stats.temporal_supersample_frames == 1, "temporal supersample first frame uses lookahead blend");
    temporal_state.next_supersample_frame.reset();
    strok::renderFrame(second, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells, &stats, &temporal_state);
    expect(stats.temporal_supersample_frames == 2, "temporal supersample falls back to adjacent history");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
    });
    strok::CliOptions options;
    options.mode = "octant";
    options.structure_overlay = "on";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "124:0,0,0:0,0,0|124:255,255,255:0,0,0|\n"
                "124:0,0,0:0,0,0|124:255,255,255:0,0,0|\n",
                "octant structure overlay golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
    });
    strok::CliOptions options;
    options.mode = "structure";
    options.line_ligatures = true;
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "9474:0,0,0:0,0,0|9474:255,255,255:0,0,0|\n"
                "9474:0,0,0:0,0,0|9474:255,255,255:0,0,0|\n",
                "line ligature golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(64), gray(192), gray(255),
      gray(0), gray(64), gray(192), gray(255),
      gray(255), gray(192), gray(64), gray(0),
      gray(255), gray(192), gray(64), gray(0),
    });
    strok::CliOptions options;
    options.style = "painterly";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "32:32,32,32:0,0,0|35:223,223,223:0,0,0|\n"
                "35:223,223,223:0,0,0|32:32,32,32:0,0,0|\n",
                "painterly style golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(255), gray(255), gray(0), gray(0),
      gray(255), gray(255), gray(0), gray(0),
    });
    strok::CliOptions options;
    options.style = "hatch";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "9587:0,0,0:0,0,0|9586:255,255,255:0,0,0|\n"
                "9586:255,255,255:0,0,0|9587:0,0,0:0,0,0|\n",
                "hatch style golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(2, 2, {
      gray(0), gray(96),
      gray(160), gray(255),
    });
    strok::CliOptions options;
    options.style = "stipple";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "9679:0,0,0:0,0,0|9679:96,96,96:0,0,0|\n"
                "8226:160,160,160:0,0,0|32:255,255,255:0,0,0|\n",
                "stipple style golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(0), gray(255), gray(255),
      gray(0), gray(0), gray(255), gray(255),
      gray(255), gray(255), gray(0), gray(0),
      gray(255), gray(255), gray(0), gray(0),
    });
    strok::CliOptions options;
    options.style = "flow";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    options.lic_length = 3;
    strok::CellBuffer cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "9585:0,0,0:0,0,0|32:255,255,255:0,0,0|\n"
                "32:255,255,255:0,0,0|9585:0,0,0:0,0,0|\n",
                "flow style golden frame");
  }

  {
    const strok::Frame frame = frameFromPixels(4, 4, {
      gray(0), gray(64), gray(128), gray(255),
      gray(255), gray(128), gray(64), gray(0),
      gray(32), gray(96), gray(160), gray(224),
      gray(224), gray(160), gray(96), gray(32),
    });
    const std::vector<std::string> styles {"painterly", "hatch", "stipple", "flow"};
    const std::vector<std::string> modes {"luminance", "structure", "halfblock", "blocks", "octant", "sextant", "braille"};
    for (const std::string& style : styles) {
      for (const std::string& mode : modes) {
        strok::CliOptions options;
        options.style = style;
        options.mode = mode;
        options.width = 2;
        options.height = 2;
        options.cell_aspect = 1.0;
        options.edge_threshold = 0.01;
        options.lic_length = 3;
        strok::CellBuffer cells;
        strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells);
        expect(cells.cols() == 2 && cells.rows() == 2, "style/blitter matrix renders expected dimensions");
        for (const strok::Cell& cell : cells.cells()) {
          expect(cell.glyph != U'\0', "style/blitter matrix writes glyphs");
        }
      }
    }
  }

  {
    const strok::Frame frame = strok::composeImageGridFrame({
      frameFromPixels(1, 1, {gray(255)}),
      frameFromPixels(1, 1, {gray(0)}),
    }, strok::ImageGridSpec{.cols = 2, .rows = 1}, 1, 1);
    strok::CliOptions options;
    options.width = 2;
    options.height = 1;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(frame, U" @", options, terminal(2, 1), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x1\n"
                "64:255,255,255:0,0,0|32:0,0,0:0,0,0|\n",
                "image-grid source golden frame");
  }

  {
    const std::vector<double> samples{-1.0, 0.0, 1.0};
    const strok::PlotRaster raster = strok::renderWaveformPlot(samples, 3, 3);
    const strok::Frame frame = strok::plotRasterToFrame(raster, 0, gray(255), gray(0));
    strok::CliOptions options;
    options.width = 3;
    options.height = 3;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(frame, U" @", options, terminal(3, 3), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "3x3\n"
                "32:0,0,0:0,0,0|32:0,0,0:0,0,0|64:255,255,255:0,0,0|\n"
                "32:0,0,0:0,0,0|64:255,255,255:0,0,0|32:0,0,0:0,0,0|\n"
                "64:255,255,255:0,0,0|32:0,0,0:0,0,0|32:0,0,0:0,0,0|\n",
                "stdin waveform source golden frame");
  }

  {
    strok::AsciinemaFrameSource source = strok::AsciinemaFrameSource::fromString(
      "{\"version\":2,\"width\":2,\"height\":1}\n"
      "[0.000000,\"o\",\"A\"]\n");
    const std::optional<strok::Frame> frame = source.nextFrame();
    expect(frame.has_value(), "asciinema source frame exists");
    strok::CliOptions options;
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(*frame, U" @", options, terminal(2, 2), nullptr, &cells);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "64:255,255,255:0,0,0|32:0,0,0:0,0,0|\n"
                "64:255,255,255:0,0,0|32:0,0,0:0,0,0|\n",
                "asciinema source golden frame");
  }

  {
    const strok::SceneMesh mesh = strok::parseObjScene(
      "v -1 -1 0\n"
      "v 1 -1 0\n"
      "v 0 1 0\n"
      "vn 0 0 1\n"
      "f 1//1 2//1 3//1\n");
    strok::SceneGBuffer gbuffer = strok::renderSceneGBuffer(mesh, strok::SceneRenderOptions{.width = 4, .height = 4});
    strok::CliOptions options;
    options.style = "cell-shade";
    options.width = 2;
    options.height = 2;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(gbuffer.albedo, strok::kDefaultGlyphRamp, options, terminal(2, 2), nullptr, &cells, nullptr, nullptr, &gbuffer);
    expectEqual(serializeCells(cells),
                "2x2\n"
                "58:127,127,255:0,0,0|32:0,0,0:0,0,0|\n"
                "58:127,127,255:0,0,0|58:127,127,255:0,0,0|\n",
                "scene source golden frame");
  }

  {
    strok::SceneGBuffer gbuffer;
    gbuffer.albedo = frameFromPixels(4, 2, {
      gray(220), gray(220), gray(220), gray(220),
      gray(220), gray(220), gray(220), gray(220),
    });
    gbuffer.depth.assign(8, 0.0);
    gbuffer.normals = {
      strok::SceneVec3{.x = 1.0}, strok::SceneVec3{.x = 1.0}, strok::SceneVec3{.y = 1.0}, strok::SceneVec3{.y = 1.0},
      strok::SceneVec3{.x = 1.0}, strok::SceneVec3{.x = 1.0}, strok::SceneVec3{.y = 1.0}, strok::SceneVec3{.y = 1.0},
    };
    strok::CliOptions options;
    options.style = "cell-shade";
    options.width = 2;
    options.height = 1;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(gbuffer.albedo, strok::kDefaultGlyphRamp, options, terminal(2, 1), nullptr, &cells, nullptr, nullptr, &gbuffer);
    expect(cells.at(0, 0).glyph == U'─', "scene normal-orient uses x normal");
    expect(cells.at(1, 0).glyph == U'│', "scene normal-orient uses y normal");
  }

  {
    strok::SceneGBuffer gbuffer;
    gbuffer.albedo = frameFromPixels(4, 2, {
      gray(255), gray(255), gray(255), gray(255),
      gray(255), gray(255), gray(255), gray(255),
    });
    gbuffer.depth = {
      0.0, 0.0, 1.0, 1.0,
      0.0, 0.0, 1.0, 1.0,
    };
    gbuffer.normals.assign(8, strok::SceneVec3{.z = 1.0});
    strok::CliOptions options;
    options.style = "cell-shade";
    options.width = 2;
    options.height = 1;
    options.cell_aspect = 1.0;
    strok::CellBuffer cells;
    strok::renderFrame(gbuffer.albedo, strok::kDefaultGlyphRamp, options, terminal(2, 1), nullptr, &cells, nullptr, nullptr, &gbuffer);
    expect(cells.at(0, 0).fg.r > cells.at(1, 0).fg.r, "scene depth-shade darkens far cell");
    expect(cells.at(0, 0).glyph != cells.at(1, 0).glyph, "scene depth-shade shifts ramp glyph");
  }

  {
    const strok::Frame frame = frameFromPixels(8, 8, {
      gray(0), gray(0), gray(0), gray(255), gray(255), gray(255), gray(255), gray(255),
      gray(0), gray(0), gray(0), gray(0), gray(255), gray(255), gray(255), gray(255),
      gray(0), gray(0), gray(0), gray(0), gray(0), gray(255), gray(255), gray(255),
      gray(255), gray(0), gray(0), gray(0), gray(0), gray(0), gray(255), gray(255),
      gray(255), gray(255), gray(0), gray(0), gray(0), gray(0), gray(0), gray(255),
      gray(255), gray(255), gray(255), gray(0), gray(0), gray(0), gray(0), gray(0),
      gray(255), gray(255), gray(255), gray(255), gray(0), gray(0), gray(0), gray(0),
      gray(255), gray(255), gray(255), gray(255), gray(255), gray(0), gray(0), gray(0),
    });
    strok::CliOptions options;
    options.mode = "structure";
    options.width = 4;
    options.height = 4;
    options.cell_aspect = 1.0;
    options.edge_threshold = 0.01;
    const strok::GlyphShapeTable shape_table = strok::buildGlyphShapeTable(strok::kDefaultStructureShapeGlyphs, 10, 14);
    strok::CellBuffer cpu_cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(4, 4), &shape_table, &cpu_cells);
    options.gpu = true;
    strok::CellBuffer gpu_cells;
    strok::renderFrame(frame, strok::kDefaultGlyphRamp, options, terminal(4, 4), &shape_table, &gpu_cells);
    if (strok::gpuSobelAvailable()) {
      expectEqual(serializeCells(gpu_cells), serializeCells(cpu_cells), "gpu structure render parity");
    }
  }

  {
    strok::CliOptions options;
    expectEqual(strok::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "cell-average(cpu)  frame:RgbFrame -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "luminance graph dump golden");
  }

  {
    strok::CliOptions options;
    options.mode = "blocks";
    expectEqual(strok::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "blocks(cpu)  frame:RgbFrame -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "blocks graph dump golden");
  }

  {
    strok::CliOptions options;
    options.mode = "octant";
    expectEqual(strok::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "octant(cpu)  frame:RgbFrame -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "octant graph dump golden");
  }

  {
    strok::CliOptions options;
    options.mode = "octant";
    options.edge_threshold = 0.01;
    expectEqual(strok::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "octant(cpu)  frame:RgbFrame -> base-cells:CellGlyphs\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> gradients:GradientField\n"
                "optical-flow(cpu)  structure-luminance:LuminanceField -> flow:OpticalFlow\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "cell-shape(cpu)  edge-field:EdgeField, base-cells:CellGlyphs -> cell-shapes:CellShapeVectors\n"
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs, cell-shapes:CellShapeVectors -> warped-history:CellGlyphs, warped-shapes:CellShapeVectors\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, warped-shapes:CellShapeVectors, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "octant auto structure overlay graph dump golden");
  }

  {
    strok::CliOptions options;
    options.mode = "octant";
    options.structure_overlay = "on";
    options.line_ligatures = true;
    expectEqual(strok::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "octant(cpu)  frame:RgbFrame -> base-cells:CellGlyphs\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "contrast(cpu)  luminance:LuminanceField -> contrast-luminance:LuminanceField\n"
                "dog(cpu)  contrast-luminance:LuminanceField -> structure-luminance:LuminanceField\n"
                "sobel(cpu)  structure-luminance:LuminanceField -> gradients:GradientField\n"
                "optical-flow(cpu)  structure-luminance:LuminanceField -> flow:OpticalFlow\n"
                "edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField\n"
                "cell-shape(cpu)  edge-field:EdgeField, base-cells:CellGlyphs -> cell-shapes:CellShapeVectors\n"
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs, cell-shapes:CellShapeVectors -> warped-history:CellGlyphs, warped-shapes:CellShapeVectors\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, warped-shapes:CellShapeVectors, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "line-ligatures(cpu)  cells:CellGlyphs -> ligature-cells:CellGlyphs\n"
                "emit(cpu)  ligature-cells:CellGlyphs -> \n",
                "line ligature graph dump golden");
  }

  {
    strok::CliOptions options;
    options.mode = "sextant";
    expectEqual(strok::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "sextant(cpu)  frame:RgbFrame -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "sextant graph dump golden");
  }

  {
    strok::CliOptions options;
    options.mode = "braille";
    expectEqual(strok::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "braille(cpu)  frame:RgbFrame -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "braille graph dump golden");
  }

  {
    strok::CliOptions options;
    options.mode = "structure";
    expectEqual(strok::dumpRenderGraph(options),
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
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs, cell-shapes:CellShapeVectors -> warped-history:CellGlyphs, warped-shapes:CellShapeVectors\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, warped-shapes:CellShapeVectors, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "structure graph dump golden");
  }

  {
    strok::CliOptions options;
    options.mode = "structure";
    options.style = "painterly";
    expectEqual(strok::dumpRenderGraph(options),
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
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs, cell-shapes:CellShapeVectors -> warped-history:CellGlyphs, warped-shapes:CellShapeVectors\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, warped-shapes:CellShapeVectors, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "painterly graph dump golden");
  }

  {
    strok::CliOptions options;
    options.style = "hatch";
    expectEqual(strok::dumpRenderGraph(options),
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
    strok::CliOptions options;
    options.style = "stipple";
    expectEqual(strok::dumpRenderGraph(options),
                "decode(cpu)   -> frame:RgbFrame\n"
                "luminance(cpu)  frame:RgbFrame -> luminance:LuminanceField\n"
                "cell-average(cpu)  frame:RgbFrame -> cell-colors:CellColors\n"
                "ramp-pick(cpu)  cell-colors:CellColors, luminance:LuminanceField -> cells:CellGlyphs\n"
                "stipple(cpu)  cells:CellGlyphs, frame:RgbFrame -> stipple-cells:CellGlyphs\n"
                "emit(cpu)  stipple-cells:CellGlyphs -> \n",
                "stipple graph dump golden");
  }

  {
    strok::CliOptions options;
    options.style = "flow";
    expectEqual(strok::dumpRenderGraph(options),
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
    strok::CliOptions options;
    options.style = "hatch";
    options.posterize = 4;
    expectEqual(strok::dumpRenderGraph(options),
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
    strok::CliOptions options;
    options.style = "cell-shade";
    expectEqual(strok::dumpRenderGraph(options),
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
    strok::CliOptions options;
    options.mode = "structure";
    options.etf_iters = 2;
    expectEqual(strok::dumpRenderGraph(options),
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
                "warp-history(cpu)  flow:OpticalFlow, base-cells:CellGlyphs, cell-shapes:CellShapeVectors -> warped-history:CellGlyphs, warped-shapes:CellShapeVectors\n"
                "overlay-structure(cpu)  edge-field:EdgeField, cell-shapes:CellShapeVectors, warped-history:CellGlyphs, warped-shapes:CellShapeVectors, base-cells:CellGlyphs -> cells:CellGlyphs\n"
                "emit(cpu)  cells:CellGlyphs -> \n",
                "ETF graph dump golden");
  }
}
