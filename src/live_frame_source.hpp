#pragma once

#include "frame.hpp"
#include "video_decoder.hpp"

#include <chrono>
#include <cstddef>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

namespace strok {

struct LiveFrame {
  Frame frame;
  std::chrono::steady_clock::time_point decoded_at;
};

struct LiveFrameBatch {
  LiveFrame latest;
  std::size_t producer_replaced = 0;
  std::size_t consumer_discarded = 0;
};

enum class LiveSourceState {
  Connecting,
  Streaming,
  Reconnecting,
  Stopped,
  Failed,
};

std::string_view liveSourceStateName(LiveSourceState state) noexcept;

struct LiveSourceStatus {
  LiveSourceState state = LiveSourceState::Connecting;
  int reconnect_attempts = 0;
  std::string message;
  std::optional<double> average_fps;
};

struct LiveSourceOptions {
  VideoDecoderOptions decoder;
  bool reconnect = true;
  std::chrono::milliseconds reconnect_backoff {1000};
};

class LatestFrameQueue {
 public:
  explicit LatestFrameQueue(std::size_t capacity);
  ~LatestFrameQueue();

  LatestFrameQueue(const LatestFrameQueue&) = delete;
  LatestFrameQueue& operator=(const LatestFrameQueue&) = delete;

  bool push(LiveFrame frame);
  std::optional<LiveFrameBatch> waitForLatest();
  std::optional<LiveFrameBatch> waitForLatestFor(std::chrono::milliseconds timeout);
  void close();
  bool closed() const;
  std::size_t capacity() const noexcept;

 private:
  struct State;
  std::unique_ptr<State> state_;
};

class LiveFrameSource {
 public:
  explicit LiveFrameSource(const std::filesystem::path& input, LiveSourceOptions options = {});

  LiveFrameSource(const LiveFrameSource&) = delete;
  LiveFrameSource& operator=(const LiveFrameSource&) = delete;
  LiveFrameSource(LiveFrameSource&&) = delete;
  LiveFrameSource& operator=(LiveFrameSource&&) = delete;
  ~LiveFrameSource();

  std::optional<LiveFrameBatch> waitForLatest();
  std::optional<LiveFrameBatch> waitForLatestFor(std::chrono::milliseconds timeout);
  bool closed() const;
  std::optional<double> averageFps() const;
  LiveSourceStatus status() const;
  void stop() noexcept;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace strok
