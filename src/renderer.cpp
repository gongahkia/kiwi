#include "renderer.hpp"

#include "ansi_transition_cost.hpp"
#include "block_sad.hpp"
#include "braille_renderer.hpp"
#include "crosshatch.hpp"
#include "depth_image_view.hpp"
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
#include "motion_vector_view.hpp"
#include "normal_image_view.hpp"
#include "octant_renderer.hpp"
#include "optical_flow.hpp"
#include "posterize.hpp"
#include "render_graph.hpp"
#include "render_layout.hpp"
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
#include <exception>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace strok {
namespace {

constexpr double kDefaultDogThreshold = 0.02;
constexpr double kDefaultEdgeThreshold = 0.35;
constexpr double kDefaultEdgeStrength = 1.0;
constexpr double kPi = 3.14159265358979323846;

struct BudgetCandidate {
  std::size_t cell_index = 0;
  Cell temporal_cell;
  CandidateScore current_score;
  CandidateScore previous_score;
};

struct ShapeMatchStats {
  int64_t cells = 0;
  int64_t ns = 0;
  int64_t temporal_candidate_cells = 0;
  int64_t temporal_reused_cells = 0;
  double temporal_candidate_reconstruction_score = 0.0;
  double temporal_candidate_temporal_score = 0.0;
  double temporal_candidate_presentation_cost = 0.0;
  std::vector<BudgetCandidate> budget_candidates;
};

struct HistoryMotionSelection {
  FlowField flow;
  std::vector<bool> history_available;
  int64_t external_cells = 0;
  int64_t inferred_cells = 0;
  int64_t suppressed_cells = 0;
};

struct CellShadeSample {
  Rgb color;
  NormalSample normal;
  double depth = 0.0;
};

struct DepthRange {
  double near = 0.0;
  double far = 0.0;
};

std::optional<FlowVector> inferredFlowForCell(const FlowField& flow, int cols, int rows, int col, int row) {
  if (flow.width <= 0 || flow.height <= 0 || flow.block_size <= 0 ||
      flow.blocks_x <= 0 || flow.blocks_y <= 0 ||
      flow.vectors.size() != static_cast<std::size_t>(flow.blocks_x) * static_cast<std::size_t>(flow.blocks_y)) {
    return std::nullopt;
  }
  const double pixel_x = (static_cast<double>(col) + 0.5) * flow.width / cols;
  const double pixel_y = (static_cast<double>(row) + 0.5) * flow.height / rows;
  const int block_x = std::clamp(static_cast<int>(pixel_x / flow.block_size), 0, flow.blocks_x - 1);
  const int block_y = std::clamp(static_cast<int>(pixel_y / flow.block_size), 0, flow.blocks_y - 1);
  const FlowVector vector = flow.at(block_x, block_y);
  return FlowVector{
    .dx = vector.dx * cols / flow.width,
    .dy = vector.dy * rows / flow.height,
    .error = vector.error,
  };
}

HistoryMotionSelection selectHistoryMotion(const CellMotionField& external,
                                           const std::optional<FlowField>& inferred) {
  if (external.cols <= 0 || external.rows <= 0 ||
      external.vectors.size() != static_cast<std::size_t>(external.cols) * static_cast<std::size_t>(external.rows)) {
    throw std::invalid_argument("invalid cell motion field");
  }
  HistoryMotionSelection selection;
  selection.flow = FlowField{
    .block_size = 1,
    .width = external.cols,
    .height = external.rows,
    .blocks_x = external.cols,
    .blocks_y = external.rows,
    .vectors = {},
  };
  selection.flow.vectors.reserve(external.vectors.size());
  selection.history_available.reserve(external.vectors.size());
  for (int row = 0; row < external.rows; ++row) {
    for (int col = 0; col < external.cols; ++col) {
      const CellMotionVector& external_vector = external.at(col, row);
      if (external_vector.validity == MotionVectorValidity::Valid) {
        selection.flow.vectors.push_back(FlowVector{.dx = external_vector.dx, .dy = external_vector.dy});
        selection.history_available.push_back(true);
        ++selection.external_cells;
        continue;
      }
      if (external_vector.validity == MotionVectorValidity::Invalid && inferred.has_value()) {
        const std::optional<FlowVector> fallback = inferredFlowForCell(*inferred, external.cols, external.rows, col, row);
        if (fallback.has_value()) {
          selection.flow.vectors.push_back(*fallback);
          selection.history_available.push_back(true);
          ++selection.inferred_cells;
          continue;
        }
      }
      selection.flow.vectors.push_back(FlowVector{});
      selection.history_available.push_back(false);
      ++selection.suppressed_cells;
    }
  }
  return selection;
}

PassPort renderPort(std::string name, BufferKind kind) {
  return PassPort{
    .name = std::move(name),
    .desc = BufferDesc{.kind = kind},
  };
}

bool cellShadeInputAvailable(const RenderInput& input) {
  return input.depth.has_value() && input.normals.has_value();
}

std::optional<DepthRange> depthRange(const DepthImageView& depth_image) {
  std::optional<DepthRange> range;
  for (int y = 0; y < depth_image.height; ++y) {
    for (int x = 0; x < depth_image.width; ++x) {
      const double depth = depthAt(depth_image, x, y);
      if (!depthSampleValid(depth)) {
        continue;
      }
      if (!range.has_value()) {
        range = DepthRange{.near = depth, .far = depth};
        continue;
      }
      range->near = std::min(range->near, depth);
      range->far = std::max(range->far, depth);
    }
  }
  return range;
}

std::optional<CellShadeSample> sampleCellShadeInput(const RenderInput& input, int cols, int rows, int col, int row) {
  if (!cellShadeInputAvailable(input) || cols <= 0 || rows <= 0) {
    return std::nullopt;
  }
  const int width = input.color.width;
  const int height = input.color.height;
  const int x0 = static_cast<int>((static_cast<int64_t>(col) * width) / cols);
  const int x1 = std::max(x0 + 1, static_cast<int>((static_cast<int64_t>(col + 1) * width) / cols));
  const int y0 = static_cast<int>((static_cast<int64_t>(row) * height) / rows);
  const int y1 = std::max(y0 + 1, static_cast<int>((static_cast<int64_t>(row + 1) * height) / rows));
  uint64_t r = 0;
  uint64_t g = 0;
  uint64_t b = 0;
  double nx = 0.0;
  double ny = 0.0;
  double nz = 0.0;
  double depth_sum = 0.0;
  uint64_t count = 0;
  const DepthImageView& depth_image = *input.depth;
  const NormalImageView& normal_image = *input.normals;
  for (int y = y0; y < y1; ++y) {
    for (int x = x0; x < x1; ++x) {
      const double depth = depthAt(depth_image, x, y);
      if (!depthSampleValid(depth)) {
        continue;
      }
      const Rgb color = colorAt(input.color, x, y);
      r += color.r;
      g += color.g;
      b += color.b;
      const NormalSample normal = normalizedNormalSampleOrViewFacing(normalAt(normal_image, x, y));
      nx += normal.x;
      ny += normal.y;
      nz += normal.z;
      depth_sum += depth;
      ++count;
    }
  }
  if (count == 0) {
    return std::nullopt;
  }
  return CellShadeSample{
    .color = Rgb{
      .r = static_cast<uint8_t>(r / count),
      .g = static_cast<uint8_t>(g / count),
      .b = static_cast<uint8_t>(b / count),
    },
    .normal = normalizedNormalSampleOrViewFacing(NormalSample{.x = nx, .y = ny, .z = nz}),
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

void applyNormalOrient(CellBuffer* cells, const RenderInput& input, int cols, int rows) {
  if (cells == nullptr || cells->cols() != cols || cells->rows() != rows) {
    return;
  }
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      const std::optional<CellShadeSample> sample = sampleCellShadeInput(input, cols, rows, col, row);
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

void applyDepthShade(CellBuffer* cells, const RenderInput& input, std::u32string_view ramp, int cols, int rows) {
  if (cells == nullptr || cells->cols() != cols || cells->rows() != rows) {
    return;
  }
  if (!input.depth.has_value()) {
    return;
  }
  const std::optional<DepthRange> range = depthRange(*input.depth);
  if (!range.has_value()) {
    return;
  }
  const double span = std::max(range->far - range->near, 1.0e-9);
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      const std::optional<CellShadeSample> sample = sampleCellShadeInput(input, cols, rows, col, row);
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

double presentationCostWeightFromConfig(const RendererConfig& config) {
  return config.presentation_cost_weight.value_or(0.0);
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
    graph_options.external_inputs = {"input-depth", "input-normals"};
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
  const bool cell_shade_enabled = config.style == "cell-shade";
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
  const auto append_cell_shade = [&](std::vector<Pass>* passes, const std::string& input) {
    if (!cell_shade_enabled) {
      return input;
    }
    passes->push_back(Pass{
      .id = "normal-orient",
      .inputs = {renderPort("input-normals", BufferKind::NormalBuffer), renderPort(input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("normal-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    passes->push_back(Pass{
      .id = "depth-shade",
      .inputs = {renderPort("input-depth", BufferKind::DepthBuffer), renderPort("input-normals", BufferKind::NormalBuffer), renderPort("normal-cells", BufferKind::CellGlyphs)},
      .outputs = {renderPort("shaded-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    return std::string("shaded-cells");
  };
  const auto emit_styled = [&](std::vector<Pass>* passes, const std::string& input) {
    passes->push_back(emit_pass(append_stipple(passes, append_cell_shade(passes, input))));
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

bool finiteAtLeast(double value, double minimum) {
  return std::isfinite(value) && value >= minimum;
}

bool finitePositive(double value) {
  return std::isfinite(value) && value > 0.0;
}

std::optional<std::string> renderConfigurationError(const RendererConfig& config) {
  if ((config.width.has_value() && *config.width <= 0) || (config.height.has_value() && *config.height <= 0)) {
    return "render dimensions must be positive";
  }
  if (!finitePositive(config.cell_aspect)) {
    return "cell aspect must be finite and positive";
  }
  if (config.mode != "auto" && config.mode != "luminance" && config.mode != "structure" && config.mode != "halfblock" && config.mode != "blocks" && config.mode != "octant" && config.mode != "sextant" && config.mode != "braille") {
    return "unknown render mode";
  }
  if (config.style != "none" && config.style != "painterly" && config.style != "hatch" && config.style != "stipple" && config.style != "flow" && config.style != "cell-shade") {
    return "unknown render style";
  }
  if (config.structure_overlay != "auto" && config.structure_overlay != "on" && config.structure_overlay != "off") {
    return "unknown structure overlay mode";
  }
  if (config.glyph_features != "overlap" && config.glyph_features != "hog" && config.glyph_features != "sdf") {
    return "unknown glyph feature mode";
  }
  if (config.font_path.has_value() && config.font_path->empty()) {
    return "font path must not be empty";
  }
  if (config.ramp_sort && !config.font_path.has_value()) {
    return "ramp sorting requires a font path";
  }
  if (config.charset.has_value() && !isValidCharset(*config.charset)) {
    return "invalid charset";
  }
  if ((config.edge_threshold.has_value() && !finiteAtLeast(*config.edge_threshold, 0.0)) ||
      (config.edge_strength.has_value() && !finiteAtLeast(*config.edge_strength, 0.0)) ||
      (config.dog_sigma.has_value() && !finiteAtLeast(*config.dog_sigma, 0.0)) ||
      (config.dog_threshold.has_value() && !finiteAtLeast(*config.dog_threshold, 0.0)) ||
      (config.contrast.has_value() && !finiteAtLeast(*config.contrast, 0.0))) {
    return "renderer numeric options must be finite and non-negative";
  }
  if (config.dog_sigma2.has_value() && (!config.dog_sigma.has_value() || !finitePositive(*config.dog_sigma2) || *config.dog_sigma == 0.0 || *config.dog_sigma2 <= *config.dog_sigma)) {
    return "second DoG sigma must be finite and greater than the first";
  }
  if ((config.etf_iters.has_value() && (*config.etf_iters < 0 || *config.etf_iters > 16)) ||
      (config.lic_length.has_value() && (*config.lic_length < 1 || *config.lic_length > 64)) ||
      (config.posterize.has_value() && (*config.posterize < 2 || *config.posterize > 64)) ||
      config.temporal_supersample < 1 || config.temporal_supersample > 8) {
    return "renderer integer options are out of range";
  }
  if ((config.glyph_stickiness.has_value() && !finiteAtLeast(*config.glyph_stickiness, 0.0)) ||
      (config.glyph_stickiness.has_value() && *config.glyph_stickiness > 1.0) ||
      (config.orient_stickiness.has_value() && (!finiteAtLeast(*config.orient_stickiness, 0.0) || *config.orient_stickiness > kPi)) ||
      (config.presentation_cost_weight.has_value() && !finiteAtLeast(*config.presentation_cost_weight, 0.0))) {
    return "renderer temporal options are out of range";
  }
  if (config.symbolic_update_budget.has_value() && *config.symbolic_update_budget < 0) {
    return "symbolic update budget must be non-negative";
  }
  return std::nullopt;
}

RenderResult renderFailure(RenderStatus status, std::string message) {
  return RenderResult{.status = status, .message = std::move(message)};
}

void collectSymbolicMetrics(const CellBuffer& previous, const CellBuffer& current, RenderStats* stats) {
  if (stats == nullptr) {
    return;
  }
  if (previous.cols() != current.cols() || previous.rows() != current.rows()) {
    const int64_t cells = static_cast<int64_t>(current.size());
    stats->changed_glyphs += cells;
    stats->changed_foregrounds += cells;
    stats->changed_backgrounds += cells;
    stats->changed_cells += cells;
    return;
  }
  for (std::size_t index = 0; index < current.size(); ++index) {
    const Cell& before = previous.cells()[index];
    const Cell& after = current.cells()[index];
    const bool glyph_changed = before.glyph != after.glyph;
    const bool foreground_changed = before.fg != after.fg;
    const bool background_changed = before.bg != after.bg;
    stats->changed_glyphs += glyph_changed;
    stats->changed_foregrounds += foreground_changed;
    stats->changed_backgrounds += background_changed;
    stats->changed_cells += glyph_changed || foreground_changed || background_changed;
  }
}

int64_t modeledSymbolicUpdateUnits(const CellBuffer& previous, const CellBuffer& current) {
  if (previous.cols() != current.cols() || previous.rows() != current.rows()) {
    return static_cast<int64_t>(current.size());
  }
  AnsiTransitionContext context;
  int64_t total = 0;
  for (int row = 0; row < current.rows(); ++row) {
    for (int col = 0; col < current.cols(); ++col) {
      const AnsiTransitionEstimate estimate = estimateAnsiCellTransition(
        previous.at(col, row), current.at(col, row), row + 1, col + 1, context);
      total += static_cast<int64_t>(estimate.update_units);
      context = estimate.next_context;
    }
  }
  return total;
}

}  // namespace

std::string dumpRenderGraph(const RendererConfig& config) {
  return buildRendererGraphTopology(config).dump();
}

Graph buildRendererGraphTopology(const RendererConfig& config) {
  return buildGraph(renderGraphSkeleton(config), renderGraphBuildOptions(config));
}

RenderResult validateRendererConfiguration(const RendererConfig& config, RenderGrid grid) {
  if (grid.cols <= 0 || grid.rows <= 0) {
    return renderFailure(RenderStatus::InvalidConfiguration, "render grid dimensions must be positive");
  }
  if (const std::optional<std::string> error = renderConfigurationError(config); error.has_value()) {
    return renderFailure(RenderStatus::InvalidConfiguration, *error);
  }
  return RenderResult{};
}

RenderResult renderFrame(const RenderInput& input, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state, const Graph* graph_topology) try {
  if (output == nullptr) {
    return renderFailure(RenderStatus::InvalidInput, "output cell buffer is required");
  }
  if (const std::optional<std::string> error = renderInputError(input); error.has_value()) {
    return renderFailure(RenderStatus::InvalidInput, *error);
  }
  const ColorImageView& image = input.color;
  if (ramp.empty()) {
    return renderFailure(RenderStatus::InvalidInput, "glyph ramp must not be empty");
  }
  if (const std::optional<std::string> error = renderConfigurationError(config); error.has_value()) {
    return renderFailure(RenderStatus::InvalidConfiguration, *error);
  }
  if (config.style == "cell-shade" && !cellShadeInputAvailable(input)) {
    return renderFailure(RenderStatus::InvalidInput, "cell-shade rendering requires depth and normal inputs");
  }

  RenderResult result;
  const auto mark_backend_fallback = [&](std::string message) {
    if (result.status == RenderStatus::Success) {
      result.status = RenderStatus::BackendFallback;
      result.message = std::move(message);
    }
  };

  if (config.gpu && !gpuSobelAvailable()) {
    mark_backend_fallback("GPU analysis requested but unavailable; used CPU fallback");
  }
  const auto render_started = std::chrono::steady_clock::now();
  CellBuffer rendered_cells;
  CellBuffer* cells = &rendered_cells;
  const RenderGrid size = fitRenderGrid(image, config, available_grid);
  cells->resize(size.cols, size.rows);
  if (temporal_state != nullptr) {
    temporal_state->glyph_hysteresis.resize(size.cols, size.rows);
    temporal_state->orientation_hysteresis.resize(size.cols, size.rows);
  }
  const bool temporal_cell_reuse_enabled = temporal_state != nullptr && shape_table != nullptr && config.temporal_cell_reuse;
  const CellBuffer* previous_cell_history = nullptr;
  if (temporal_cell_reuse_enabled && temporal_state->previous_cells.has_value() &&
      temporal_state->previous_cells->cols() == size.cols && temporal_state->previous_cells->rows() == size.rows) {
    previous_cell_history = &*temporal_state->previous_cells;
  }
  std::optional<CellMotionField> external_motion;
  bool external_motion_has_invalid = false;
  if (input.motion_vectors.has_value()) {
    external_motion = remapMotionVectorsToCellGrid(*input.motion_vectors,
                                                   input.motion_vector_validity.has_value() ? &*input.motion_vector_validity : nullptr,
                                                   size.cols,
                                                   size.rows);
    for (const CellMotionVector& vector : external_motion->vectors) {
      external_motion_has_invalid = external_motion_has_invalid || vector.validity == MotionVectorValidity::Invalid;
    }
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
  ++result.stats.frames;
  result.stats.cells += static_cast<int64_t>(size.cols) * static_cast<int64_t>(size.rows);

  std::optional<LuminanceField> analysis_luminance;
  std::optional<GradientField> structure_gradients;
  std::optional<LuminanceField> structure_ink;
  std::optional<FlowField> flow_field;
  std::optional<GpuStructureGlyphs> gpu_structure_glyphs;
  std::vector<Rgb> average_colors;
  std::vector<CellLuminanceRegion> cell_shape_regions;
  std::vector<char32_t> warped_previous_glyphs;
  std::vector<CellLuminanceRegion> warped_previous_shape_regions;
  std::vector<Cell> warped_previous_cells;
  std::vector<bool> warped_history_available;
  const double edge_threshold = effectiveEdgeThresholdFromConfig(config);
  const double orient_stickiness = orientationStickinessFromConfig(config);
  const bool overlay_enabled = structureOverlayEnabled(config);
  const bool etf_enabled = etfIterationsFromConfig(config) > 0;
  const bool painterly_enabled = painterlyStyleEnabled(config);
  const bool hatch_enabled = hatchStyleEnabled(config);
  const bool stipple_enabled = stippleStyleEnabled(config);
  const StippleCarrier stipple_carrier = stippleCarrierFromMode(config.mode);
  const bool flow_enabled = flowStyleEnabled(config);
  const bool cell_shade_enabled = config.style == "cell-shade";
  const std::optional<int> posterize_levels = posterizeLevelsFromConfig(config);
  const bool posterize_enabled = posterize_levels.has_value();
  const double glyph_stickiness = glyphStickinessFromConfig(config);
  const double presentation_cost_weight = presentationCostWeightFromConfig(config);
  const bool glyph_hysteresis_enabled = temporal_state != nullptr && shape_table != nullptr && glyphTemporalEnabledFromConfig(config);
  const bool orientation_hysteresis_enabled = temporal_state != nullptr && orientationTemporalEnabledFromConfig(config);
  const bool motion_flow_enabled = flow_enabled && temporal_state != nullptr;
  const int temporal_supersample = temporalSupersampleFromConfig(config);
  const std::string source_frame_input = painterly_enabled ? "styled-frame" : "frame";
  const std::string frame_input = posterize_enabled ? "posterized-frame" : source_frame_input;
  Frame styled_frame;
  Frame posterized_frame;
  ColorImageView active_image = image;
  const auto activeImage = [&]() -> const ColorImageView& {
    return active_image;
  };
  std::vector<ShapeMatchStats> worker_stats;

  const auto finish_stats = [&] {
    if (temporal_state != nullptr) {
      temporal_state->previous_shape_regions = cell_shape_regions;
    }
    for (const ShapeMatchStats& local_stats : worker_stats) {
      result.stats.shape_match_cells += local_stats.cells;
      result.stats.shape_match_ns += local_stats.ns;
      result.stats.temporal_cell_candidate_cells += local_stats.temporal_candidate_cells;
      result.stats.temporal_cell_reused_cells += local_stats.temporal_reused_cells;
      result.stats.temporal_candidate_reconstruction_score += local_stats.temporal_candidate_reconstruction_score;
      result.stats.temporal_candidate_temporal_score += local_stats.temporal_candidate_temporal_score;
      result.stats.temporal_candidate_presentation_cost += local_stats.temporal_candidate_presentation_cost;
    }
    result.stats.render_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - render_started).count();
  };

  const auto collectBudgetStatus = [&](const CellBuffer& rendered_cells) {
    if (!config.symbolic_update_budget.has_value()) {
      return;
    }
    result.stats.modeled_symbolic_update_units = modeledSymbolicUpdateUnits(*output, rendered_cells);
    result.stats.symbolic_update_budget_exceeded =
      result.stats.modeled_symbolic_update_units > *config.symbolic_update_budget;
  };

  const auto applyBudgetPressure = [&] {
    if (!config.symbolic_update_budget.has_value() || temporal_state == nullptr ||
        output->cols() != rendered_cells.cols() || output->rows() != rendered_cells.rows()) {
      return;
    }
    int64_t remaining_updates = modeledSymbolicUpdateUnits(*output, rendered_cells);
    if (remaining_updates <= *config.symbolic_update_budget) {
      return;
    }

    std::vector<BudgetCandidate> candidates;
    for (const ShapeMatchStats& local_stats : worker_stats) {
      candidates.insert(candidates.end(), local_stats.budget_candidates.begin(), local_stats.budget_candidates.end());
    }
    std::sort(candidates.begin(), candidates.end(), [](const BudgetCandidate& left, const BudgetCandidate& right) {
      const double left_loss = std::max(0.0, left.current_score.reconstruction - left.previous_score.reconstruction);
      const double right_loss = std::max(0.0, right.current_score.reconstruction - right.previous_score.reconstruction);
      if (left_loss != right_loss) {
        return left_loss < right_loss;
      }
      return left.cell_index < right.cell_index;
    });

    for (const BudgetCandidate& candidate : candidates) {
      if (remaining_updates <= *config.symbolic_update_budget) {
        break;
      }
      const Cell& previous_cell = output->cells()[candidate.cell_index];
      Cell& current_cell = rendered_cells.cells()[candidate.cell_index];
      // Retention must eliminate a modeled update, not merely exchange one
      // changed cell for another after motion compensation.
      if (current_cell == candidate.temporal_cell || previous_cell != candidate.temporal_cell) {
        continue;
      }
      current_cell = candidate.temporal_cell;
      temporal_state->glyph_hysteresis.replace(candidate.cell_index, candidate.temporal_cell.glyph, candidate.previous_score);
      --remaining_updates;
      ++result.stats.temporal_cell_reused_cells;
      ++result.stats.budget_suppressed_updates;
      result.stats.budget_reconstruction_score_loss +=
        std::max(0.0, candidate.current_score.reconstruction - candidate.previous_score.reconstruction);
    }
  };

  const auto run_graph = [&](std::vector<Pass> passes) {
    PassContext context;
    if (graph_topology == nullptr) {
      Graph graph = buildGraph(std::move(passes), renderGraphBuildOptions(config));
      ++result.stats.graph_topology_builds;
      graph.run(context);
      return;
    }

    PassCallbackMap callbacks;
    callbacks.reserve(passes.size());
    for (Pass& pass : passes) {
      if (!callbacks.emplace(std::move(pass.id), std::move(pass.run)).second) {
        throw GraphError("duplicate render callback");
      }
    }
    graph_topology->run(context, callbacks);
    ++result.stats.graph_topology_reuses;
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
        styled_frame = applyKuwaharaFilter(activeImage(), 2);
        active_image = colorImageViewFromValidFrame(styled_frame);
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
        posterized_frame = posterizeFrameOklab(activeImage(), *posterize_levels);
        active_image = colorImageViewFromValidFrame(posterized_frame);
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
        LuminanceField current_luminance = makeLuminanceField(activeImage());
        if (temporal_state != nullptr && temporal_supersample > 1) {
          const auto supersample_started = std::chrono::steady_clock::now();
          if (input.lookahead_color.has_value()) {
            const LuminanceField next_luminance = makeLuminanceField(*input.lookahead_color);
            analysis_luminance = blendTemporalSupersample(current_luminance, next_luminance, temporal_supersample, true);
            result.stats.temporal_supersample_frames += temporal_supersample - 1;
            result.stats.temporal_supersample_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - supersample_started).count();
          } else if (temporal_state->previous_supersample_luminance.has_value()) {
            analysis_luminance = blendTemporalSupersample(current_luminance, *temporal_state->previous_supersample_luminance, temporal_supersample, false);
            result.stats.temporal_supersample_frames += temporal_supersample - 1;
            result.stats.temporal_supersample_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - supersample_started).count();
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
          renderHalfBlockFrame(activeImage(), size.cols, size.rows, cells);
        } else if (blitter == "blocks") {
          renderBlockSadFrame(activeImage(), size.cols, size.rows, cells);
        } else if (blitter == "octant") {
          renderOctantFrame(activeImage(), size.cols, size.rows, cells);
        } else if (blitter == "sextant") {
          renderSextantFrame(activeImage(), size.cols, size.rows, cells);
        } else if (blitter == "braille") {
          renderBrailleFrame(activeImage(), size.cols, size.rows, cells);
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
              average_colors[cell_index] = has_gpu_average ? gpu_structure_glyphs->average_colors[cell_index] : averageRegion(activeImage(), size.cols, size.rows, col, row);
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
          mark_backend_fallback("GPU DoG analysis unavailable; used CPU fallback");
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
          gpu_structure_glyphs = computeStructureGlyphsGpu(*analysis_luminance, size.cols, size.rows, edge_threshold, shape_table);
          if (gpu_structure_glyphs.has_value()) {
            result.stats.shape_match_cells += gpu_structure_glyphs->shape_match_cells;
            return;
          }
          structure_gradients = computeSobelGradientsGpu(*analysis_luminance);
          if (!structure_gradients.has_value()) {
            mark_backend_fallback("GPU Sobel analysis unavailable; used CPU fallback");
          }
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
          const auto flow_started = std::chrono::steady_clock::now();
          const bool inferred_flow_needed = motion_flow_enabled ||
                                            !external_motion.has_value() ||
                                            external_motion_has_invalid;
          if (inferred_flow_needed && temporal_state->previous_luminance.has_value() &&
              temporal_state->previous_luminance->width == analysis_luminance->width &&
              temporal_state->previous_luminance->height == analysis_luminance->height) {
            flow_field = computeBlockOpticalFlow(*temporal_state->previous_luminance, *analysis_luminance);
            result.stats.optical_flow_blocks += static_cast<int64_t>(flow_field->vectors.size());
            result.stats.optical_flow_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - flow_started).count();
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
        warped_previous_cells.clear();
        warped_history_available.clear();
        if (!previous_glyphs.empty()) {
          std::optional<HistoryMotionSelection> external_selection;
          const FlowField* history_flow = nullptr;
          if (external_motion.has_value()) {
            external_selection = selectHistoryMotion(*external_motion, flow_field);
            history_flow = &external_selection->flow;
            warped_history_available = external_selection->history_available;
            result.stats.external_motion_cells += external_selection->external_cells;
            result.stats.inferred_motion_cells += external_selection->inferred_cells;
            result.stats.history_suppressed_cells += external_selection->suppressed_cells;
          } else if (flow_field.has_value()) {
            history_flow = &*flow_field;
            warped_history_available.assign(static_cast<std::size_t>(size.cols) * static_cast<std::size_t>(size.rows), true);
            result.stats.inferred_motion_cells += static_cast<int64_t>(size.cols) * static_cast<int64_t>(size.rows);
          }
          if (history_flow == nullptr) {
            return;
          }
          const auto warp_started = std::chrono::steady_clock::now();
          warped_previous_glyphs = warpGlyphHistory(previous_glyphs, size.cols, size.rows, *history_flow);
          if (previous_shape_regions.size() == cell_shape_regions.size()) {
            warped_previous_shape_regions = warpCellShapeHistory(previous_shape_regions, size.cols, size.rows, *history_flow);
          }
          if (previous_cell_history != nullptr) {
            warped_previous_cells = warpCellHistory(previous_cell_history->cells(), size.cols, size.rows, *history_flow);
          }
          result.stats.warp_history_cells += static_cast<int64_t>(warped_previous_glyphs.size() + warped_previous_shape_regions.size() + warped_previous_cells.size());
          result.stats.warp_history_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - warp_started).count();
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
        const auto historyAvailable = [&](std::size_t cell_index) {
          if (!external_motion.has_value()) {
            return true;
          }
          if (glyph_hysteresis_enabled) {
            return cell_index < warped_history_available.size() && warped_history_available[cell_index];
          }
          return external_motion->vectors.at(cell_index).validity == MotionVectorValidity::Valid;
        };
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
                const auto match_started = std::chrono::steady_clock::now();
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
                  if (!historyAvailable(cell_index)) {
                    temporal_state->glyph_hysteresis.clear(cell_index);
                    cell.glyph = best.glyph;
                  } else {
                    const Cell* temporal_candidate = nullptr;
                    if (previous_cell_history != nullptr) {
                      const Cell& history_cell = warped_previous_cells.empty()
                                                   ? previous_cell_history->cells()[cell_index]
                                                   : warped_previous_cells[cell_index];
                      // Full-cell reuse needs zero color error until candidate scoring
                      // explicitly models color fidelity.
                      if (history_cell.fg == cell.fg && history_cell.bg == cell.bg) {
                        temporal_candidate = &history_cell;
                      }
                    }
                    if (temporal_candidate != nullptr) {
                      ++local_stats->temporal_candidate_cells;
                    }
                    const std::vector<char32_t>& history_glyphs = warped_previous_glyphs.empty() ? previous_glyphs : warped_previous_glyphs;
                    const std::optional<char32_t> history_glyph = history_glyphs.empty() ? std::nullopt : std::optional<char32_t>(history_glyphs[cell_index]);
                    const char32_t previous_glyph = temporal_candidate == nullptr ? history_glyph.value_or(cell.glyph) : temporal_candidate->glyph;
                    const std::vector<double> previous_features = warped_previous_shape_regions.empty()
                                                                    ? features
                                                                    : match_region(warped_previous_shape_regions[cell_index]);
                    const double previous_score = temporal_candidate == nullptr
                                                    ? scoreGlyphShape(previous_features, *shape_table, previous_glyph)
                                                    : scoreGlyphShape(features, *shape_table, previous_glyph);
                    const std::optional<char32_t> candidate_glyph = temporal_candidate == nullptr
                                                                       ? history_glyph
                                                                       : std::optional<char32_t>(temporal_candidate->glyph);
                    CandidateScore current_score{.reconstruction = best.score};
                    CandidateScore previous_candidate_score{.reconstruction = previous_score};
                    if (temporal_candidate != nullptr) {
                      if (presentation_cost_weight > 0.0) {
                        Cell current_cell = cell;
                        current_cell.glyph = best.glyph;
                        const AnsiTransitionEstimate transition = estimateAnsiCellTransition(
                          *temporal_candidate, current_cell, row + 1, col + 1);
                        current_score.presentation_cost = presentation_cost_weight * static_cast<double>(transition.ansi_bytes);
                      }
                      local_stats->temporal_candidate_reconstruction_score +=
                        current_score.reconstruction + previous_candidate_score.reconstruction;
                      local_stats->temporal_candidate_temporal_score += current_score.temporal + previous_candidate_score.temporal;
                      local_stats->temporal_candidate_presentation_cost +=
                        current_score.presentation_cost + previous_candidate_score.presentation_cost;
                      if (config.symbolic_update_budget.has_value() &&
                          candidatePreferred(previous_candidate_score, CandidateScore{})) {
                        local_stats->budget_candidates.push_back(BudgetCandidate{
                          .cell_index = cell_index,
                          .temporal_cell = *temporal_candidate,
                          .current_score = current_score,
                          .previous_score = previous_candidate_score,
                        });
                      }
                    }
                    const GlyphHysteresisDecision decision = temporal_state->glyph_hysteresis.choose(
                      cell_index,
                      GlyphCandidate{.glyph = best.glyph, .score = current_score},
                      previous_candidate_score,
                      glyph_stickiness,
                      candidate_glyph);
                    if (temporal_candidate != nullptr && decision.kept_previous && decision.glyph == temporal_candidate->glyph) {
                      cell = *temporal_candidate;
                      ++local_stats->temporal_reused_cells;
                    } else {
                      cell.glyph = decision.glyph;
                    }
                  }
                } else {
                  cell.glyph = matchGlyphShape(features, *shape_table);
                }
                ++local_stats->cells;
                local_stats->ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - match_started).count();
              } else {
                char32_t directional_glyph = *edge_glyph;
                if (orientation_hysteresis_enabled) {
                  if (!historyAvailable(cell_index)) {
                    temporal_state->orientation_hysteresis.clear(cell_index);
                  }
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

  const auto normal_orient_pass = [&](const std::string& base_input) {
    return Pass{
      .id = "normal-orient",
      .inputs = {renderPort("input-normals", BufferKind::NormalBuffer), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("normal-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        applyNormalOrient(cells, input, size.cols, size.rows);
      },
    };
  };

  const auto depth_shade_pass = [&] {
    return Pass{
      .id = "depth-shade",
      .inputs = {renderPort("input-depth", BufferKind::DepthBuffer), renderPort("input-normals", BufferKind::NormalBuffer), renderPort("normal-cells", BufferKind::CellGlyphs)},
      .outputs = {renderPort("shaded-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        applyDepthShade(cells, input, ramp, size.cols, size.rows);
      },
    };
  };

  const auto append_cell_shade_passes = [&](std::vector<Pass>* passes, const std::string& input) {
    if (!cell_shade_enabled) {
      return input;
    }
    passes->push_back(normal_orient_pass(input));
    passes->push_back(depth_shade_pass());
    return std::string("shaded-cells");
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
          applyStipple(cells, stipple_carrier, &activeImage());
        },
      });
      return std::string("stipple-cells");
    };
    std::string output = "cells";
    if (config.line_ligatures && overlay_enabled) {
      passes->push_back(line_ligatures_pass());
      output = "ligature-cells";
    }
    passes->push_back(emit_pass(append_stipple_pass(append_cell_shade_passes(passes, output))));
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
    applyBudgetPressure();
    collectBudgetStatus(rendered_cells);
    if (config.collect_symbolic_metrics) {
      collectSymbolicMetrics(*output, rendered_cells, &result.stats);
    }
    if (temporal_cell_reuse_enabled) {
      temporal_state->previous_cells = rendered_cells;
    }
    *output = std::move(rendered_cells);
    return result;
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
  applyBudgetPressure();
  collectBudgetStatus(rendered_cells);
  if (config.collect_symbolic_metrics) {
    collectSymbolicMetrics(*output, rendered_cells, &result.stats);
  }
  if (temporal_cell_reuse_enabled) {
    temporal_state->previous_cells = rendered_cells;
  }
  *output = std::move(rendered_cells);
  return result;
} catch (const std::invalid_argument& error) {
  return renderFailure(RenderStatus::InvalidConfiguration, error.what());
} catch (const std::exception& error) {
  return renderFailure(RenderStatus::InternalError, error.what());
} catch (...) {
  return renderFailure(RenderStatus::InternalError, "unexpected renderer failure");
}

RenderResult renderFrame(const RenderInput& input, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state) {
  return renderFrame(input, ramp, config, available_grid, shape_table, output, temporal_state, nullptr);
}

RenderResult renderFrame(const ColorImageView& image, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state) {
  return renderFrame(RenderInput{.color = image}, ramp, config, available_grid, shape_table, output, temporal_state, nullptr);
}

RenderResult renderFrame(const Frame& frame, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, const GlyphShapeTable* shape_table, CellBuffer* output, RenderTemporalState* temporal_state) {
  const std::optional<ColorImageView> image = colorImageViewFromFrame(frame);
  if (!image.has_value()) {
    return renderFailure(RenderStatus::InvalidInput, "frame RGB buffer does not match its dimensions");
  }
  return renderFrame(RenderInput{.color = *image}, ramp, config, available_grid, shape_table, output, temporal_state, nullptr);
}

}  // namespace strok
