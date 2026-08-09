#pragma once

#include "candidate_scoring.hpp"

#include <cstddef>
#include <optional>
#include <vector>

namespace strok {

struct GlyphHysteresisDecision {
  char32_t glyph = U' ';
  CandidateScore score;
  bool kept_previous = false;
};

struct OrientationHysteresisDecision {
  char32_t glyph = U' ';
  double orientation = 0.0;
  bool kept_previous = false;
};

class GlyphHysteresisState {
 public:
  void reset();
  void resize(int cols, int rows);
  void clear(std::size_t index);
  void replace(std::size_t index, char32_t glyph, CandidateScore score);
  GlyphHysteresisDecision choose(std::size_t index,
                                 GlyphCandidate best,
                                 CandidateScore previous_score,
                                 double stickiness,
                                 std::optional<char32_t> history_glyph = std::nullopt);

 private:
  struct Entry {
    char32_t glyph = U' ';
    CandidateScore score;
    bool valid = false;
  };

  int cols_ = 0;
  int rows_ = 0;
  std::vector<Entry> entries_;
};

class OrientationHysteresisState {
 public:
  void reset();
  void resize(int cols, int rows);
  void clear(std::size_t index);
  OrientationHysteresisDecision choose(std::size_t index, char32_t glyph, double orientation, double stickiness);

 private:
  struct Entry {
    char32_t glyph = U' ';
    double orientation = 0.0;
    bool valid = false;
  };

  int cols_ = 0;
  int rows_ = 0;
  std::vector<Entry> entries_;
};

}  // namespace strok
