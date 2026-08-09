#pragma once

#include "frame.hpp"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>

namespace strok {

enum class RtspTransport {
  Auto,
  Tcp,
  Udp,
};

struct VideoDecoderOptions {
  std::chrono::milliseconds input_open_timeout {5000};
  std::chrono::milliseconds read_timeout {5000};
  RtspTransport rtsp_transport = RtspTransport::Auto;
};

class VideoDecoder {
 public:
  explicit VideoDecoder(const std::filesystem::path& input,
                        VideoDecoderOptions options = {},
                        const std::atomic<bool>* external_stop_requested = nullptr);
  VideoDecoder(const VideoDecoder&) = delete;
  VideoDecoder& operator=(const VideoDecoder&) = delete;
  VideoDecoder(VideoDecoder&&) noexcept;
  VideoDecoder& operator=(VideoDecoder&&) noexcept;
  ~VideoDecoder();

  std::optional<Frame> nextFrame();
  void stop() noexcept;
  void seekToUs(int64_t position_us);
  void restart();
  bool isStillImage() const noexcept;
  bool isAnimatedImage() const noexcept;
  std::optional<double> averageFps() const noexcept;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace strok
