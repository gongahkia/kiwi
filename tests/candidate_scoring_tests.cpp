#include "candidate_scoring.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  const strok::CandidateScore baseline{.reconstruction = 0.80};
  expect(baseline.total() == 0.80, "zero optional terms preserve reconstruction score");

  const strok::CandidateScore balanced{
    .reconstruction = 0.80,
    .temporal = 0.10,
    .presentation_cost = 0.15,
  };
  expect(balanced.total() == 0.75, "score breakdown separates quality, temporal, and presentation terms");
  expect(strok::candidatePreferred(baseline, balanced), "higher total candidate is preferred");

  const strok::CandidateScore best{.reconstruction = 1.0};
  const strok::CandidateScore near_tie{.reconstruction = 0.96};
  const strok::CandidateScore clear_loser{.reconstruction = 0.90};
  expect(strok::candidateWithinTemporalMargin(near_tie, best, 0.05), "zero-term temporal margin preserves prior near-tie rule");
  expect(!strok::candidateWithinTemporalMargin(clear_loser, best, 0.05), "zero-term temporal margin rejects clear reconstruction loss");
}
