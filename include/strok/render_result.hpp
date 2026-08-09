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
  int64_t render_ns = 0;
  int64_t shape_match_cells = 0;
  int64_t shape_match_ns = 0;
  int64_t optical_flow_blocks = 0;
  int64_t optical_flow_ns = 0;
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
