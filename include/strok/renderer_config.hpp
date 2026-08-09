#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
struct RendererConfig {
  std::optional<int> width;
  std::optional<int> height;
  double cell_aspect = 0.5;
  std::string mode = "luminance";
  std::string style = "none";
  std::string structure_overlay = "auto";
  std::optional<std::string> font_path;
  std::string glyph_features = "overlap";
  bool ramp_sort = false;
  std::optional<std::string> charset;
  std::optional<double> edge_threshold;
  std::optional<double> edge_strength;
  std::optional<double> dog_sigma;
  std::optional<double> dog_sigma2;
  std::optional<double> dog_threshold;
  std::optional<int> etf_iters;
  std::optional<int> lic_length;
  std::optional<int> posterize;
  std::optional<double> contrast;
  std::optional<double> glyph_stickiness;
  std::optional<double> orient_stickiness;
  // ANSI-specific score penalty per estimated changed-cell byte. This is off
  // unless set to a positive value; it is not a whole-frame emitter optimum.
  std::optional<double> presentation_cost_weight;
  // Maximum modeled symbolic update units per completed CellBuffer frame. One
  // unit is one changed cell in the ANSI transition model; this does not control
  // terminal writes, transport lifetime, or frame scheduling. Unset disables
  // budget observation and does not change reconstruction choices.
  std::optional<int64_t> symbolic_update_budget;
  int temporal_supersample = 1;
  // Makes a valid prior CellBuffer an opt-in structure candidate. Reuse requires
  // the existing glyph stickiness margin, current shape score, and exact colors.
  bool temporal_cell_reuse = false;
  bool fit = false;
  bool gpu = false;
  bool line_ligatures = false;
  // Enables exact final CellBuffer delta counters in RenderStats. This is off by
  // default so normal rendering does not scan the completed cell grid twice.
  bool collect_symbolic_metrics = false;
  std::vector<std::string> graph_passes;
};

}  // namespace strok
