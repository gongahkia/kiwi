#pragma once

#include "cli.hpp"
#include "renderer.hpp"

namespace strok {

RendererConfig rendererConfigFromCliOptions(const CliOptions& options);
void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats = nullptr, RenderTemporalState* temporal_state = nullptr, const SceneGBuffer* scene_gbuffer = nullptr);
std::string dumpRenderGraph(const CliOptions& options);

}  // namespace strok
