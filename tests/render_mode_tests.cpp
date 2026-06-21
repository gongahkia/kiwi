#include "render_mode.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

contourtty::CliOptions options(std::string render_mode) {
  contourtty::CliOptions opts;
  opts.render_mode = std::move(render_mode);
  return opts;
}

}  // namespace

int main() {
  {
    const auto resolved = contourtty::resolveRenderMode(options("text"), contourtty::TerminalCaps{.kitty_graphics = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Text, "text stays text");
    expect(resolved.protocol == contourtty::GraphicsProtocol::None, "text has no protocol");
    expect(!resolved.degraded_to_text, "text does not degrade");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("auto"), contourtty::TerminalCaps{});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Text, "auto without graphics falls back text");
    expect(resolved.protocol == contourtty::GraphicsProtocol::None, "auto without graphics has no protocol");
    expect(resolved.degraded_to_text, "auto without graphics records degradation");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("auto"), contourtty::TerminalCaps{.kitty_graphics = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Pixel, "auto kitty picks pixel");
    expect(resolved.protocol == contourtty::GraphicsProtocol::Kitty, "auto kitty protocol");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("auto"), contourtty::TerminalCaps{.sixel = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Pixel, "auto sixel picks pixel");
    expect(resolved.protocol == contourtty::GraphicsProtocol::Sixel, "auto sixel protocol");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("auto"), contourtty::TerminalCaps{.iterm_inline = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Pixel, "auto iTerm picks pixel");
    expect(resolved.protocol == contourtty::GraphicsProtocol::ITermInline, "auto iTerm protocol");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("pixel"), contourtty::TerminalCaps{});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Text, "pixel without graphics falls back text");
    expect(resolved.degraded_to_text, "pixel without graphics records degradation");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("hybrid"), contourtty::TerminalCaps{.kitty_graphics = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Hybrid, "hybrid kitty stays hybrid");
    expect(resolved.protocol == contourtty::GraphicsProtocol::Kitty, "hybrid kitty protocol");
  }

  {
    const auto protocol = contourtty::bestGraphicsProtocol(contourtty::TerminalCaps{.kitty_graphics = true, .sixel = true, .iterm_inline = true});
    expect(protocol == contourtty::GraphicsProtocol::Kitty, "kitty preferred over other protocols");
    expect(contourtty::toString(protocol) == "kitty", "protocol string");
    expect(contourtty::toString(contourtty::ResolvedRenderMode::Hybrid) == "hybrid", "mode string");
  }
}
