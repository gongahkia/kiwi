#include "../include/strok/render.hpp"
#include "../include/strok/renderer.hpp"

#include "glyph_font.hpp"
#include "glyph_hog.hpp"
#include "glyph_kdtree.hpp"
#include "glyph_ramp.hpp"
#include "glyph_sdf.hpp"
#include "glyph_shape.hpp"
#include "gpu_backend.hpp"
#include "renderer.hpp"
#include "structure_overlay.hpp"

#include <exception>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>

namespace strok {
namespace {

std::u32string rampFromConfig(const RendererConfig& config, const GlyphFont* glyph_font) {
  std::u32string ramp = kDefaultGlyphRamp.data();
  const bool packed_braille = config.charset.has_value() && isBrailleCharset(*config.charset);
  if (config.charset.has_value() && !packed_braille) {
    ramp = resolveCharsetRamp(*config.charset);
  }
  if (config.ramp_sort && !packed_braille) {
    if (glyph_font == nullptr) {
      throw std::invalid_argument("ramp sorting requires a font path");
    }
    ramp = sortRampByInkDensity(ramp, *glyph_font, 10, 14);
  }
  return ramp;
}

std::optional<GlyphShapeTable> shapeTableFromConfig(const RendererConfig& config, const GlyphFont* glyph_font) {
  if (!structureOverlayEnabled(config)) {
    return std::nullopt;
  }
  if (config.glyph_features == "hog") {
    GlyphShapeTable table = glyph_font == nullptr
                              ? buildHogGlyphShapeTable(kDefaultStructureShapeGlyphs, 10, 14)
                              : buildHogGlyphShapeTable(*glyph_font, kDefaultStructureShapeGlyphs, 10, 14);
    attachGlyphKdTree(&table);
    return table;
  }
  if (config.glyph_features == "sdf") {
    return glyph_font == nullptr
             ? buildSdfGlyphShapeTable(kDefaultStructureShapeGlyphs, 10, 14)
             : buildSdfGlyphShapeTable(*glyph_font, kDefaultStructureShapeGlyphs, 10, 14);
  }
  return glyph_font == nullptr
           ? buildGlyphShapeTable(kDefaultStructureShapeGlyphs, 10, 14)
           : buildGlyphShapeTable(*glyph_font, kDefaultStructureShapeGlyphs, 10, 14);
}

}  // namespace

struct Renderer::State {
  RendererConfig config;
  RenderGrid grid;
  std::optional<GlyphFont> glyph_font;
  std::u32string ramp;
  std::optional<GlyphShapeTable> shape_table;
  std::unique_ptr<GpuAnalysisBackend> gpu_backend;
  Graph graph;
  RenderTemporalState temporal_state;
  CellBuffer cells;

  State(RendererConfig renderer_config, RenderGrid renderer_grid)
      : config(std::move(renderer_config)), grid(renderer_grid) {
    if (config.font_path.has_value()) {
      glyph_font.emplace(*config.font_path);
    }
    ramp = rampFromConfig(config, glyph_font.has_value() ? &*glyph_font : nullptr);
    shape_table = shapeTableFromConfig(config, glyph_font.has_value() ? &*glyph_font : nullptr);
    gpu_backend = createGpuAnalysisBackend(config.gpu);
    graph = buildRendererGraphTopology(config, gpu_backend->backend());
  }
};

RenderResult renderFrame(const Frame& frame, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, CellBuffer* output) {
  return renderFrame(frame, ramp, config, available_grid, nullptr, output, nullptr);
}

RenderResult renderFrame(const ColorImageView& image, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, CellBuffer* output) {
  return renderFrame(image, ramp, config, available_grid, nullptr, output, nullptr);
}

RenderResult renderFrame(const RenderInput& input, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, CellBuffer* output) {
  return renderFrame(input, ramp, config, available_grid, nullptr, output, nullptr);
}

Renderer::Renderer(RendererConfig config, RenderGrid grid)
    : state_(std::make_unique<State>(std::move(config), grid)) {}

Renderer::~Renderer() = default;

Renderer::CreateResult Renderer::create(RendererConfig config, RenderGrid grid) {
  const RenderResult validation = validateRendererConfiguration(config, grid);
  if (!validation.succeeded()) {
    return CreateResult{.result = validation};
  }
  try {
    return CreateResult{
      .renderer = std::unique_ptr<Renderer>(new Renderer(std::move(config), grid)),
      .result = RenderResult{},
    };
  } catch (const std::runtime_error& error) {
    return CreateResult{.result = RenderResult{
                          .status = RenderStatus::InvalidConfiguration,
                          .message = error.what(),
                        }};
  } catch (const std::exception& error) {
    return CreateResult{.result = RenderResult{
                          .status = RenderStatus::InternalError,
                          .message = error.what(),
                        }};
  } catch (...) {
    return CreateResult{.result = RenderResult{
                          .status = RenderStatus::InternalError,
                          .message = "unexpected renderer initialization failure",
                        }};
  }
}

RenderResult Renderer::render(const Frame& frame) {
  return render(frame, &state_->cells);
}

RenderResult Renderer::render(const ColorImageView& image) {
  return render(RenderInput{.color = image}, &state_->cells);
}

RenderResult Renderer::render(const RenderInput& input) {
  return render(input, &state_->cells);
}

const CellBuffer& Renderer::cells() const noexcept {
  return state_->cells;
}

RenderResult Renderer::render(const Frame& frame, CellBuffer* output) {
  const std::optional<ColorImageView> image = colorImageViewFromFrame(frame);
  if (!image.has_value()) {
    return RenderResult{
      .status = RenderStatus::InvalidInput,
      .message = "frame RGB buffer does not match its dimensions",
    };
  }
  return render(RenderInput{.color = *image}, output);
}

RenderResult Renderer::render(const ColorImageView& image, CellBuffer* output) {
  return render(RenderInput{.color = image}, output);
}

RenderResult Renderer::render(const RenderInput& input, CellBuffer* output) {
  return renderFrame(input, state_->ramp, state_->config, state_->grid, state_->shape_table.has_value() ? &*state_->shape_table : nullptr, output, &state_->temporal_state, &state_->graph, state_->gpu_backend.get());
}

void Renderer::reset() {
  state_->temporal_state.reset();
}

}  // namespace strok
