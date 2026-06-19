#pragma once

#include "frame.hpp"

#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>

namespace contourtty {

class VideoDecoder {
 public:
  explicit VideoDecoder(const std::filesystem::path& input);
  VideoDecoder(const VideoDecoder&) = delete;
  VideoDecoder& operator=(const VideoDecoder&) = delete;
  VideoDecoder(VideoDecoder&&) noexcept;
  VideoDecoder& operator=(VideoDecoder&&) noexcept;
  ~VideoDecoder();

  std::optional<Frame> nextFrame();
  void seekToUs(int64_t position_us);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace contourtty
