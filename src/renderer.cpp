#include "renderer.hpp"

#include "block_sad.hpp"
#include "braille_renderer.hpp"
#include "crosshatch.hpp"
#include "etf.hpp"
#include "frame_sampling.hpp"
#include "glyph_hog.hpp"
#include "glyph_ramp.hpp"
#include "glyph_sdf.hpp"
#include "gpu_sobel.hpp"
#include "halfblock_renderer.hpp"
#include "kuwahara.hpp"
#include "lic.hpp"
#include "line_ligatures.hpp"
#include "luminance.hpp"
#include "octant_renderer.hpp"
#include "optical_flow.hpp"
#include "posterize.hpp"
#include "render_graph.hpp"
#include "render_layout.hpp"
#include "scene_source.hpp"
#include "sextant_renderer.hpp"
#include "stipple.hpp"
#include "structure_edges.hpp"
#include "structure_overlay.hpp"
#include "structure_sampling.hpp"
#include "warp_history.hpp"
#include "worker_count.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace strok {
namespace {

constexpr double kDefaultDogThreshold = 0.02;
constexpr double kDefaultEdgeThreshold = 0.35;
constexpr double kDefaultEdgeStrength = 1.0;
constexpr double kPi = 3.14159265358979323846;

struct ShapeMatchStats {
  int64_t cells = 0;
  int64_t ns = 0;
};

struct SceneCellSample {
  Rgb color;
  SceneVec3 normal;
  double depth = 0.0;
};

struct SceneDepthRange {
  double near = 0.0;
  double far = 0.0;
};

PassPort renderPort(std::string name, BufferKind kind) {
  return PassPort{
    .name = std::move(name),
    .desc = BufferDesc{.kind = kind},
  };
}

SceneVec3 normalizeSceneVec(SceneVec3 value) {
  const double length = std::sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
  if (length <= 1.0e-12) {
    return SceneVec3{.z = 1.0};
  }
  return SceneVec3{.x = value.x / length, .y = value.y / length, .z = value.z / length};
}

bool sceneGBufferUsable(const SceneGBuffer& gbuffer) {
  const std::size_t pixels = static_cast<std::size_t>(gbuffer.albedo.w) * static_cast<std::size_t>(gbuffer.albedo.h);
  return gbuffer.albedo.w > 0 &&
         gbuffer.albedo.h > 0 &&
         gbuffer.albedo.rgb.size() == pixels * 3U &&
         gbuffer.depth.size() == pixels &&
         gbuffer.normals.size() == pixels;
}

std::optional<SceneDepthRange> sceneDepthRange(const SceneGBuffer& gbuffer) {
  std::optional<SceneDepthRange> range;
  for (const double depth : gbuffer.depth) {
    if (!std::isfinite(depth)) {
      continue;
    }
    if (!range.has_value()) {
      range = SceneDepthRange{.near = depth, .far = depth};
      continue;
    }
    range->near = std::min(range->near, depth);
    range->far = std::max(range->far, depth);
  }
  return range;
}

std::optional<SceneCellSample> sampleSceneCell(const SceneGBuffer& gbuffer, int cols, int rows, int col, int row) {
  if (!sceneGBufferUsable(gbuffer) || cols <= 0 || rows <= 0) {
    return std::nullopt;
  }
  const int x0 = (col * gbuffer.albedo.w) / cols;
  const int x1 = std::max(x0 + 1, ((col + 1) * gbuffer.albedo.w) / cols);
  const int y0 = (row * gbuffer.albedo.h) / rows;
  const int y1 = std::max(y0 + 1, ((row + 1) * gbuffer.albedo.h) / rows);
  uint64_t r = 0;
  uint64_t g = 0;
  uint64_t b = 0;
  double nx = 0.0;
  double ny = 0.0;
  double nz = 0.0;
  double depth_sum = 0.0;
  uint64_t count = 0;
  for (int y = y0; y < y1; ++y) {
    for (int x = x0; x < x1; ++x) {
      const std::size_t index = static_cast<std::size_t>(y) * static_cast<std::size_t>(gbuffer.albedo.w) + static_cast<std::size_t>(x);
      const double depth = gbuffer.depth[index];
      if (!std::isfinite(depth)) {
        continue;
      }
      r += gbuffer.albedo.rgb[index * 3U];
      g += gbuffer.albedo.rgb[index * 3U + 1U];
      b += gbuffer.albedo.rgb[index * 3U + 2U];
      nx += gbuffer.normals[index].x;
      ny += gbuffer.normals[index].y;
      nz += gbuffer.normals[index].z;
      depth_sum += depth;
      ++count;
    }
  }
  if (count == 0) {
    return std::nullopt;
  }
  return SceneCellSample{
    .color = Rgb{
      .r = static_cast<uint8_t>(r / count),
      .g = static_cast<uint8_t>(g / count),
      .b = static_cast<uint8_t>(b / count),
    },
    .normal = normalizeSceneVec(SceneVec3{.x = nx, .y = ny, .z = nz}),
    .depth = depth_sum / static_cast<double>(count),
  };
}

double angularDistance(double a, double b) {
  double delta = std::fmod(std::abs(a - b), 2.0 * kPi);
  if (delta > kPi) {
    delta = 2.0 * kPi - delta;
  }
  return delta;
}

char32_t sceneOrientationGlyph(double orientation) {
  struct Candidate {
    double angle;
    char32_t glyph;
  };
  const Candidate candidates[] = {
    Candidate{.angle = 0.0, .glyph = U'│'},
    Candidate{.angle = kPi, .glyph = U'│'},
    Candidate{.angle = -kPi, .glyph = U'│'},
    Candidate{.angle = kPi / 2.0, .glyph = U'─'},
    Candidate{.angle = -kPi / 2.0, .glyph = U'─'},
    Candidate{.angle = kPi / 4.0, .glyph = U'╱'},
    Candidate{.angle = -3.0 * kPi / 4.0, .glyph = U'╱'},
    Candidate{.angle = -kPi / 4.0, .glyph = U'╲'},
    Candidate{.angle = 3.0 * kPi / 4.0, .glyph = U'╲'},
  };
  const Candidate* best = &candidates[0];
  double best_distance = angularDistance(orientation, best->angle);
  for (const Candidate& candidate : candidates) {
    const double distance = angularDistance(orientation, candidate.angle);
    if (distance < best_distance) {
      best = &candidate;
      best_distance = distance;
    }
  }
  return best->glyph;
}

bool isSceneOrientationGlyph(char32_t glyph) {
  return glyph == U'│' || glyph == U'─' || glyph == U'╱' || glyph == U'╲';
}

Rgb scaleRgb(Rgb color, double factor) {
  factor = std::clamp(factor, 0.0, 1.0);
  return Rgb{
    .r = static_cast<uint8_t>(std::lround(static_cast<double>(color.r) * factor)),
    .g = static_cast<uint8_t>(std::lround(static_cast<double>(color.g) * factor)),
    .b = static_cast<uint8_t>(std::lround(static_cast<double>(color.b) * factor)),
  };
}

void applySceneNormalOrient(CellBuffer* cells, const SceneGBuffer& gbuffer, int cols, int rows) {
  if (cells == nullptr || cells->cols() != cols || cells->rows() != rows) {
    return;
  }
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      const std::optional<SceneCellSample> sample = sampleSceneCell(gbuffer, cols, rows, col, row);
      if (!sample.has_value()) {
        continue;
      }
      if (std::hypot(sample->normal.x, sample->normal.y) <= 0.08) {
        continue;
      }
      const double tangent = std::atan2(sample->normal.y, sample->normal.x) + kPi / 2.0;
      cells->at(col, row).glyph = sceneOrientationGlyph(tangent);
    }
  }
}

