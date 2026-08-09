#include <strok/diff_emitter.hpp>

#include <cstdlib>

int main() {
  strok::CellBuffer cells(1, 1);
  cells.at(0, 0) = strok::Cell{
    .glyph = U'█',
    .fg = strok::Rgb{.r = 255, .g = 0, .b = 0},
  };

  strok::DiffEmitter emitter;
  const strok::EmissionResult first = emitter.emit(cells);
  if (first.changed_cells != 1 || first.bytes.empty()) {
    return EXIT_FAILURE;
  }
  const strok::EmissionResult unchanged = emitter.emit(cells);
  if (unchanged.changed_cells != 0 || !unchanged.bytes.empty()) {
    return EXIT_FAILURE;
  }
  emitter.reset();
  const strok::EmissionResult after_reset = emitter.emit(cells);
  return after_reset.changed_cells == 1 && !after_reset.bytes.empty() ? EXIT_SUCCESS : EXIT_FAILURE;
}
