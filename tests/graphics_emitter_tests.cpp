#include "graphics_emitter.hpp"
#include "raster_compose.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

contourtty::CellBuffer oneCell() {
  contourtty::CellBuffer cells(1, 1);
  cells.at(0, 0) = contourtty::Cell{
    .glyph = U'█',
    .fg = contourtty::Rgb{.r = 255, .g = 0, .b = 0},
    .bg = contourtty::Rgb{},
  };
  return cells;
}

}  // namespace

int main() {
  {
    const auto frame = contourtty::emitGraphicsFrame(oneCell(), contourtty::GraphicsFrameOptions{
      .protocol = contourtty::GraphicsProtocol::Kitty,
      .image_id = 5,
      .placement_id = 6,
    });
    expect(frame.raster_bytes == 1U * contourtty::kRasterCellPixelWidth * contourtty::kRasterCellPixelHeight * 3U, "kitty raster byte count");
    expect(frame.bytes.find("\x1b_Ga=T,t=d,f=24,s=8,v=12,i=5,p=6") == 0, "kitty frame escape prefix");
    expect(frame.bytes.find(",c=1,r=1,") != std::string::npos, "kitty cell placement dimensions");
  }

  {
    const auto frame = contourtty::emitGraphicsFrame(oneCell(), contourtty::GraphicsFrameOptions{
      .protocol = contourtty::GraphicsProtocol::ITermInline,
    });
    expect(frame.raster_bytes == 1U * contourtty::kRasterCellPixelWidth * contourtty::kRasterCellPixelHeight * 3U, "iTerm raster byte count");
    expect(frame.bytes.find("\x1b]1337;File=inline=1") == 0, "iTerm frame escape prefix");
    expect(frame.bytes.find(";width=1;height=1;") != std::string::npos, "iTerm cell dimensions");
  }

  {
    bool threw = false;
    try {
      (void)contourtty::emitGraphicsFrame(oneCell(), contourtty::GraphicsFrameOptions{.protocol = contourtty::GraphicsProtocol::Sixel});
    } catch (const std::runtime_error&) {
      threw = true;
    }
    expect(threw, "sixel emitter blocked until encoder exists");
  }
}
