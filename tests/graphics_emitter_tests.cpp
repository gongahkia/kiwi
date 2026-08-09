#include "graphics_emitter.hpp"
#include "iterm_inline.hpp"
#include "raster_compose.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

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

std::string hexBytes(std::string_view bytes) {
  constexpr char digits[] = "0123456789abcdef";
  std::string out;
  out.reserve(bytes.size() * 2U);
  for (const unsigned char byte : bytes) {
    out.push_back(digits[byte >> 4U]);
    out.push_back(digits[byte & 0x0fU]);
  }
  return out;
}

std::string repeatString(std::string_view text, int count) {
  std::string out;
  for (int i = 0; i < count; ++i) {
    out += text;
  }
  return out;
}

strok::CellBuffer oneCell() {
  strok::CellBuffer cells(1, 1);
  cells.at(0, 0) = strok::Cell{
    .glyph = U'█',
    .fg = strok::Rgb{.r = 255, .g = 0, .b = 0},
    .bg = strok::Rgb{},
  };
  return cells;
}

strok::CellBuffer twoCells(strok::Rgb right) {
  strok::CellBuffer cells(2, 1);
  cells.at(0, 0) = strok::Cell{
    .glyph = U'█',
    .fg = strok::Rgb{.r = 255, .g = 0, .b = 0},
    .bg = strok::Rgb{},
  };
  cells.at(1, 0) = strok::Cell{
    .glyph = U'█',
    .fg = right,
    .bg = strok::Rgb{},
  };
  return cells;
}

}  // namespace

int main() {
  {
    const auto frame = strok::emitGraphicsFrame(oneCell(), strok::GraphicsFrameOptions{
      .protocol = strok::GraphicsProtocol::Kitty,
      .image_id = 5,
      .placement_id = 6,
    });
    expect(frame.raster_bytes == 1U * strok::kRasterCellPixelWidth * strok::kRasterCellPixelHeight * 3U, "kitty raster byte count");
    expect(frame.bytes.find("\x1b_Ga=T,t=d,f=24,s=8,v=12,i=5,p=6") == 0, "kitty frame escape prefix");
    expect(frame.bytes.find(",c=1,r=1,") != std::string::npos, "kitty cell placement dimensions");
    const std::string expected_hex = "1b5f47613d542c743d642c663d32342c733d382c763d31322c693d352c703d362c713d322c633d312c723d312c433d312c6d3d303b" +
                                     repeatString("2f774141", 96) + "1b5c";
    expectEqual(hexBytes(frame.bytes),
                expected_hex,
                "kitty graphics frame golden bytes");
  }

  {
    strok::GraphicsFrameState state;
    const auto first = strok::emitGraphicsFrame(twoCells(strok::Rgb{.r = 0, .g = 0, .b = 255}), strok::GraphicsFrameOptions{
                                                                                                       .protocol = strok::GraphicsProtocol::Kitty,
                                                                                                       .image_id = 8,
                                                                                                       .placement_id = 9,
                                                                                                     },
                                                     &state);
    const auto second = strok::emitGraphicsFrame(twoCells(strok::Rgb{.r = 0, .g = 255, .b = 0}), strok::GraphicsFrameOptions{
                                                                                                        .protocol = strok::GraphicsProtocol::Kitty,
                                                                                                        .image_id = 8,
                                                                                                        .placement_id = 9,
                                                                                                      },
                                                      &state);
    const auto third = strok::emitGraphicsFrame(twoCells(strok::Rgb{.r = 0, .g = 255, .b = 0}), strok::GraphicsFrameOptions{
                                                                                                       .protocol = strok::GraphicsProtocol::Kitty,
                                                                                                       .image_id = 8,
                                                                                                       .placement_id = 9,
                                                                                                     },
                                                     &state);
    expect(first.bytes.find("\x1b_Ga=T,t=d,f=24,s=16,v=12,i=8,p=9") == 0, "stateful kitty first frame is full upload");
    expect(second.bytes.find("\x1b_Ga=f,t=d,f=24,i=8,r=1,x=8,y=0,s=8,v=12") == 0, "stateful kitty second frame is cropped delta");
    expect(second.bytes.find("\x1b_Ga=a,i=8,c=1,q=2;") != std::string::npos, "stateful kitty delta selects root frame");
    expect(second.bytes.size() < first.bytes.size(), "stateful kitty delta is smaller than full upload");
    expect(third.bytes.empty(), "stateful kitty unchanged frame emits nothing");
  }

  {
    const auto frame = strok::emitGraphicsFrame(oneCell(), strok::GraphicsFrameOptions{
      .protocol = strok::GraphicsProtocol::ITermInline,
    });
    expect(frame.raster_bytes == 1U * strok::kRasterCellPixelWidth * strok::kRasterCellPixelHeight * 3U, "iTerm raster byte count");
    expect(frame.bytes.find("\x1b]1337;File=inline=1") == 0, "iTerm frame escape prefix");
    expect(frame.bytes.find(";width=1;height=1;") != std::string::npos, "iTerm cell dimensions");
    std::vector<uint8_t> expected_raster(frame.raster_bytes, 0);
    for (std::size_t pixel = 0; pixel < expected_raster.size(); pixel += 3U) {
      expected_raster[pixel] = 255;
    }
    expectEqual(frame.bytes,
                strok::encodeITermInlineRgb24(expected_raster,
                                               strok::kRasterCellPixelWidth,
                                               strok::kRasterCellPixelHeight,
                                               strok::ITermInlineOptions{.width = "1", .height = "1"}),
                "iTerm graphics frame bytes");
  }

  {
    const auto frame = strok::emitGraphicsFrame(oneCell(), strok::GraphicsFrameOptions{.protocol = strok::GraphicsProtocol::Sixel});
    expect(frame.raster_bytes == 1U * strok::kRasterCellPixelWidth * strok::kRasterCellPixelHeight * 3U, "sixel raster byte count");
    expect(frame.bytes.find("\x1bPq") == 0, "sixel frame escape prefix");
    expect(frame.bytes.find("#9;2;100;0;0") != std::string::npos, "sixel palette defines red register");
    expect(frame.bytes.find("#9!8~") != std::string::npos, "sixel red full-cell run encoded");
    expect(frame.bytes.ends_with("\x1b\\"), "sixel frame terminator");
  }
}
