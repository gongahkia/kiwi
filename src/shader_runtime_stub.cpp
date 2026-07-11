#include "shader_runtime.hpp"

#include <stdexcept>
#include <utility>

namespace strok {

bool shaderRuntimeAvailable() {
  return false;
}

struct ShaderFrameSource::Impl {};

ShaderFrameSource::ShaderFrameSource(std::filesystem::path) {
  throw std::runtime_error("shader runtime is unavailable on this build");
}

ShaderFrameSource::ShaderFrameSource(ShaderFrameSource&&) noexcept = default;
ShaderFrameSource& ShaderFrameSource::operator=(ShaderFrameSource&&) noexcept = default;
ShaderFrameSource::~ShaderFrameSource() = default;

void ShaderFrameSource::reloadIfChanged() {}

Frame ShaderFrameSource::renderFrame(int, int, int64_t, int64_t, int64_t) {
  throw std::runtime_error("shader runtime is unavailable on this build");
}

}  // namespace strok
