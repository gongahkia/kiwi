#pragma once

#include "glyph_shape.hpp"

#include <cstddef>
#include <vector>

namespace contourtty {

struct GlyphHysteresisDecision {
  char32_t glyph = U' ';
  double score = 0.0;
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
  GlyphHysteresisDecision choose(std::size_t index, GlyphShapeMatch best, double previous_score, double stickiness);

 private:
  struct Entry {
    char32_t glyph = U' ';
    double score = 0.0;
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

}  // namespace contourtty