void applySceneDepthShade(CellBuffer* cells, const SceneGBuffer& gbuffer, std::u32string_view ramp, int cols, int rows) {
  if (cells == nullptr || cells->cols() != cols || cells->rows() != rows) {
    return;
  }
  const std::optional<SceneDepthRange> range = sceneDepthRange(gbuffer);
  if (!range.has_value()) {
    return;
  }
  const double span = std::max(range->far - range->near, 1.0e-9);
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      const std::optional<SceneCellSample> sample = sampleSceneCell(gbuffer, cols, rows, col, row);
      Cell& cell = cells->at(col, row);
      if (!sample.has_value()) {
        cell = Cell{};
        continue;
      }
      const double depth_t = std::clamp((sample->depth - range->near) / span, 0.0, 1.0);
      const double facing = std::clamp(sample->normal.z * 0.5 + 0.5, 0.0, 1.0);
      const double factor = (0.55 + facing * 0.45) * (1.0 - depth_t * 0.45);
      cell.fg = scaleRgb(sample->color, factor);
      cell.bg = Rgb{};
      if (!isSceneOrientationGlyph(cell.glyph)) {
        cell.glyph = glyphForLuminance(relativeLuminance(cell.fg), ramp);
      }
    }
  }
}

DogOptions dogOptionsFromConfig(const RendererConfig& config) {
  const double sigma1 = config.dog_sigma.value_or(0.0);
  return DogOptions{
    .sigma1 = sigma1,
    .sigma2 = config.dog_sigma2.value_or(sigma1 > 0.0 ? sigma1 * 2.0 : 0.0),
    .threshold = config.dog_threshold.value_or(kDefaultDogThreshold),
  };
}

double contrastFromConfig(const RendererConfig& config) {
  return config.contrast.value_or(0.0);
}

double edgeThresholdFromConfig(const RendererConfig& config) {
  return config.edge_threshold.value_or(kDefaultEdgeThreshold);
}

double effectiveEdgeThresholdFromConfig(const RendererConfig& config) {
  const double strength = config.edge_strength.value_or(kDefaultEdgeStrength);
  if (strength <= 0.0) {
    return std::numeric_limits<double>::infinity();
  }
  return edgeThresholdFromConfig(config) / strength;
}

int etfIterationsFromConfig(const RendererConfig& config) {
  const bool graph_etf = std::find(config.graph_passes.begin(), config.graph_passes.end(), "etf") != config.graph_passes.end();
  return config.etf_iters.value_or(config.style == "hatch" || config.style == "flow" || graph_etf ? 2 : 0);
}

int licLengthFromConfig(const RendererConfig& config) {
  return config.lic_length.value_or(8);
}

double glyphStickinessFromConfig(const RendererConfig& config) {
  return config.glyph_stickiness.value_or(0.05);
}

bool glyphTemporalEnabledFromConfig(const RendererConfig& config) {
  return glyphStickinessFromConfig(config) > 0.0;
}

double orientationStickinessFromConfig(const RendererConfig& config) {
  return config.orient_stickiness.value_or(0.0);
}

bool orientationTemporalEnabledFromConfig(const RendererConfig& config) {
  return orientationStickinessFromConfig(config) > 0.0;
}

int temporalSupersampleFromConfig(const RendererConfig& config) {
  return std::clamp(config.temporal_supersample, 1, 8);
}

LuminanceField blendTemporalSupersample(const LuminanceField& current, const LuminanceField& adjacent, int samples, bool adjacent_is_future) {
  if (samples <= 1 || current.width != adjacent.width || current.height != adjacent.height || current.values.size() != adjacent.values.size()) {
    return current;
  }
  LuminanceField blended;
  blended.width = current.width;
  blended.height = current.height;
  blended.values.assign(current.values.size(), 0.0);
  for (int sample = 0; sample < samples; ++sample) {
    const double t = adjacent_is_future
                       ? static_cast<double>(sample) / static_cast<double>(samples)
                       : static_cast<double>(sample + 1) / static_cast<double>(samples);
    const double current_weight = adjacent_is_future ? 1.0 - t : t;
    const double adjacent_weight = 1.0 - current_weight;
    for (std::size_t index = 0; index < current.values.size(); ++index) {
      blended.values[index] += (current.values[index] * current_weight) + (adjacent.values[index] * adjacent_weight);
    }
  }
  const double scale = 1.0 / static_cast<double>(samples);
  for (double& value : blended.values) {
    value *= scale;
  }
  return blended;
}

bool painterlyStyleEnabled(const RendererConfig& config) {
  return config.style == "painterly" ||
         std::find(config.graph_passes.begin(), config.graph_passes.end(), "kuwahara") != config.graph_passes.end();
}

