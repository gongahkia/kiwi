#include "hysteresis.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

double alternatingGlyphChangeRate(double stickiness) {
  constexpr std::size_t kCells = 8;
  constexpr int kFrames = 12;
  contourtty::GlyphHysteresisState state;
  state.resize(static_cast<int>(kCells), 1);
  std::vector<char32_t> previous(kCells, U'\0');
  int changes = 0;
  int comparisons = 0;
  for (int frame = 0; frame < kFrames; ++frame) {
    for (std::size_t index = 0; index < kCells; ++index) {
      const char32_t best_glyph = ((frame + static_cast<int>(index)) % 2 == 0) ? U'|' : U'/';
      const auto decision = state.choose(index,
                                         contourtty::GlyphShapeMatch{.glyph = best_glyph, .score = 1.0},
                                         0.97,
                                         stickiness);
      if (previous[index] != U'\0') {
        changes += decision.glyph != previous[index] ? 1 : 0;
        ++comparisons;
      }
      previous[index] = decision.glyph;
    }
  }
  return static_cast<double>(changes) / static_cast<double>(comparisons);
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

  auto warped_tie = state.choose(0, contourtty::GlyphShapeMatch{.glyph = U'\\', .score = 1.0}, 0.98, 0.05, U'-');
  expect(warped_tie.glyph == U'-' && warped_tie.kept_previous, "warped near-tied glyph keeps motion-compensated history");

  state.resize(2, 1);
  auto after_resize = state.choose(1, contourtty::GlyphShapeMatch{.glyph = U'\\', .score = 1.0}, 1.0, 0.05);
  expect(after_resize.glyph == U'\\' && !after_resize.kept_previous, "resize clears glyph history");

  state.reset();
  state.resize(1, 1);
  auto after_reset = state.choose(0, contourtty::GlyphShapeMatch{.glyph = U'-', .score = 1.0}, 1.0, 0.05);
  expect(after_reset.glyph == U'-' && !after_reset.kept_previous, "reset clears glyph history");

  bool out_of_range = false;
  try {
    (void)state.choose(2, contourtty::GlyphShapeMatch{.glyph = U'-', .score = 1.0}, 1.0, 0.05);
  } catch (const std::out_of_range&) {
    out_of_range = true;
  }
  expect(out_of_range, "invalid hysteresis index rejected");

  const double unstuck_rate = alternatingGlyphChangeRate(0.0);
  const double default_rate = alternatingGlyphChangeRate(0.05);
  expect(std::abs(unstuck_rate - 1.0) < 0.001, "flicker metric baseline changes every frame");
  expect(default_rate <= 0.40 * unstuck_rate, "default stickiness keeps flicker metric below threshold");

  contourtty::OrientationHysteresisState orientation_state;
  orientation_state.resize(1, 1);
  auto orient_first = orientation_state.choose(0, U'|', 0.0, 0.15);
  expect(orient_first.glyph == U'|' && !orient_first.kept_previous, "first orientation stores without hysteresis");

  auto orient_near = orientation_state.choose(0, U'/', 0.10, 0.15);
  expect(orient_near.glyph == U'|' && orient_near.kept_previous, "near orientation bucket keeps previous");

  auto orient_far = orientation_state.choose(0, U'/', 0.50, 0.15);
  expect(orient_far.glyph == U'/' && !orient_far.kept_previous, "far orientation bucket switches glyph");

  orientation_state.reset();
  orientation_state.resize(1, 1);
  auto orient_after_reset = orientation_state.choose(0, U'\\', 0.0, 0.15);
  expect(orient_after_reset.glyph == U'\\' && !orient_after_reset.kept_previous, "orientation reset clears history");
}
