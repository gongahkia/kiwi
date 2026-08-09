#include "structure_overlay.hpp"

namespace strok {
namespace {

bool graphImpliesStructure(const RendererConfig& config) {
  for (const std::string& pass : config.graph_passes) {
    if (pass == "dog" || pass == "sobel" || pass == "etf" || pass == "edge-field" ||
        pass == "cell-shape" || pass == "overlay-structure" || pass == "shape-match" ||
        pass == "crosshatch" || pass == "lic") {
      return true;
    }
  }
  return false;
}

}  // namespace

bool structureOverlayImplied(const RendererConfig& config) {
  return config.mode == "structure" ||
         config.style == "hatch" ||
         config.style == "flow" ||
         graphImpliesStructure(config) ||
         config.edge_threshold.has_value() ||
         config.edge_strength.has_value() ||
         config.dog_sigma.has_value() ||
         config.dog_threshold.has_value() ||
         config.etf_iters.has_value() ||
         config.contrast.has_value() ||
         config.glyph_features != "overlap";
}

bool structureOverlayEnabled(const RendererConfig& config) {
  if (config.structure_overlay == "on") {
    return true;
  }
  if (config.structure_overlay == "off") {
    return false;
  }
  return structureOverlayImplied(config);
}

}  // namespace strok
