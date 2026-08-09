#include "gpu_backend.hpp"

#include <string_view>
#include <utility>

namespace strok {
namespace {

class CpuAnalysisBackend final : public GpuAnalysisBackend {
 public:
  CpuAnalysisBackend(bool requested, Backend attempted_backend)
      : requested_(requested), attempted_backend_(attempted_backend) {}

  bool requested() const noexcept override {
    return requested_;
  }

  Backend attemptedBackend() const noexcept override {
    return attempted_backend_;
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
  Backend attempted_backend_ = Backend::Cpu;
};

class NativeAnalysisBackend final : public GpuAnalysisBackend {
 public:
  NativeAnalysisBackend(Backend backend, std::unique_ptr<GpuSobelContext> context)
      : backend_(backend), context_(std::move(context)) {}

  bool requested() const noexcept override {
    return true;
  }

  Backend attemptedBackend() const noexcept override {
    return backend_;
  }

  Backend backend() const noexcept override {
    return backend_;
  }

  std::optional<LuminanceField> differenceOfGaussians(const LuminanceField& field, DogOptions options) const override {
    return context_->differenceOfGaussians(field, options);
  }

  std::optional<GradientField> sobelGradients(const LuminanceField& field) const override {
    return context_->sobelGradients(field);
  }

  std::optional<GpuStructureGlyphs> structureGlyphs(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) const override {
    return context_->structureGlyphs(field, cols, rows, edge_threshold, shape_table);
  }

 private:
  Backend backend_ = Backend::Cpu;
  std::unique_ptr<GpuSobelContext> context_;
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
  if (!request_gpu) {
    return std::make_unique<CpuAnalysisBackend>(false, Backend::Cpu);
  }
  const Backend candidate = nativeBackend();
  if (candidate == Backend::Cpu) {
    return std::make_unique<CpuAnalysisBackend>(true, Backend::Auto);
  }
  std::unique_ptr<GpuSobelContext> context = createGpuSobelContext();
  if (!context) {
    return std::make_unique<CpuAnalysisBackend>(true, candidate);
  }
  return std::make_unique<NativeAnalysisBackend>(candidate, std::move(context));
}

}  // namespace strok
