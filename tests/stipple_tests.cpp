#include "stipple.hpp"

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
    for (int y = 0; y < 64; ++y) {
      for (int x = 0; x < 64; ++x) {
        const int rank = contourtty::blueNoiseRank64(x, y);
        values.insert(rank);
        low += rank < 32 ? 1 : 0;
        high += rank > 223 ? 1 : 0;
      }
    }
    expect(values.size() > 200, "blue noise tile spans most byte ranks");
    expect(low > 100 && high > 100, "blue noise tile has low and high ranks");
    expect(contourtty::blueNoiseRank64(0, 0) == contourtty::blueNoiseRank64(64, 64), "blue noise tile wraps");
  }

  {
    expect(contourtty::stippleGlyphForLuminance(1.0, 0) == U' ', "white cell stays blank");
    expect(contourtty::stippleGlyphForLuminance(0.0, 255) == U' ', "noise can drop darkest dot at max threshold");
    expect(contourtty::stippleGlyphForLuminance(0.0, 0) == U'●', "dark cell gets dense dot");
    expect(contourtty::stippleGlyphForLuminance(0.45, 0) == U'∙', "mid shade gets mid dot");
  }

  {
    contourtty::CellBuffer cells(1, 1);
    cells.at(0, 0).fg = contourtty::Rgb{.r = 0, .g = 0, .b = 0};
    contourtty::applyStipple(&cells);
    expect(cells.at(0, 0).glyph != U' ', "applyStipple writes dot glyph");
  }
}
