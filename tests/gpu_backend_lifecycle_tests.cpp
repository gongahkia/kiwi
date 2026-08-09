#include "gpu_backend.hpp"

#include <cstdlib>
#include <iostream>
#include <memory>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  const std::unique_ptr<strok::GpuAnalysisBackend> cpu = strok::createGpuAnalysisBackend(false);
  expect(cpu != nullptr && !cpu->requested() && cpu->backend() == strok::Backend::Cpu,
         "CPU backend is renderer-owned when GPU is not requested");

  const std::unique_ptr<strok::GpuAnalysisBackend> requested = strok::createGpuAnalysisBackend(true);
  expect(requested != nullptr && requested->requested(), "GPU request creates a backend lifecycle object");
  expect(requested->backend() == strok::Backend::Cpu || requested->backend() == strok::Backend::Metal ||
             requested->backend() == strok::Backend::Vulkan,
         "GPU request resolves to an explicit backend or CPU fallback");
}
