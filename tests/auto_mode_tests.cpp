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

contourtty::CliOptions autoOptions() {
  contourtty::CliOptions options;
  options.mode = "auto";
  return options;
}

}  // namespace

int main() {
  {
    contourtty::CliOptions options = autoOptions();
    contourtty::resolveAutoMode(&options, contourtty::TerminalCaps{.truecolor = true, .font_has_octants = true});
    expect(options.mode == "octant", "auto picks octant");
  }

  {
    contourtty::CliOptions options = autoOptions();
    contourtty::resolveAutoMode(&options, contourtty::TerminalCaps{.truecolor = true, .font_has_sextants = true});
    expect(options.mode == "sextant", "auto picks sextant");
  }

  {
    contourtty::CliOptions options = autoOptions();
    contourtty::resolveAutoMode(&options, contourtty::TerminalCaps{.truecolor = true, .font_has_braille = true});
    expect(options.mode == "braille", "auto picks packed braille mode");
  }

  {
    contourtty::CliOptions options = autoOptions();
    contourtty::resolveAutoMode(&options, contourtty::TerminalCaps{.truecolor = true});
    expect(options.mode == "halfblock", "auto truecolor fallback");
  }

  {
    contourtty::CliOptions options = autoOptions();
    options.edge_threshold = 0.2;
    contourtty::resolveAutoMode(&options, contourtty::TerminalCaps{});
    expect(options.mode == "structure", "auto structure fallback");
  }

  {
    contourtty::CliOptions options = autoOptions();
    contourtty::resolveAutoMode(&options, contourtty::TerminalCaps{});
    expect(options.mode == "luminance", "auto luminance fallback");
  }

  {
    contourtty::CliOptions options;
    options.mode = "octant";
    contourtty::resolveAutoMode(&options, contourtty::TerminalCaps{});
    expect(options.mode == "octant", "non-auto unchanged");
  }
}
