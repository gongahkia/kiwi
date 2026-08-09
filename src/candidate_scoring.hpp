#pragma once

#include <cstdint>

namespace strok {

// Internal reconstruction-candidate score terms. Higher total score wins;
// presentation_cost is subtracted so it remains visibly distinct from quality.
struct CandidateScore {
  double reconstruction = 0.0;
  double temporal = 0.0;
  double presentation_cost = 0.0;

  double total() const noexcept;
};

struct GlyphCandidate {
  char32_t glyph = U' ';
  CandidateScore score;
};

bool candidatePreferred(const CandidateScore& candidate, const CandidateScore& incumbent) noexcept;
bool candidateWithinTemporalMargin(const CandidateScore& candidate,
                                   const CandidateScore& best,
                                   double stickiness) noexcept;

}  // namespace strok
