#pragma once

#include "glyph_shape.hpp"
#include "luminance.hpp"
#include "structure_edges.hpp"

#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

namespace strok {

struct GpuStructureGlyphs {
  std::vector<char32_t> glyphs;
  std::vector<Rgb> average_colors;
  int64_t shape_match_cells = 0;
};

// Library-owned native analysis state. A Renderer receives one instance when a
// platform backend is available; callers never supply native GPU handles.
class GpuSobelContext {
 public:
  virtual ~GpuSobelContext() = default;

  virtual std::optional<LuminanceField> differenceOfGaussians(const LuminanceField& field, DogOptions options) = 0;
  virtual std::optional<GradientField> sobelGradients(const LuminanceField& field) = 0;
  virtual std::optional<GpuStructureGlyphs> structureGlyphs(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) = 0;
};

std::unique_ptr<GpuSobelContext> createGpuSobelContext();

bool gpuSobelAvailable();
const char* gpuSobelBackendName();
std::optional<LuminanceField> differenceOfGaussiansGpu(const LuminanceField& field, DogOptions options);
std::optional<GradientField> computeSobelGradientsGpu(const LuminanceField& field);
std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table);
std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const Frame& frame, const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table);

}  // namespace strok
