#include "structure_overlay.hpp"

namespace strok {
namespace {

bool graphImpliesStructure(const CliOptions& options) {
  for (const std::string& pass : options.graph_passes) {
    if (pass == "dog" || pass == "sobel" || pass == "etf" || pass == "edge-field" ||
        pass == "cell-shape" || pass == "overlay-structure" || pass == "shape-match" ||
        pass == "crosshatch" || pass == "lic") {
      return true;
    }
  }
  return false;
}

}  // namespace

bool structureOverlayImplied(const CliOptions& options) {
  return options.mode == "structure" ||
         options.style == "hatch" ||
         options.style == "flow" ||
         graphImpliesStructure(options) ||
         options.edge_threshold.has_value() ||
         options.edge_strength.has_value() ||
         options.dog_sigma.has_value() ||
         options.dog_threshold.has_value() ||
         options.etf_iters.has_value() ||
         options.contrast.has_value() ||
         options.glyph_features != "overlap";
}

bool structureOverlayEnabled(const CliOptions& options) {
  if (options.structure_overlay == "on") {
    return true;
  }
  if (options.structure_overlay == "off") {
    return false;
  }
  return structureOverlayImplied(options);
}

}  // namespace strok
