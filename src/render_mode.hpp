#pragma once

#include "cli.hpp"
#include "terminal_caps.hpp"

#include <string_view>

namespace contourtty {

enum class ResolvedRenderMode {
  Text,
  Pixel,
  Hybrid,
};

enum class GraphicsProtocol {
  None,
  Kitty,
  Sixel,
  ITermInline,
};

struct RenderModeResolution {
  ResolvedRenderMode mode = ResolvedRenderMode::Text;
  GraphicsProtocol protocol = GraphicsProtocol::None;
  bool degraded_to_text = false;
};

GraphicsProtocol bestGraphicsProtocol(const TerminalCaps& caps);
RenderModeResolution resolveRenderMode(const CliOptions& options, const TerminalCaps& caps);
std::string_view toString(ResolvedRenderMode mode);
std::string_view toString(GraphicsProtocol protocol);

}  // namespace contourtty
