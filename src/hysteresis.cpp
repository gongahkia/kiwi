#include "hysteresis.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace strok {
namespace {

constexpr double kPi = 3.14159265358979323846;

double angularDistance(double a, double b) {
  double delta = std::fmod(std::abs(a - b), 2.0 * kPi);
  if (delta > kPi) {
    delta = 2.0 * kPi - delta;
  }
  return delta;
}

}  // namespace

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

void GlyphHysteresisState::clear(std::size_t index) {
  if (index >= entries_.size()) {
    throw std::out_of_range("hysteresis cell index out of range");
  }
  entries_[index] = Entry{};
}

GlyphHysteresisDecision GlyphHysteresisState::choose(std::size_t index,
                                                      GlyphCandidate best,
                                                      CandidateScore previous_score,
                                                      double stickiness,
                                                      std::optional<char32_t> history_glyph) {
  if (index >= entries_.size()) {
    throw std::out_of_range("hysteresis cell index out of range");
  }
  const Entry previous = entries_[index];
  const char32_t candidate_glyph = history_glyph.value_or(previous.glyph);
  GlyphHysteresisDecision decision{.glyph = best.glyph, .score = best.score, .kept_previous = false};
  if (previous.valid && candidate_glyph != best.glyph && stickiness > 0.0) {
    if (candidateWithinTemporalMargin(previous_score, best.score, stickiness)) {
      decision = GlyphHysteresisDecision{.glyph = candidate_glyph, .score = previous_score, .kept_previous = true};
    }
  }
  entries_[index] = Entry{.glyph = decision.glyph, .score = decision.score, .valid = true};
  return decision;
}

void OrientationHysteresisState::reset() {
  cols_ = 0;
  rows_ = 0;
  entries_.clear();
}

void OrientationHysteresisState::resize(int cols, int rows) {
  if (cols <= 0 || rows <= 0) {
    throw std::invalid_argument("orientation hysteresis dimensions must be positive");
  }
  if (cols == cols_ && rows == rows_) {
    return;
  }
  cols_ = cols;
  rows_ = rows;
  entries_.assign(static_cast<std::size_t>(cols_) * static_cast<std::size_t>(rows_), Entry{});
}

void OrientationHysteresisState::clear(std::size_t index) {
  if (index >= entries_.size()) {
    throw std::out_of_range("orientation hysteresis cell index out of range");
  }
  entries_[index] = Entry{};
}

OrientationHysteresisDecision OrientationHysteresisState::choose(std::size_t index, char32_t glyph, double orientation, double stickiness) {
  if (index >= entries_.size()) {
    throw std::out_of_range("orientation hysteresis cell index out of range");
  }
  const Entry previous = entries_[index];
  OrientationHysteresisDecision decision{.glyph = glyph, .orientation = orientation, .kept_previous = false};
  if (previous.valid && previous.glyph != glyph && stickiness > 0.0) {
    const double margin = std::clamp(stickiness, 0.0, kPi);
    if (angularDistance(previous.orientation, orientation) <= margin) {
      decision = OrientationHysteresisDecision{.glyph = previous.glyph, .orientation = previous.orientation, .kept_previous = true};
    }
  }
  entries_[index] = Entry{.glyph = decision.glyph, .orientation = decision.orientation, .valid = true};
  return decision;
}

}  // namespace strok
