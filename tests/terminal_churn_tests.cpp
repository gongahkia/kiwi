#include "diff_emitter.hpp"
#include "temporal_stability_metric.hpp"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

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

strok::CellBuffer frame(std::u32string_view glyphs) {
  expect(glyphs.size() == 8, "fixture grid has eight cells");
  strok::CellBuffer result(4, 2);
  for (std::size_t index = 0; index < glyphs.size(); ++index) {
    result.cells()[index] = cell(glyphs[index]);
  }
  return result;
}

struct PresentationMeasurements {
  // Symbolic deltas are exact CellBuffer comparisons; emission values are produced
  // independently by DiffEmitter with its default truecolor ANSI policy.
  strok_test::TemporalStability symbolic;
  std::vector<std::size_t> emitted_cells;
  std::vector<std::size_t> emitted_bytes;
};

PresentationMeasurements measurePresentation(const std::vector<strok::CellBuffer>& frames) {
  PresentationMeasurements measurements;
  measurements.symbolic = strok_test::measureSequence(frames);
  strok::DiffEmitter emitter;
  for (const strok::CellBuffer& cells : frames) {
    const strok::EmissionResult emission = emitter.emit(cells);
    measurements.emitted_cells.push_back(emission.changed_cells);
    measurements.emitted_bytes.push_back(emission.bytes.size());
  }
  return measurements;
}

void expectEmission(const PresentationMeasurements& measurements,
                    std::vector<std::size_t> changed_cells,
                    std::vector<std::size_t> bytes,
                    const char* label) {
  expect(measurements.emitted_cells == changed_cells && measurements.emitted_bytes == bytes, label);
}

}  // namespace

int main() {
  const strok::CellBuffer base = frame(U"ABCDEFGH");

  strok::CellBuffer sparse_changed = base;
  sparse_changed.at(1, 0).glyph = U'Z';
  const PresentationMeasurements sparse = measurePresentation({base, sparse_changed});
  expect(sparse.symbolic.compared_cells == 8 && sparse.symbolic.glyph_changes == 1 &&
             sparse.symbolic.color_changes == 0 && sparse.symbolic.changed_cells == 1,
         "sparse fixture has one symbolic glyph update");
  expectEmission(sparse, {8, 1}, {49, 36}, "sparse fixture ANSI baseline");

  const strok::CellBuffer dense_changed = frame(U"IJKLMNOP");
  const PresentationMeasurements dense = measurePresentation({base, dense_changed});
  expect(dense.symbolic.compared_cells == 8 && dense.symbolic.glyph_changes == 8 &&
             dense.symbolic.color_changes == 0 && dense.symbolic.changed_cells == 8,
         "dense fixture changes every symbolic glyph");
  expectEmission(dense, {8, 8}, {49, 49}, "dense fixture ANSI baseline");

  strok::CellBuffer color_changed = base;
  color_changed.at(1, 0).fg = strok::Rgb{.r = 11, .g = 20, .b = 30};
  const PresentationMeasurements color_only = measurePresentation({base, color_changed});
  expect(color_only.symbolic.compared_cells == 8 && color_only.symbolic.glyph_changes == 0 &&
             color_only.symbolic.color_changes == 1 && color_only.symbolic.changed_cells == 1,
         "color-only fixture keeps glyphs while changing one symbolic cell");
  expectEmission(color_only, {8, 1}, {49, 36}, "color-only fixture ANSI baseline");

  const PresentationMeasurements motion = measurePresentation({
    frame(U"1234abcd"),
    frame(U"4123dabc"),
    frame(U"3412cdab"),
  });
  expect(motion.symbolic.compared_cells == 16 && motion.symbolic.glyph_changes == 16 &&
             motion.symbolic.color_changes == 0 && motion.symbolic.changed_cells == 16,
         "scrolling fixture records deterministic scene-wide symbolic churn");
  expectEmission(motion, {8, 8, 8}, {49, 49, 49}, "scrolling fixture ANSI baseline");
}
