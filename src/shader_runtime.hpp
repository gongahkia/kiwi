#pragma once

#include "frame.hpp"

#include <cstdint>
#include <filesystem>
#include <memory>

namespace contourtty {

bool shaderRuntimeAvailable();

class ShaderFrameSource {
 public:
  explicit ShaderFrameSource(std::filesystem::path path);
  ShaderFrameSource(const ShaderFrameSource&) = delete;
  ShaderFrameSource& operator=(const ShaderFrameSource&) = delete;
  ShaderFrameSource(ShaderFrameSource&&) noexcept;
  ShaderFrameSource& operator=(ShaderFrameSource&&) noexcept;
  ~ShaderFrameSource();

  void reloadIfChanged();
  Frame renderFrame(int width, int height, int64_t pts_us, int64_t frame_index, int64_t frame_delta_us);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace contourtty
