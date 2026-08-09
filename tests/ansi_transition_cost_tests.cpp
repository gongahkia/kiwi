#include "ansi_transition_cost.hpp"
#include "diff_emitter.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::Cell cell(char32_t glyph, uint8_t red = 10, uint8_t green = 20, uint8_t blue = 30) {
  return strok::Cell{
    .glyph = glyph,
    .fg = strok::Rgb{.r = red, .g = green, .b = blue},
    .bg = strok::Rgb{},
  };
}

struct FrameEstimate {
  std::size_t ansi_bytes = 0;
  std::size_t update_units = 0;
};

FrameEstimate estimateFrame(const strok::CellBuffer& previous, const strok::CellBuffer& current) {
  expect(previous.cols() == current.cols() && previous.rows() == current.rows(), "estimate fixtures keep dimensions");
  FrameEstimate total;
  strok::AnsiTransitionContext context;
  for (int row = 0; row < current.rows(); ++row) {
    for (int col = 0; col < current.cols(); ++col) {
      const strok::AnsiTransitionEstimate estimate = strok::estimateAnsiCellTransition(
        previous.at(col, row), current.at(col, row), row + 1, col + 1, context);
      total.ansi_bytes += estimate.ansi_bytes;
      total.update_units += estimate.update_units;
      context = estimate.next_context;
    }
  }
  return total;
}

void expectMatchesEmitter(const strok::CellBuffer& previous, const strok::CellBuffer& current, const char* label) {
  strok::DiffEmitter emitter;
  (void)emitter.emit(previous);
  const strok::EmissionResult emitted = emitter.emit(current);
  const FrameEstimate estimate = estimateFrame(previous, current);
  expect(estimate.ansi_bytes == emitted.bytes.size() && estimate.update_units == emitted.changed_cells, label);
}

}  // namespace

int main() {
  strok::CellBuffer previous(3, 1);
  previous.at(0, 0) = cell(U'A');
  previous.at(1, 0) = cell(U'B');
  previous.at(2, 0) = cell(U'C');

  expectMatchesEmitter(previous, previous, "unchanged transition has no cost");

  strok::CellBuffer glyph_changed = previous;
  glyph_changed.at(1, 0).glyph = U'Z';
  expectMatchesEmitter(previous, glyph_changed, "glyph transition matches ANSI emitter");

  strok::CellBuffer foreground_changed = previous;
  foreground_changed.at(1, 0).fg = strok::Rgb{.r = 40, .g = 50, .b = 60};
  expectMatchesEmitter(previous, foreground_changed, "foreground transition matches ANSI emitter");

  strok::CellBuffer background_changed = previous;
  background_changed.at(1, 0).bg = strok::Rgb{.r = 7, .g = 8, .b = 9};
  expectMatchesEmitter(previous, background_changed, "background transition matches ANSI emitter");

  strok::CellBuffer adjacent_run = previous;
  adjacent_run.at(0, 0).glyph = U'X';
  adjacent_run.at(1, 0).glyph = U'Y';
  expectMatchesEmitter(previous, adjacent_run, "adjacent run transition matches ANSI emitter");

  strok::CellBuffer wide_glyph_run = previous;
  wide_glyph_run.at(0, 0).glyph = U'\u754c';
  wide_glyph_run.at(1, 0).glyph = U'Y';
  expectMatchesEmitter(previous, wide_glyph_run, "unknown-width glyph starts a new ANSI cursor run");

  const strok::CellBuffer before_estimate = adjacent_run;
  (void)estimateFrame(previous, adjacent_run);
  expect(adjacent_run == before_estimate, "estimation does not mutate CellBuffer results");
}
