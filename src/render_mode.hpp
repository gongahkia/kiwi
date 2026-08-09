#pragma once

#include "../include/strok/graphics_emitter.hpp"

#include "cli.hpp"
#include "terminal_caps.hpp"

#include <string_view>

namespace strok {

enum class ResolvedRenderMode {
  Text,
  Pixel,
  Hybrid,
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

}  // namespace strok