bool hatchStyleEnabled(const RendererConfig& config) {
  return config.style == "hatch" ||
         std::find(config.graph_passes.begin(), config.graph_passes.end(), "crosshatch") != config.graph_passes.end();
}

bool stippleStyleEnabled(const RendererConfig& config) {
  return config.style == "stipple" ||
         std::find(config.graph_passes.begin(), config.graph_passes.end(), "stipple") != config.graph_passes.end();
}

bool flowStyleEnabled(const RendererConfig& config) {
  return config.style == "flow" ||
         std::find(config.graph_passes.begin(), config.graph_passes.end(), "lic") != config.graph_passes.end();
}

std::optional<int> posterizeLevelsFromConfig(const RendererConfig& config) {
  if (config.posterize.has_value()) {
    return config.posterize;
  }
  if (config.style == "cell-shade") {
    return 4;
  }
  return std::nullopt;
}

int renderWorkerCount(int cols, int rows) {
  if (rows < 2 || cols * rows < 1024) {
    return 1;
  }
  const unsigned hardware = std::thread::hardware_concurrency();
  const int max_workers = boundedWorkerCount(static_cast<int>(hardware == 0 ? 2 : hardware));
  return std::min(rows, max_workers);
}

GraphBuildOptions renderGraphBuildOptions(const RendererConfig& config) {
  GraphBuildOptions graph_options;
  if (config.style == "cell-shade") {
    graph_options.external_inputs = {"scene-depth", "scene-normals"};
  }
  graph_options.backend_preference = config.gpu
                                       ? std::vector<Backend>{Backend::Metal, Backend::Cpu}
                                       : std::vector<Backend>{Backend::Cpu};
  graph_options.available_backends = {Backend::Cpu};
  if (gpuSobelAvailable()) {
    graph_options.available_backends.push_back(Backend::Metal);
  }
  return graph_options;
}

std::optional<std::string> directBlitterMode(const RendererConfig& config) {
  if (config.mode == "halfblock" || config.mode == "blocks" || config.mode == "octant" || config.mode == "sextant" || config.mode == "braille") {
    return config.mode;
  }
  if (config.charset.has_value() && isBrailleCharset(*config.charset)) {
    return "braille";
  }
  return std::nullopt;
}

