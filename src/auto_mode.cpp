#include "auto_mode.hpp"

#include "structure_overlay.hpp"

namespace contourtty {

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
    options->mode = "braille";
    return;
  }
  if (caps.truecolor) {
    options->mode = "halfblock";
    return;
  }
  options->mode = structureOverlayEnabled(*options) ? "structure" : "luminance";
}

}  // namespace contourtty
