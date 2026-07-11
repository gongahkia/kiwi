#include "block_sad.hpp"

#include "frame_sampling.hpp"
#include "luminance.hpp"

#include <array>
#include <cmath>
#include <limits>

namespace strok {
namespace {

struct BlockCandidate {
  char32_t glyph = U' ';
  std::array<double, 4> alpha{};
};

constexpr std::array<BlockCandidate, 20> kCandidates {{
  BlockCandidate{.glyph = U' ', .alpha = {0.0, 0.0, 0.0, 0.0}},
  BlockCandidate{.glyph = U'░', .alpha = {0.25, 0.25, 0.25, 0.25}},
  BlockCandidate{.glyph = U'▒', .alpha = {0.50, 0.50, 0.50, 0.50}},
  BlockCandidate{.glyph = U'▓', .alpha = {0.75, 0.75, 0.75, 0.75}},
  BlockCandidate{.glyph = U'▘', .alpha = {1.0, 0.0, 0.0, 0.0}},
  BlockCandidate{.glyph = U'▝', .alpha = {0.0, 1.0, 0.0, 0.0}},
  BlockCandidate{.glyph = U'▀', .alpha = {1.0, 1.0, 0.0, 0.0}},
  BlockCandidate{.glyph = U'▖', .alpha = {0.0, 0.0, 1.0, 0.0}},
  BlockCandidate{.glyph = U'▌', .alpha = {1.0, 0.0, 1.0, 0.0}},
  BlockCandidate{.glyph = U'▞', .alpha = {0.0, 1.0, 1.0, 0.0}},
  BlockCandidate{.glyph = U'▛', .alpha = {1.0, 1.0, 1.0, 0.0}},
  BlockCandidate{.glyph = U'▗', .alpha = {0.0, 0.0, 0.0, 1.0}},
  BlockCandidate{.glyph = U'▚', .alpha = {1.0, 0.0, 0.0, 1.0}},
  BlockCandidate{.glyph = U'▐', .alpha = {0.0, 1.0, 0.0, 1.0}},
  BlockCandidate{.glyph = U'▜', .alpha = {1.0, 1.0, 0.0, 1.0}},
  BlockCandidate{.glyph = U'▄', .alpha = {0.0, 0.0, 1.0, 1.0}},
  BlockCandidate{.glyph = U'▙', .alpha = {1.0, 0.0, 1.0, 1.0}},
  BlockCandidate{.glyph = U'▟', .alpha = {0.0, 1.0, 1.0, 1.0}},
  BlockCandidate{.glyph = U'█', .alpha = {1.0, 1.0, 1.0, 1.0}},
  BlockCandidate{.glyph = U'·', .alpha = {0.10, 0.10, 0.10, 0.10}},
}};

double sad(const std::array<double, 4>& samples, const BlockCandidate& candidate) {
  double error = 0.0;
  for (std::size_t i = 0; i < samples.size(); ++i) {
    error += std::abs(samples[i] - candidate.alpha[i]);
  }
  return error;
}

}  // namespace

char32_t blockGlyphForSamples(const std::array<double, 4>& samples) {
  char32_t best = U' ';
  double best_error = std::numeric_limits<double>::infinity();
  for (const BlockCandidate& candidate : kCandidates) {
    const double error = sad(samples, candidate);
    if (error < best_error) {
      best_error = error;
      best = candidate.glyph;
    }
  }
  return best;
}

void renderBlockSadFrame(const Frame& frame, int cols, int rows, CellBuffer* cells) {
  cells->resize(cols, rows);
  const int sample_cols = cols * 2;
  const int sample_rows = rows * 2;
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      std::array<double, 4> samples{};
      for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
          samples[static_cast<std::size_t>(y * 2 + x)] = relativeLuminance(averageRegion(frame, sample_cols, sample_rows, col * 2 + x, row * 2 + y));
        }
      }
      Cell& cell = cells->at(col, row);
      cell.glyph = blockGlyphForSamples(samples);
      cell.fg = averageRegion(frame, cols, rows, col, row);
      cell.bg = Rgb{};
    }
  }
}

}  // namespace strok