std::vector<Pass> renderGraphSkeleton(const RendererConfig& config) {
  const bool overlay_enabled = structureOverlayEnabled(config);
  const bool etf_enabled = etfIterationsFromConfig(config) > 0;
  const bool painterly_enabled = painterlyStyleEnabled(config);
  const bool hatch_enabled = hatchStyleEnabled(config);
  const bool stipple_enabled = stippleStyleEnabled(config);
  const bool flow_enabled = flowStyleEnabled(config);
  const bool scene_cell_shade_enabled = config.style == "cell-shade";
  const std::optional<int> posterize_levels = posterizeLevelsFromConfig(config);
  const bool posterize_enabled = posterize_levels.has_value();
  const bool glyph_temporal_enabled = glyphTemporalEnabledFromConfig(config);
  const std::string source_frame_input = painterly_enabled ? "styled-frame" : "frame";
  const std::string frame_input = posterize_enabled ? "posterized-frame" : source_frame_input;
  const auto decode_pass = [] {
    return Pass{
      .id = "decode",
      .outputs = {renderPort("frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
    };
  };
  const auto emit_pass = [](std::string input) {
    return Pass{
      .id = "emit",
      .inputs = {renderPort(std::move(input), BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    };
  };
  const auto luminance_pass = [&] {
    return Pass{
      .id = "luminance",
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort("luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu},
    };
  };
  const auto append_structure_analysis = [&](std::vector<Pass>* passes) {
    const std::string sobel_output = etf_enabled ? "raw-gradients" : "gradients";
    passes->push_back(Pass{
      .id = "contrast",
      .inputs = {renderPort("luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("contrast-luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu},
    });
    passes->push_back(Pass{
      .id = "dog",
      .inputs = {renderPort("contrast-luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu, Backend::Metal},
    });
    passes->push_back(Pass{
      .id = "sobel",
      .inputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort(sobel_output, BufferKind::GradientField)},
      .supports = {Backend::Cpu, Backend::Metal},
    });
    if (etf_enabled) {
      passes->push_back(Pass{
        .id = "etf",
        .inputs = {renderPort("raw-gradients", BufferKind::GradientField)},
        .outputs = {renderPort("gradients", BufferKind::GradientField)},
        .supports = {Backend::Cpu},
      });
    }
    passes->push_back(Pass{
      .id = "edge-field",
      .inputs = {renderPort("gradients", BufferKind::GradientField)},
      .outputs = {renderPort("edge-field", BufferKind::EdgeField)},
      .supports = {Backend::Cpu},
    });
    if ((glyph_temporal_enabled && !hatch_enabled && !flow_enabled) || (flow_enabled && !hatch_enabled)) {
      passes->push_back(Pass{
        .id = "optical-flow",
        .inputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
        .outputs = {renderPort("flow", BufferKind::OpticalFlow)},
        .supports = {Backend::Cpu},
      });
    }
  };
  const auto append_structure_overlay = [&](std::vector<Pass>* passes, const std::string& base_input) {
    if (hatch_enabled) {
      passes->push_back(Pass{
        .id = "crosshatch",
        .inputs = {renderPort("gradients", BufferKind::GradientField), renderPort(base_input, BufferKind::CellGlyphs)},
        .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
        .supports = {Backend::Cpu},
      });
      return;
    }
    if (flow_enabled) {
      passes->push_back(Pass{
        .id = "lic",
        .inputs = {renderPort("gradients", BufferKind::GradientField), renderPort("flow", BufferKind::OpticalFlow), renderPort(base_input, BufferKind::CellGlyphs)},
        .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
        .supports = {Backend::Cpu},
      });
      return;
    }
    passes->push_back(Pass{
      .id = "cell-shape",
      .inputs = {renderPort("edge-field", BufferKind::EdgeField), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cell-shapes", BufferKind::CellShapeVectors)},
      .supports = {Backend::Cpu},
    });
    if (glyph_temporal_enabled) {
      passes->push_back(Pass{
        .id = "warp-history",
        .inputs = {renderPort("flow", BufferKind::OpticalFlow), renderPort(base_input, BufferKind::CellGlyphs), renderPort("cell-shapes", BufferKind::CellShapeVectors)},
        .outputs = {renderPort("warped-history", BufferKind::CellGlyphs), renderPort("warped-shapes", BufferKind::CellShapeVectors)},
        .supports = {Backend::Cpu},
      });
    }
    passes->push_back(Pass{
      .id = "overlay-structure",
      .inputs = glyph_temporal_enabled
                  ? std::vector<PassPort>{renderPort("edge-field", BufferKind::EdgeField), renderPort("cell-shapes", BufferKind::CellShapeVectors), renderPort("warped-history", BufferKind::CellGlyphs), renderPort("warped-shapes", BufferKind::CellShapeVectors), renderPort(base_input, BufferKind::CellGlyphs)}
                  : std::vector<PassPort>{renderPort("edge-field", BufferKind::EdgeField), renderPort("cell-shapes", BufferKind::CellShapeVectors), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu, Backend::Metal},
    });
  };
  const auto append_line_ligatures = [&](std::vector<Pass>* passes) {
    if (!config.line_ligatures || !overlay_enabled) {
      return std::string("cells");
    }
    passes->push_back(Pass{
      .id = "line-ligatures",
      .inputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .outputs = {renderPort("ligature-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    return std::string("ligature-cells");
  };
  const auto append_stipple = [&](std::vector<Pass>* passes, const std::string& input) {
    if (!stipple_enabled) {
      return input;
    }
    passes->push_back(Pass{
      .id = "stipple",
      .inputs = {renderPort(input, BufferKind::CellGlyphs), renderPort(frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort("stipple-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    return std::string("stipple-cells");
  };
  const auto append_scene_cell_shade = [&](std::vector<Pass>* passes, const std::string& input) {
    if (!scene_cell_shade_enabled) {
      return input;
    }
    passes->push_back(Pass{
      .id = "normal-orient",
      .inputs = {renderPort("scene-normals", BufferKind::NormalBuffer), renderPort(input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("normal-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    passes->push_back(Pass{
      .id = "depth-shade",
      .inputs = {renderPort("scene-depth", BufferKind::DepthBuffer), renderPort("scene-normals", BufferKind::NormalBuffer), renderPort("normal-cells", BufferKind::CellGlyphs)},
      .outputs = {renderPort("scene-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    return std::string("scene-cells");
  };
  const auto emit_styled = [&](std::vector<Pass>* passes, const std::string& input) {
    passes->push_back(emit_pass(append_stipple(passes, append_scene_cell_shade(passes, input))));
  };
  std::vector<Pass> passes;
  passes.push_back(decode_pass());
  if (painterly_enabled) {
    passes.push_back(Pass{
      .id = "kuwahara",
      .inputs = {renderPort("frame", BufferKind::RgbFrame)},
      .outputs = {renderPort("styled-frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
    });
  }
  if (posterize_enabled) {
    passes.push_back(Pass{
      .id = "posterize",
      .inputs = {renderPort(source_frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort("posterized-frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
    });
  }
  if (const std::optional<std::string> blitter = directBlitterMode(config)) {
    const std::string blitter_output = overlay_enabled ? "base-cells" : "cells";
    passes.push_back(Pass{
      .id = *blitter,
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort(blitter_output, BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    if (overlay_enabled) {
      passes.push_back(luminance_pass());
      append_structure_analysis(&passes);
      append_structure_overlay(&passes, blitter_output);
    }
    emit_styled(&passes, append_line_ligatures(&passes));
    return passes;
  }
  passes.push_back(luminance_pass());
  if (overlay_enabled) {
    append_structure_analysis(&passes);
    passes.push_back(Pass{
      .id = "cell-average",
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame), renderPort("gradients", BufferKind::GradientField)},
      .outputs = {renderPort("cell-colors", BufferKind::CellColors)},
      .supports = {Backend::Cpu, Backend::Metal},
    });
    passes.push_back(Pass{
      .id = "ramp-pick",
      .inputs = {renderPort("cell-colors", BufferKind::CellColors), renderPort("luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("base-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    append_structure_overlay(&passes, "base-cells");
    emit_styled(&passes, append_line_ligatures(&passes));
    return passes;
  }
  passes.push_back(Pass{
    .id = "cell-average",
    .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
    .outputs = {renderPort("cell-colors", BufferKind::CellColors)},
    .supports = {Backend::Cpu, Backend::Metal},
  });
  passes.push_back(Pass{
    .id = "ramp-pick",
    .inputs = {renderPort("cell-colors", BufferKind::CellColors), renderPort("luminance", BufferKind::LuminanceField)},
    .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
    .supports = {Backend::Cpu},
  });
  emit_styled(&passes, "cells");
  return passes;
}

}  // namespace

std::string dumpRenderGraph(const RendererConfig& config) {
  return buildGraph(renderGraphSkeleton(config), renderGraphBuildOptions(config)).dump();
}

void renderFrame(const Frame& frame, std::u32string_view ramp, const RendererConfig& config, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats, RenderTemporalState* temporal_state, const SceneGBuffer* scene_gbuffer) {
  const auto render_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
  const RenderSize size = fitRenderSize(frame, config, terminal);
  cells->resize(size.cols, size.rows);
  if (temporal_state != nullptr) {
    temporal_state->glyph_hysteresis.resize(size.cols, size.rows);
    temporal_state->orientation_hysteresis.resize(size.cols, size.rows);
  }
  std::vector<char32_t> previous_glyphs;
  std::vector<CellLuminanceRegion> previous_shape_regions;
  if (temporal_state != nullptr) {
    previous_glyphs.reserve(cells->cells().size());
    for (const Cell& cell : cells->cells()) {
      previous_glyphs.push_back(cell.glyph);
    }
    previous_shape_regions = temporal_state->previous_shape_regions;
  }
  if (stats != nullptr) {
    ++stats->frames;
    stats->cells += static_cast<int64_t>(size.cols) * static_cast<int64_t>(size.rows);
  }

  std::optional<LuminanceField> analysis_luminance;
  std::optional<GradientField> structure_gradients;
  std::optional<LuminanceField> structure_ink;
  std::optional<FlowField> flow_field;
  std::optional<GpuStructureGlyphs> gpu_structure_glyphs;
  std::vector<Rgb> average_colors;
  std::vector<CellLuminanceRegion> cell_shape_regions;
  std::vector<char32_t> warped_previous_glyphs;
  std::vector<CellLuminanceRegion> warped_previous_shape_regions;
  const double edge_threshold = effectiveEdgeThresholdFromConfig(config);
  const double orient_stickiness = orientationStickinessFromConfig(config);
  const bool overlay_enabled = structureOverlayEnabled(config);
  const bool etf_enabled = etfIterationsFromConfig(config) > 0;
  const bool painterly_enabled = painterlyStyleEnabled(config);
  const bool hatch_enabled = hatchStyleEnabled(config);
  const bool stipple_enabled = stippleStyleEnabled(config);
  const StippleCarrier stipple_carrier = stippleCarrierFromMode(config.mode);
  const bool flow_enabled = flowStyleEnabled(config);
  const bool scene_cell_shade_enabled = config.style == "cell-shade";
  const std::optional<int> posterize_levels = posterizeLevelsFromConfig(config);
  const bool posterize_enabled = posterize_levels.has_value();
  const double glyph_stickiness = glyphStickinessFromConfig(config);
  const bool glyph_hysteresis_enabled = temporal_state != nullptr && shape_table != nullptr && glyphTemporalEnabledFromConfig(config);
  const bool orientation_hysteresis_enabled = temporal_state != nullptr && orientationTemporalEnabledFromConfig(config);
  const bool motion_flow_enabled = flow_enabled && temporal_state != nullptr;
  const int temporal_supersample = temporalSupersampleFromConfig(config);
  const std::string source_frame_input = painterly_enabled ? "styled-frame" : "frame";
  const std::string frame_input = posterize_enabled ? "posterized-frame" : source_frame_input;
  Frame styled_frame;
  Frame posterized_frame;
  const Frame* render_frame = &frame;
  const auto active_frame = [&]() -> const Frame& {
    return *render_frame;
  };
  std::vector<ShapeMatchStats> worker_stats;

  const auto finish_stats = [&] {
    if (temporal_state != nullptr) {
      temporal_state->previous_shape_regions = cell_shape_regions;
    }
    if (stats != nullptr) {
      for (const ShapeMatchStats& local_stats : worker_stats) {
        stats->shape_match_cells += local_stats.cells;
        stats->shape_match_ns += local_stats.ns;
      }
      stats->render_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - render_started).count();
    }
  };

  const auto run_graph = [&](std::vector<Pass> passes) {
    Graph graph = buildGraph(std::move(passes), renderGraphBuildOptions(config));
    PassContext context;
    graph.run(context);
  };

  const auto decode_pass = [&] {
    return Pass{
      .id = "decode",
      .outputs = {renderPort("frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
    };
  };

  const auto kuwahara_pass = [&] {
    return Pass{
      .id = "kuwahara",
      .inputs = {renderPort("frame", BufferKind::RgbFrame)},
      .outputs = {renderPort("styled-frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        styled_frame = applyKuwaharaFilter(frame, 2);
        render_frame = &styled_frame;
      },
    };
  };

  const auto posterize_pass = [&] {
    return Pass{
      .id = "posterize",
      .inputs = {renderPort(source_frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort("posterized-frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        posterized_frame = posterizeFrameOklab(active_frame(), *posterize_levels);
        render_frame = &posterized_frame;
      },
    };
  };

  const auto emit_pass = [&](std::string input) {
    return Pass{
      .id = "emit",
      .inputs = {renderPort(std::move(input), BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    };
  };

  const auto luminance_pass = [&] {
    return Pass{
      .id = "luminance",
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort("luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        LuminanceField current_luminance = makeLuminanceField(active_frame());
        if (temporal_state != nullptr && temporal_supersample > 1) {
          const auto supersample_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
          if (temporal_state->next_supersample_frame.has_value()) {
            const LuminanceField next_luminance = makeLuminanceField(*temporal_state->next_supersample_frame);
            analysis_luminance = blendTemporalSupersample(current_luminance, next_luminance, temporal_supersample, true);
            temporal_state->next_supersample_frame.reset();
            if (stats != nullptr) {
              stats->temporal_supersample_frames += temporal_supersample - 1;
              stats->temporal_supersample_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - supersample_started).count();
            }
          } else if (!temporal_state->next_supersample_required && temporal_state->previous_supersample_luminance.has_value()) {
            analysis_luminance = blendTemporalSupersample(current_luminance, *temporal_state->previous_supersample_luminance, temporal_supersample, false);
            if (stats != nullptr) {
              stats->temporal_supersample_frames += temporal_supersample - 1;
              stats->temporal_supersample_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - supersample_started).count();
            }
          } else {
            analysis_luminance = current_luminance;
          }
          temporal_state->previous_supersample_luminance = std::move(current_luminance);
        } else {
          analysis_luminance = std::move(current_luminance);
        }
      },
    };
  };

  const auto append_blitter_pass = [&](std::vector<Pass>* passes, const std::string& blitter, const std::string& output) {
    passes->push_back(Pass{
      .id = blitter,
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort(output, BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&, blitter](PassContext&) {
        if (blitter == "halfblock") {
          renderHalfBlockFrame(active_frame(), size.cols, size.rows, cells);
        } else if (blitter == "blocks") {
          renderBlockSadFrame(active_frame(), size.cols, size.rows, cells);
        } else if (blitter == "octant") {
          renderOctantFrame(active_frame(), size.cols, size.rows, cells);
        } else if (blitter == "sextant") {
          renderSextantFrame(active_frame(), size.cols, size.rows, cells);
        } else if (blitter == "braille") {
          renderBrailleFrame(active_frame(), size.cols, size.rows, cells);
        }
      },
    });
  };

  const auto cell_average_pass = [&](std::vector<PassPort> inputs) {
    return Pass{
      .id = "cell-average",
      .inputs = std::move(inputs),
      .outputs = {renderPort("cell-colors", BufferKind::CellColors)},
      .supports = {Backend::Cpu, Backend::Metal},
      .run = [&](PassContext&) {
        const std::vector<Cell>& cell_values = cells->cells();
        average_colors.assign(cell_values.size(), Rgb{});
        const bool has_gpu_average = gpu_structure_glyphs.has_value() && gpu_structure_glyphs->average_colors.size() == cell_values.size();
        const int workers = renderWorkerCount(size.cols, size.rows);
        const auto fill_rows = [&](int row_begin, int row_end) {
          for (int row = row_begin; row < row_end; ++row) {
            for (int col = 0; col < size.cols; ++col) {
              const std::size_t cell_index = static_cast<std::size_t>(row) * static_cast<std::size_t>(size.cols) + static_cast<std::size_t>(col);
              average_colors[cell_index] = has_gpu_average ? gpu_structure_glyphs->average_colors[cell_index] : averageRegion(active_frame(), size.cols, size.rows, col, row);
            }
          }
        };
        if (workers == 1) {
          fill_rows(0, size.rows);
        } else {
          std::vector<std::thread> threads;
          threads.reserve(static_cast<std::size_t>(workers - 1));
          for (int worker = 1; worker < workers; ++worker) {
            const int row_begin = (size.rows * worker) / workers;
            const int row_end = (size.rows * (worker + 1)) / workers;
            threads.emplace_back(fill_rows, row_begin, row_end);
          }
          fill_rows(0, size.rows / workers);
          for (std::thread& thread : threads) {
            thread.join();
          }
        }
      },
    };
  };

  const auto ramp_pick_pass = [&](std::string output) {
    return Pass{
      .id = "ramp-pick",
      .inputs = {renderPort("cell-colors", BufferKind::CellColors), renderPort("luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort(std::move(output), BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        std::vector<Cell>& cell_values = cells->cells();
        for (std::size_t index = 0; index < cell_values.size(); ++index) {
          const Rgb avg = average_colors[index];
          Cell& cell = cell_values[index];
          cell.glyph = glyphForLuminance(relativeLuminance(avg), ramp);
          cell.fg = avg;
          cell.bg = Rgb{};
        }
      },
    };
  };

  const auto append_structure_analysis = [&](std::vector<Pass>* passes) {
    passes->push_back(Pass{
      .id = "contrast",
      .inputs = {renderPort("luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("contrast-luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        analysis_luminance = applyStructureContrast(*analysis_luminance, contrastFromConfig(config));
      },
    });
    passes->push_back(Pass{
      .id = "dog",
      .inputs = {renderPort("contrast-luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu, Backend::Metal},
      .run = [&](PassContext& context) {
        const DogOptions dog_options = dogOptionsFromConfig(config);
        if (!dog_options.enabled()) {
          return;
        }
        if (context.backend() == Backend::Metal) {
          if (auto gpu_dog = differenceOfGaussiansGpu(*analysis_luminance, dog_options)) {
            analysis_luminance = std::move(*gpu_dog);
            return;
          }
        }
        analysis_luminance = differenceOfGaussians(*analysis_luminance, dog_options);
      },
    });
    passes->push_back(Pass{
      .id = "sobel",
      .inputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort(etf_enabled ? "raw-gradients" : "gradients", BufferKind::GradientField)},
      .supports = {Backend::Cpu, Backend::Metal},
      .run = [&](PassContext& context) {
        if (!glyph_hysteresis_enabled && !etf_enabled && context.backend() == Backend::Metal && (shape_table == nullptr || shape_table->feature_kind == GlyphFeatureKind::Overlap)) {
          gpu_structure_glyphs = computeStructureGlyphsGpu(active_frame(), *analysis_luminance, size.cols, size.rows, edge_threshold, shape_table);
          if (gpu_structure_glyphs.has_value()) {
            if (stats != nullptr) {
              stats->shape_match_cells += gpu_structure_glyphs->shape_match_cells;
            }
            return;
          }
          structure_gradients = computeSobelGradientsGpu(*analysis_luminance);
        }
        if (!structure_gradients.has_value()) {
          structure_gradients = computeSobelGradients(*analysis_luminance);
        }
      },
    });
    if (etf_enabled) {
      passes->push_back(Pass{
        .id = "etf",
        .inputs = {renderPort("raw-gradients", BufferKind::GradientField)},
        .outputs = {renderPort("gradients", BufferKind::GradientField)},
        .supports = {Backend::Cpu},
        .run = [&](PassContext&) {
          if (structure_gradients.has_value()) {
            structure_gradients = smoothEtfGradients(*structure_gradients, etfIterationsFromConfig(config));
          }
        },
      });
    }
    passes->push_back(Pass{
      .id = "edge-field",
      .inputs = {renderPort("gradients", BufferKind::GradientField)},
      .outputs = {renderPort("edge-field", BufferKind::EdgeField)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        if (structure_gradients.has_value()) {
          structure_ink = etf_enabled
                            ? coherentLineField(*structure_gradients, edge_threshold)
                            : gradientMagnitudeField(*structure_gradients, edge_threshold);
        }
      },
    });
    if (glyph_hysteresis_enabled || motion_flow_enabled) {
      passes->push_back(Pass{
        .id = "optical-flow",
        .inputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
        .outputs = {renderPort("flow", BufferKind::OpticalFlow)},
        .supports = {Backend::Cpu},
        .run = [&](PassContext&) {
          if (!analysis_luminance.has_value()) {
            return;
          }
          const auto flow_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
          if (temporal_state->previous_luminance.has_value() &&
              temporal_state->previous_luminance->width == analysis_luminance->width &&
              temporal_state->previous_luminance->height == analysis_luminance->height) {
            flow_field = computeBlockOpticalFlow(*temporal_state->previous_luminance, *analysis_luminance);
            if (stats != nullptr) {
              stats->optical_flow_blocks += static_cast<int64_t>(flow_field->vectors.size());
              stats->optical_flow_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - flow_started).count();
            }
          }
          temporal_state->previous_luminance = *analysis_luminance;
        },
      });
    }
  };

  const auto cell_shape_pass = [&](const std::string& base_input) {
    return Pass{
      .id = "cell-shape",
      .inputs = {renderPort("edge-field", BufferKind::EdgeField), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cell-shapes", BufferKind::CellShapeVectors)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        cell_shape_regions.clear();
        if (shape_table == nullptr || !structure_ink.has_value()) {
          return;
        }
        cell_shape_regions.reserve(cells->cells().size());
        for (int row = 0; row < size.rows; ++row) {
          for (int col = 0; col < size.cols; ++col) {
            cell_shape_regions.push_back(sampleCellRegion(*structure_ink, size.cols, size.rows, col, row));
          }
        }
      },
    };
  };

  const auto warp_history_pass = [&](const std::string& base_input) {
    return Pass{
      .id = "warp-history",
      .inputs = {renderPort("flow", BufferKind::OpticalFlow), renderPort(base_input, BufferKind::CellGlyphs), renderPort("cell-shapes", BufferKind::CellShapeVectors)},
      .outputs = {renderPort("warped-history", BufferKind::CellGlyphs), renderPort("warped-shapes", BufferKind::CellShapeVectors)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        warped_previous_glyphs.clear();
        warped_previous_shape_regions.clear();
        if (flow_field.has_value() && !previous_glyphs.empty()) {
          const auto warp_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
          warped_previous_glyphs = warpGlyphHistory(previous_glyphs, size.cols, size.rows, *flow_field);
          if (previous_shape_regions.size() == cell_shape_regions.size()) {
            warped_previous_shape_regions = warpCellShapeHistory(previous_shape_regions, size.cols, size.rows, *flow_field);
          }
          if (stats != nullptr) {
            stats->warp_history_cells += static_cast<int64_t>(warped_previous_glyphs.size() + warped_previous_shape_regions.size());
            stats->warp_history_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - warp_started).count();
          }
        }
      },
    };
  };

  const auto overlay_structure_pass = [&](const std::string& base_input) {
    return Pass{
      .id = "overlay-structure",
      .inputs = glyph_hysteresis_enabled
                  ? std::vector<PassPort>{renderPort("edge-field", BufferKind::EdgeField), renderPort("cell-shapes", BufferKind::CellShapeVectors), renderPort("warped-history", BufferKind::CellGlyphs), renderPort("warped-shapes", BufferKind::CellShapeVectors), renderPort(base_input, BufferKind::CellGlyphs)}
                  : std::vector<PassPort>{renderPort("edge-field", BufferKind::EdgeField), renderPort("cell-shapes", BufferKind::CellShapeVectors), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu, Backend::Metal},
      .run = [&](PassContext&) {
        std::vector<Cell>& cell_values = cells->cells();
        if (gpu_structure_glyphs.has_value() && (shape_table == nullptr || shape_table->feature_kind == GlyphFeatureKind::Overlap)) {
          for (std::size_t index = 0; index < cell_values.size(); ++index) {
            const char32_t gpu_glyph = gpu_structure_glyphs->glyphs[index];
            if (gpu_glyph != U'\0') {
              cell_values[index].glyph = gpu_glyph;
            }
          }
          return;
        }
        if (!structure_gradients.has_value()) {
          return;
        }
        const int workers = renderWorkerCount(size.cols, size.rows);
        worker_stats.assign(static_cast<std::size_t>(workers), ShapeMatchStats{});
        const auto match_rows = [&](int row_begin, int row_end, ShapeMatchStats* local_stats) {
          for (int row = row_begin; row < row_end; ++row) {
            for (int col = 0; col < size.cols; ++col) {
              const std::size_t cell_index = static_cast<std::size_t>(row) * static_cast<std::size_t>(size.cols) + static_cast<std::size_t>(col);
              Cell& cell = cell_values[cell_index];
              const CellGradient gradient = cellGradient(*structure_gradients, size.cols, size.rows, col, row);
              const std::optional<char32_t> edge_glyph = directionalGlyphForGradient(gradient, edge_threshold);
              if (!edge_glyph.has_value()) {
                continue;
              }
              if (shape_table != nullptr && structure_ink.has_value()) {
                const auto match_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
                const auto match_region = [&](const CellLuminanceRegion& region) {
                  if (shape_table->feature_count == kHogFeatureCount) {
                    return hogVectorForCell(region);
                  }
                  if (shape_table->feature_kind == GlyphFeatureKind::Sdf) {
                    return sdfVectorForCell(region);
                  }
                  return shapeVectorForCell(region);
                };
                const std::vector<double> features = cell_shape_regions.empty()
                                                       ? match_region(sampleCellRegion(*structure_ink, size.cols, size.rows, col, row))
                                                       : match_region(cell_shape_regions[cell_index]);
                if (glyph_hysteresis_enabled) {
                  const GlyphShapeMatch best = matchGlyphShapeWithScore(features, *shape_table);
                  const std::vector<char32_t>& history_glyphs = warped_previous_glyphs.empty() ? previous_glyphs : warped_previous_glyphs;
                  const std::optional<char32_t> history_glyph = history_glyphs.empty() ? std::nullopt : std::optional<char32_t>(history_glyphs[cell_index]);
                  const char32_t previous_glyph = history_glyph.value_or(cell.glyph);
                  const std::vector<double> previous_features = warped_previous_shape_regions.empty()
                                                                  ? features
                                                                  : match_region(warped_previous_shape_regions[cell_index]);
                  const double previous_score = scoreGlyphShape(previous_features, *shape_table, previous_glyph);
                  cell.glyph = temporal_state->glyph_hysteresis.choose(cell_index, best, previous_score, glyph_stickiness, history_glyph).glyph;
                } else {
                  cell.glyph = matchGlyphShape(features, *shape_table);
                }
                if (stats != nullptr) {
                  ++local_stats->cells;
                  local_stats->ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - match_started).count();
                }
              } else {
                char32_t directional_glyph = *edge_glyph;
                if (orientation_hysteresis_enabled) {
                  directional_glyph = temporal_state->orientation_hysteresis.choose(cell_index, directional_glyph, gradient.orientation, orient_stickiness).glyph;
                }
                cell.glyph = directional_glyph;
              }
            }
          }
        };
        if (workers == 1) {
          match_rows(0, size.rows, &worker_stats[0]);
        } else {
          std::vector<std::thread> threads;
          threads.reserve(static_cast<std::size_t>(workers - 1));
          for (int worker = 1; worker < workers; ++worker) {
            const int row_begin = (size.rows * worker) / workers;
            const int row_end = (size.rows * (worker + 1)) / workers;
            threads.emplace_back(match_rows, row_begin, row_end, &worker_stats[static_cast<std::size_t>(worker)]);
          }
          match_rows(0, size.rows / workers, &worker_stats[0]);
          for (std::thread& thread : threads) {
            thread.join();
          }
        }
      },
    };
  };

  const auto crosshatch_pass = [&](const std::string& base_input) {
    return Pass{
      .id = "crosshatch",
      .inputs = {renderPort("gradients", BufferKind::GradientField), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        if (structure_gradients.has_value()) {
          applyCrosshatch(cells, *structure_gradients, size.cols, size.rows, edge_threshold);
        }
      },
    };
  };

  const auto lic_pass = [&](const std::string& base_input) {
    return Pass{
      .id = "lic",
      .inputs = motion_flow_enabled
                  ? std::vector<PassPort>{renderPort("gradients", BufferKind::GradientField), renderPort("flow", BufferKind::OpticalFlow), renderPort(base_input, BufferKind::CellGlyphs)}
                  : std::vector<PassPort>{renderPort("gradients", BufferKind::GradientField), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        if (flow_field.has_value()) {
          applyLicMotionFlow(cells, *flow_field, size.cols, size.rows, licLengthFromConfig(config), edge_threshold);
        } else if (structure_gradients.has_value()) {
          applyLicFlow(cells, *structure_gradients, size.cols, size.rows, licLengthFromConfig(config), edge_threshold);
        }
      },
    };
  };

  const auto normal_orient_pass = [&](const std::string& input) {
    return Pass{
      .id = "normal-orient",
      .inputs = {renderPort("scene-normals", BufferKind::NormalBuffer), renderPort(input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("normal-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        if (scene_gbuffer != nullptr) {
          applySceneNormalOrient(cells, *scene_gbuffer, size.cols, size.rows);
        }
      },
    };
  };

  const auto depth_shade_pass = [&] {
    return Pass{
      .id = "depth-shade",
      .inputs = {renderPort("scene-depth", BufferKind::DepthBuffer), renderPort("scene-normals", BufferKind::NormalBuffer), renderPort("normal-cells", BufferKind::CellGlyphs)},
      .outputs = {renderPort("scene-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        if (scene_gbuffer != nullptr) {
          applySceneDepthShade(cells, *scene_gbuffer, ramp, size.cols, size.rows);
        }
      },
    };
  };

  const auto append_scene_cell_shade_passes = [&](std::vector<Pass>* passes, const std::string& input) {
    if (!scene_cell_shade_enabled) {
      return input;
    }
    passes->push_back(normal_orient_pass(input));
    passes->push_back(depth_shade_pass());
    return std::string("scene-cells");
  };

  const auto line_ligatures_pass = [&] {
    return Pass{
      .id = "line-ligatures",
      .inputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .outputs = {renderPort("ligature-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        applyLineLigatures(cells);
      },
    };
  };

  const auto append_emit_after_overlay = [&](std::vector<Pass>* passes) {
    const auto append_stipple_pass = [&](std::string input) {
      if (!stipple_enabled) {
        return input;
      }
      passes->push_back(Pass{
        .id = "stipple",
        .inputs = {renderPort(input, BufferKind::CellGlyphs), renderPort(frame_input, BufferKind::RgbFrame)},
        .outputs = {renderPort("stipple-cells", BufferKind::CellGlyphs)},
        .supports = {Backend::Cpu},
        .run = [&](PassContext&) {
          applyStipple(cells, stipple_carrier, &active_frame());
        },
      });
      return std::string("stipple-cells");
    };
    std::string output = "cells";
    if (config.line_ligatures && overlay_enabled) {
      passes->push_back(line_ligatures_pass());
      output = "ligature-cells";
    }
    passes->push_back(emit_pass(append_stipple_pass(append_scene_cell_shade_passes(passes, output))));
  };

  if (const std::optional<std::string> blitter = directBlitterMode(config)) {
    std::vector<Pass> passes;
    const std::string blitter_output = overlay_enabled ? "base-cells" : "cells";
    passes.push_back(decode_pass());
    if (painterly_enabled) {
      passes.push_back(kuwahara_pass());
    }
    if (posterize_enabled) {
      passes.push_back(posterize_pass());
    }
    append_blitter_pass(&passes, *blitter, blitter_output);
    if (overlay_enabled) {
      passes.push_back(luminance_pass());
      append_structure_analysis(&passes);
      if (hatch_enabled) {
        passes.push_back(crosshatch_pass(blitter_output));
      } else if (flow_enabled) {
        passes.push_back(lic_pass(blitter_output));
      } else {
        passes.push_back(cell_shape_pass(blitter_output));
        if (glyph_hysteresis_enabled) {
          passes.push_back(warp_history_pass(blitter_output));
        }
        passes.push_back(overlay_structure_pass(blitter_output));
      }
      append_emit_after_overlay(&passes);
    } else {
      append_emit_after_overlay(&passes);
    }
    run_graph(std::move(passes));
    finish_stats();
    return;
  }

  std::vector<Pass> passes;
  passes.push_back(decode_pass());
  if (painterly_enabled) {
    passes.push_back(kuwahara_pass());
  }
  if (posterize_enabled) {
    passes.push_back(posterize_pass());
  }
  passes.push_back(luminance_pass());

  if (overlay_enabled) {
    append_structure_analysis(&passes);
    passes.push_back(cell_average_pass({renderPort(frame_input, BufferKind::RgbFrame), renderPort("gradients", BufferKind::GradientField)}));
    passes.push_back(ramp_pick_pass("base-cells"));
    if (hatch_enabled) {
      passes.push_back(crosshatch_pass("base-cells"));
    } else if (flow_enabled) {
      passes.push_back(lic_pass("base-cells"));
    } else {
      passes.push_back(cell_shape_pass("base-cells"));
      if (glyph_hysteresis_enabled) {
        passes.push_back(warp_history_pass("base-cells"));
      }
      passes.push_back(overlay_structure_pass("base-cells"));
    }
    append_emit_after_overlay(&passes);
  } else {
    passes.push_back(cell_average_pass({renderPort(frame_input, BufferKind::RgbFrame)}));
    passes.push_back(ramp_pick_pass("cells"));
    append_emit_after_overlay(&passes);
  }

  run_graph(std::move(passes));
  finish_stats();
}

}  // namespace strok
