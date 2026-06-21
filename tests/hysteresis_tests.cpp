#include "hysteresis.hpp"

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

}  // namespace

int main() {
  contourtty::GlyphHysteresisState state;
  state.resize(1, 1);

  auto first = state.choose(0, contourtty::GlyphShapeMatch{.glyph = U'|', .score = 1.0}, 0.0, 0.05);
  expect(first.glyph == U'|' && !first.kept_previous, "first glyph stores without hysteresis");

  auto near_tie = state.choose(0, contourtty::GlyphShapeMatch{.glyph = U'/', .score = 1.0}, 0.96, 0.05);
  expect(near_tie.glyph == U'|' && near_tie.kept_previous, "near-tied glyph keeps previous");

  auto clear_winner = state.choose(0, contourtty::GlyphShapeMatch{.glyph = U'/', .score = 1.0}, 0.90, 0.05);
  expect(clear_winner.glyph == U'/' && !clear_winner.kept_previous, "clear winner switches glyph");

  state.resize(2, 1);
  auto after_resize = state.choose(1, contourtty::GlyphShapeMatch{.glyph = U'\\', .score = 1.0}, 1.0, 0.05);
  expect(after_resize.glyph == U'\\' && !after_resize.kept_previous, "resize clears glyph history");

  bool out_of_range = false;
  try {
    (void)state.choose(2, contourtty::GlyphShapeMatch{.glyph = U'-', .score = 1.0}, 1.0, 0.05);
  } catch (const std::out_of_range&) {
    out_of_range = true;
  }
  expect(out_of_range, "invalid hysteresis index rejected");
}
