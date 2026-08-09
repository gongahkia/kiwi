#pragma once

#include "gpu_sobel.hpp"
#include "render_graph.hpp"

#include <memory>
#include <optional>

namespace strok {

// Renderer-owned boundary for library-managed analysis backends. It keeps
// selection, fallback, use, and destruction at the Renderer lifecycle boundary;
// native resource persistence is added by the platform backends separately.
class GpuAnalysisBackend {
 public:
  virtual ~GpuAnalysisBackend() = default;

  virtual bool requested() const noexcept = 0;
  virtual Backend backend() const noexcept = 0;
  virtual std::optional<LuminanceField> differenceOfGaussians(const LuminanceField& field, DogOptions options) const = 0;
  virtual std::optional<GradientField> sobelGradients(const LuminanceField& field) const = 0;
  virtual std::optional<GpuStructureGlyphs> structureGlyphs(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) const = 0;
};

std::unique_ptr<GpuAnalysisBackend> createGpuAnalysisBackend(bool request_gpu);

}  // namespace strok
