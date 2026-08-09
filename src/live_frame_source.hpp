#pragma once

#include "frame.hpp"

#include <chrono>
#include <cstddef>
#include <filesystem>
#include <memory>
#include <optional>

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

class LatestFrameQueue {
 public:
  explicit LatestFrameQueue(std::size_t capacity);

  LatestFrameQueue(const LatestFrameQueue&) = delete;
  LatestFrameQueue& operator=(const LatestFrameQueue&) = delete;

  bool push(LiveFrame frame);
  std::optional<LiveFrameBatch> waitForLatest();
  void close();
  std::size_t capacity() const noexcept;

 private:
  struct State;
  std::unique_ptr<State> state_;
};

class LiveFrameSource {
 public:
  explicit LiveFrameSource(const std::filesystem::path& input);

  LiveFrameSource(const LiveFrameSource&) = delete;
  LiveFrameSource& operator=(const LiveFrameSource&) = delete;
  LiveFrameSource(LiveFrameSource&&) = delete;
  LiveFrameSource& operator=(LiveFrameSource&&) = delete;
  ~LiveFrameSource();

  std::optional<LiveFrameBatch> waitForLatest();
  std::optional<double> averageFps() const noexcept;
  void stop() noexcept;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace strok
