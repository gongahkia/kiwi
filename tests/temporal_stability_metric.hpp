#pragma once

#include <strok/cell_buffer.hpp>

#include <cstdint>
#include <stdexcept>
#include <vector>

namespace strok_test {

struct TemporalStability {
  // Cell churn is changed_cells / compared_cells. Keep its exact numerator and
  // denominator so this renderer-only metric is repeatable and does not imply
  // anything about terminal emission cost.
  std::uint64_t compared_cells = 0;
  std::uint64_t changed_cells = 0;
  std::uint64_t glyph_changes = 0;
  std::uint64_t color_changes = 0;

  bool operator==(const TemporalStability&) const = default;
};

inline TemporalStability measureChurn(const strok::CellBuffer& previous, const strok::CellBuffer& current) {
  if (previous.cols() != current.cols() || previous.rows() != current.rows()) {
    throw std::invalid_argument("temporal metric dimensions must match");
  }
  TemporalStability metric;
  metric.compared_cells = static_cast<std::uint64_t>(current.size());
  for (std::size_t index = 0; index < current.size(); ++index) {
    const strok::Cell& before = previous.cells()[index];
    const strok::Cell& after = current.cells()[index];
    const bool glyph_changed = before.glyph != after.glyph;
    const bool color_changed = before.fg != after.fg || before.bg != after.bg;
    metric.glyph_changes += glyph_changed ? 1U : 0U;
    metric.color_changes += color_changed ? 1U : 0U;
    metric.changed_cells += glyph_changed || color_changed ? 1U : 0U;
  }
  return metric;
}

inline TemporalStability measureSequence(const std::vector<strok::CellBuffer>& frames) {
  TemporalStability total;
  for (std::size_t index = 1; index < frames.size(); ++index) {
    const TemporalStability frame_metric = measureChurn(frames[index - 1], frames[index]);
    total.compared_cells += frame_metric.compared_cells;
    total.changed_cells += frame_metric.changed_cells;
    total.glyph_changes += frame_metric.glyph_changes;
    total.color_changes += frame_metric.color_changes;
  }
  return total;
}

}  // namespace strok_test
