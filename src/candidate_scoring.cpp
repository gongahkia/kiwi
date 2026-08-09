#include "candidate_scoring.hpp"

#include <algorithm>

namespace strok {

double CandidateScore::total() const noexcept {
  return reconstruction + temporal - presentation_cost;
}

bool candidatePreferred(const CandidateScore& candidate, const CandidateScore& incumbent) noexcept {
  return candidate.total() > incumbent.total();
}

bool candidateWithinTemporalMargin(const CandidateScore& candidate,
                                   const CandidateScore& best,
                                   double stickiness) noexcept {
  const double margin = std::clamp(stickiness, 0.0, 1.0);
  return candidate.total() >= best.total() * (1.0 - margin);
}

}  // namespace strok
