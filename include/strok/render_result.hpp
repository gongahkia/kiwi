#pragma once

#include <cstdint>
#include <string>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
enum class RenderStatus {
  Success,
  BackendFallback,
  InvalidInput,
  InvalidConfiguration,
  InternalError,
};

struct RenderStats {
  int64_t frames = 0;
  int64_t cells = 0;
  // Reconstruction time only; media decode and terminal or graphics emission are
  // outside this interval.
  int64_t render_ns = 0;
  // Exact final CellBuffer deltas relative to the output buffer before rendering.
  // These are zero unless RendererConfig::collect_symbolic_metrics is enabled.
  // A missing or differently sized prior buffer counts every current cell as changed.
  int64_t changed_glyphs = 0;
  int64_t changed_foregrounds = 0;
  int64_t changed_backgrounds = 0;
  int64_t changed_cells = 0;
  int64_t shape_match_cells = 0;
  int64_t shape_match_ns = 0;
  int64_t optical_flow_blocks = 0;
  int64_t optical_flow_ns = 0;
  // Per-frame temporal history selection counts; these exclude terminal emission.
  int64_t external_motion_cells = 0;
  int64_t inferred_motion_cells = 0;
  int64_t history_suppressed_cells = 0;
  int64_t temporal_cell_candidate_cells = 0;
  int64_t temporal_cell_reused_cells = 0;
  // Sums over the current and retained candidates evaluated where valid
  // full-cell temporal history exists. They are score diagnostics, not output
  // emitter measurements.
  double temporal_candidate_reconstruction_score = 0.0;
  double temporal_candidate_temporal_score = 0.0;
  double temporal_candidate_presentation_cost = 0.0;
  int64_t warp_history_cells = 0;
  int64_t warp_history_ns = 0;
  int64_t temporal_supersample_frames = 0;
  int64_t temporal_supersample_ns = 0;
};

struct RenderResult {
  RenderStatus status = RenderStatus::Success;
  std::string message;
  RenderStats stats;

  bool succeeded() const noexcept {
    return status == RenderStatus::Success || status == RenderStatus::BackendFallback;
  }
};

}  // namespace strok
