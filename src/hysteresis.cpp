#include "hysteresis.hpp"

#include <algorithm>
#include <stdexcept>

namespace contourtty {

void GlyphHysteresisState::reset() {
  cols_ = 0;
  rows_ = 0;
  entries_.clear();
}

void GlyphHysteresisState::resize(int cols, int rows) {
  if (cols <= 0 || rows <= 0) {
    throw std::invalid_argument("hysteresis dimensions must be positive");
  }
  if (cols == cols_ && rows == rows_) {
    return;
  }
  cols_ = cols;
  rows_ = rows;
  entries_.assign(static_cast<std::size_t>(cols_) * static_cast<std::size_t>(rows_), Entry{});
}

GlyphHysteresisDecision GlyphHysteresisState::choose(std::size_t index, GlyphShapeMatch best, double previous_score, double stickiness) {
  if (index >= entries_.size()) {
    throw std::out_of_range("hysteresis cell index out of range");
  }
  const Entry previous = entries_[index];
  GlyphHysteresisDecision decision{.glyph = best.glyph, .score = best.score, .kept_previous = false};
  if (previous.valid && previous.glyph != best.glyph && stickiness > 0.0) {
    const double margin = std::clamp(stickiness, 0.0, 1.0);
    if (previous_score >= best.score * (1.0 - margin)) {
      decision = GlyphHysteresisDecision{.glyph = previous.glyph, .score = previous_score, .kept_previous = true};
    }
  }
  entries_[index] = Entry{.glyph = decision.glyph, .score = decision.score, .valid = true};
  return decision;
}

}  // namespace contourtty
