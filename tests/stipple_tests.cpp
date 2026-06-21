#include "stipple.hpp"

#include <cstddef>
#include <cstdlib>
#include <iostream>
#include <set>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  {
    std::set<int> values;
    int low = 0;
    int high = 0;
    int low_neighbors = 0;
    for (int y = 0; y < 64; ++y) {
      for (int x = 0; x < 64; ++x) {
        const int rank = contourtty::blueNoiseRank64(x, y);
        values.insert(rank);
        low += rank < 32 ? 1 : 0;
        high += rank > 223 ? 1 : 0;
        if (rank < 32) {
          low_neighbors += contourtty::blueNoiseRank64(x + 1, y) < 32 ? 1 : 0;
          low_neighbors += contourtty::blueNoiseRank64(x, y + 1) < 32 ? 1 : 0;
        }
      }
    }
    expect(values.size() > 200, "blue noise tile spans most byte ranks");
    expect(low > 100 && high > 100, "blue noise tile has low and high ranks");
    expect(low_neighbors < 40, "blue noise low ranks avoid adjacent clusters");
    expect(contourtty::blueNoiseRank64(0, 0) == contourtty::blueNoiseRank64(64, 64), "blue noise tile wraps");
  }

  {
    expect(contourtty::stippleGlyphForLuminance(1.0, 0) == U' ', "white cell stays blank");
    expect(contourtty::stippleGlyphForLuminance(0.0, 255) == U' ', "noise can drop darkest dot at max threshold");
    expect(contourtty::stippleGlyphForLuminance(0.0, 0) == U'●', "dark cell gets dense dot");
    expect(contourtty::stippleGlyphForLuminance(0.45, 0) == U'∙', "mid shade gets mid dot");
    expect(contourtty::stippleCarrierFromMode("braille") == contourtty::StippleCarrier::Braille, "braille mode selects braille carrier");
    expect(contourtty::stippleCarrierFromMode("octant") == contourtty::StippleCarrier::Octant, "octant mode selects octant carrier");
    expect(contourtty::stippleCarrierFromMode("luminance") == contourtty::StippleCarrier::Cell, "luminance mode selects cell carrier");
  }

  {
    contourtty::CellBuffer cells(1, 1);
    cells.at(0, 0).fg = contourtty::Rgb{.r = 0, .g = 0, .b = 0};
    contourtty::applyStipple(&cells);
    expect(cells.at(0, 0).glyph != U' ', "applyStipple writes dot glyph");
  }

  {
    contourtty::CellBuffer cells(1, 1);
    cells.at(0, 0).fg = contourtty::Rgb{.r = 0, .g = 0, .b = 0};
    contourtty::applyStipple(&cells, contourtty::StippleCarrier::Braille);
    expect(cells.at(0, 0).glyph >= 0x2800 && cells.at(0, 0).glyph <= 0x28ff, "braille carrier packs stipple dots");
  }

  {
    contourtty::CellBuffer cells(1, 1);
    cells.at(0, 0).fg = contourtty::Rgb{.r = 0, .g = 0, .b = 0};
    contourtty::applyStipple(&cells, contourtty::StippleCarrier::Octant);
    expect(cells.at(0, 0).glyph != U' ', "octant carrier packs stipple dots");
  }

  {
    contourtty::Frame frame;
    frame.w = 2;
    frame.h = 4;
    frame.rgb.assign(static_cast<std::size_t>(frame.w * frame.h * 3), 255);
    frame.rgb[0] = 0;
    frame.rgb[1] = 0;
    frame.rgb[2] = 0;
    contourtty::CellBuffer cells(1, 1);
    cells.at(0, 0).fg = contourtty::Rgb{.r = 255, .g = 255, .b = 255};
    contourtty::applyStipple(&cells, contourtty::StippleCarrier::Braille, &frame);
    expect(cells.at(0, 0).glyph == U'\u2801', "braille carrier samples source subcells");
  }
}
