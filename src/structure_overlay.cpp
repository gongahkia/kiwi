#include "structure_overlay.hpp"

namespace contourtty {

bool structureOverlayImplied(const CliOptions& options) {
  return options.mode == "structure" ||
         options.edge_threshold.has_value() ||
         options.edge_strength.has_value() ||
         options.dog_sigma.has_value() ||
         options.dog_threshold.has_value() ||
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

}  // namespace contourtty
