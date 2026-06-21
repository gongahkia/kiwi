#include "auto_mode.hpp"

namespace contourtty {
namespace {

bool structureImplied(const CliOptions& options) {
  return options.edge_threshold.has_value() ||
         options.edge_strength.has_value() ||
         options.dog_sigma.has_value() ||
         options.dog_threshold.has_value() ||
         options.contrast.has_value() ||
         options.glyph_features != "overlap";
}

}  // namespace

void resolveAutoMode(CliOptions* options, const TerminalCaps& caps) {
  if (options->mode != "auto") {
    return;
  }
  if (caps.truecolor && caps.font_has_octants) {
    options->mode = "octant";
    return;
  }
  if (caps.truecolor && caps.font_has_sextants) {
    options->mode = "sextant";
    return;
  }
  if (caps.truecolor && caps.font_has_braille) {
    options->mode = "luminance";
    options->charset = "braille";
    return;
  }
  if (caps.truecolor) {
    options->mode = "halfblock";
    return;
  }
  options->mode = structureImplied(*options) ? "structure" : "luminance";
}

}  // namespace contourtty
