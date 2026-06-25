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
  void restart();
  bool isStillImage() const noexcept;
  bool isAnimatedImage() const noexcept;
  std::optional<double> averageFps() const noexcept;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace contourtty
