#include "hybrid_emitter.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  contourtty::CellBuffer cells(2, 1);
  cells.at(0, 0) = contourtty::Cell{
    .glyph = U'|',
    .fg = contourtty::Rgb{.r = 255, .g = 0, .b = 0},
  };
  cells.at(1, 0) = contourtty::Cell{
    .glyph = U' ',
    .fg = contourtty::Rgb{.r = 0, .g = 255, .b = 0},
  };

  {
    const contourtty::HybridFrameResult frame = contourtty::emitHybridFrame(cells, contourtty::HybridFrameOptions{
      .graphics = contourtty::GraphicsFrameOptions{
        .protocol = contourtty::GraphicsProtocol::Kitty,
        .image_id = 9,
        .placement_id = 10,
      },
      .text = contourtty::EmissionOptions{.color_mode = contourtty::ColorMode::Truecolor},
      .terminal = contourtty::TerminalSize{.cols = 10, .rows = 5},
    });
    expect(frame.raster_bytes > 0, "hybrid emits raster bytes");
    expect(frame.overlay_cells == 1, "hybrid overlays nonblank cells only");
    expect(frame.bytes.find("\x1b[3;5H\x1b_Ga=T,t=d,f=24") == 0, "hybrid starts graphics at centered origin");
    expect(frame.bytes.find("\x1b[3;5H") != std::string::npos, "hybrid overlays centered text cell");
    expect(frame.bytes.find("\x1b[38;2;255;0;0m|") != std::string::npos, "hybrid writes foreground glyph");
    expect(frame.bytes.find("\x1b[48;2;") == std::string::npos, "hybrid text overlay avoids background fill");
  }

  {
    const contourtty::HybridFrameResult frame = contourtty::emitHybridFrame(cells, contourtty::HybridFrameOptions{
      .graphics = contourtty::GraphicsFrameOptions{.protocol = contourtty::GraphicsProtocol::ITermInline},
      .text = contourtty::EmissionOptions{.color_mode = contourtty::ColorMode::Mono},
      .terminal = contourtty::TerminalSize{.cols = 2, .rows = 1},
    });
    expect(frame.overlay_cells == 1, "mono hybrid overlay count");
    expect(frame.bytes.find("\x1b[38;") == std::string::npos, "mono hybrid overlay omits sgr");
  }
}
