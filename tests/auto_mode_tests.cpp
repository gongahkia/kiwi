#include "auto_mode.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::CliOptions autoOptions() {
  strok::CliOptions options;
  options.mode = "auto";
  return options;
}

}  // namespace

int main() {
  {
    strok::CliOptions options = autoOptions();
    strok::resolveAutoMode(&options, strok::TerminalCaps{.truecolor = true, .font_has_octants = true});
    expect(options.mode == "octant", "auto picks octant");
  }

  {
    strok::CliOptions options = autoOptions();
    strok::resolveAutoMode(&options, strok::TerminalCaps{.truecolor = true, .font_has_sextants = true});
    expect(options.mode == "sextant", "auto picks sextant");
  }

  {
    strok::CliOptions options = autoOptions();
    strok::resolveAutoMode(&options, strok::TerminalCaps{.truecolor = true, .font_has_braille = true});
    expect(options.mode == "braille", "auto picks packed braille mode");
  }

  {
    strok::CliOptions options = autoOptions();
    strok::resolveAutoMode(&options, strok::TerminalCaps{.truecolor = true});
    expect(options.mode == "halfblock", "auto truecolor fallback");
  }

  {
    strok::CliOptions options = autoOptions();
    options.edge_threshold = 0.2;
    strok::resolveAutoMode(&options, strok::TerminalCaps{});
    expect(options.mode == "structure", "auto structure fallback");
  }

  {
    strok::CliOptions options = autoOptions();
    options.structure_overlay = "off";
    options.edge_threshold = 0.2;
    strok::resolveAutoMode(&options, strok::TerminalCaps{});
    expect(options.mode == "luminance", "auto overlay off fallback");
  }

  {
    strok::CliOptions options = autoOptions();
    options.structure_overlay = "on";
    strok::resolveAutoMode(&options, strok::TerminalCaps{});
    expect(options.mode == "structure", "auto overlay on fallback");
  }

  {
    strok::CliOptions options = autoOptions();
    strok::resolveAutoMode(&options, strok::TerminalCaps{});
    expect(options.mode == "luminance", "auto luminance fallback");
  }

  {
    strok::CliOptions options;
    options.mode = "octant";
    strok::resolveAutoMode(&options, strok::TerminalCaps{});
    expect(options.mode == "octant", "non-auto unchanged");
  }
}
