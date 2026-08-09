#include "gpu_backend.hpp"

#include <string_view>
#include <utility>

namespace strok {
namespace {

class CpuAnalysisBackend final : public GpuAnalysisBackend {
 public:
  explicit CpuAnalysisBackend(bool requested) : requested_(requested) {}

  bool requested() const noexcept override {
    return requested_;
  }

  Backend backend() const noexcept override {
    return Backend::Cpu;
  }

  std::optional<LuminanceField> differenceOfGaussians(const LuminanceField&, DogOptions) const override {
    return std::nullopt;
  }

  std::optional<GradientField> sobelGradients(const LuminanceField&) const override {
    return std::nullopt;
  }

  std::optional<GpuStructureGlyphs> structureGlyphs(const LuminanceField&, int, int, double, const GlyphShapeTable*) const override {
    return std::nullopt;
  }

 private:
  bool requested_ = false;
};

class NativeAnalysisBackend final : public GpuAnalysisBackend {
 public:
  explicit NativeAnalysisBackend(Backend backend) : backend_(backend) {}

  bool requested() const noexcept override {
    return true;
  }

  Backend backend() const noexcept override {
    return backend_;
  }

  std::optional<LuminanceField> differenceOfGaussians(const LuminanceField& field, DogOptions options) const override {
    return differenceOfGaussiansGpu(field, options);
  }

  std::optional<GradientField> sobelGradients(const LuminanceField& field) const override {
    return computeSobelGradientsGpu(field);
  }

  std::optional<GpuStructureGlyphs> structureGlyphs(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) const override {
    return computeStructureGlyphsGpu(field, cols, rows, edge_threshold, shape_table);
  }

 private:
  Backend backend_ = Backend::Cpu;
};

Backend nativeBackend() noexcept {
  const std::string_view name = gpuSobelBackendName();
  if (name == "Metal") {
    return Backend::Metal;
  }
  if (name == "Vulkan") {
    return Backend::Vulkan;
  }
  return Backend::Cpu;
}

}  // namespace

std::unique_ptr<GpuAnalysisBackend> createGpuAnalysisBackend(bool request_gpu) {
  if (!request_gpu || !gpuSobelAvailable()) {
    return std::make_unique<CpuAnalysisBackend>(request_gpu);
  }
  const Backend backend = nativeBackend();
  if (backend == Backend::Cpu) {
    return std::make_unique<CpuAnalysisBackend>(true);
  }
  return std::make_unique<NativeAnalysisBackend>(backend);
}

}  // namespace strok
