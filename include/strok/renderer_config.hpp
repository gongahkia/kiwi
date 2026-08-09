#pragma once

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
  std::string glyph_features = "overlap";
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
  int temporal_supersample = 1;
  bool fit = false;
  bool gpu = false;
  bool line_ligatures = false;
  std::vector<std::string> graph_passes;
};

}  // namespace strok
