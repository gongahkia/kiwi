#include "live_frame_source.hpp"

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <exception>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <utility>

namespace strok {

struct LatestFrameQueue::State {
  explicit State(std::size_t queue_capacity) : capacity(queue_capacity) {
    if (capacity == 0) {
      throw std::invalid_argument("live frame queue capacity must be positive");
    }
  }

  const std::size_t capacity;
  std::mutex mutex;
  std::condition_variable ready;
  std::deque<LiveFrame> frames;
  std::size_t producer_replaced = 0;
  bool closed = false;
};

LatestFrameQueue::LatestFrameQueue(std::size_t capacity) : state_(std::make_unique<State>(capacity)) {}

LatestFrameQueue::~LatestFrameQueue() = default;

bool LatestFrameQueue::push(LiveFrame frame) {
  std::lock_guard lock(state_->mutex);
  if (state_->closed) {
    return false;
  }
  if (state_->frames.size() == state_->capacity) {
    state_->frames.pop_front();
    ++state_->producer_replaced;
  }
  state_->frames.push_back(std::move(frame));
  state_->ready.notify_one();
  return true;
}

std::optional<LiveFrameBatch> LatestFrameQueue::waitForLatest() {
  std::unique_lock lock(state_->mutex);
  state_->ready.wait(lock, [&] { return state_->closed || !state_->frames.empty(); });
  if (state_->frames.empty()) {
    return std::nullopt;
  }

  const std::size_t consumer_discarded = state_->frames.size() - 1U;
  LiveFrame latest = std::move(state_->frames.back());
  state_->frames.clear();
  LiveFrameBatch batch{
    .latest = std::move(latest),
    .producer_replaced = state_->producer_replaced,
    .consumer_discarded = consumer_discarded,
  };
  state_->producer_replaced = 0;
  return batch;
}

std::optional<LiveFrameBatch> LatestFrameQueue::waitForLatestFor(std::chrono::milliseconds timeout) {
  std::unique_lock lock(state_->mutex);
  if (!state_->ready.wait_for(lock, timeout, [&] { return state_->closed || !state_->frames.empty(); })) {
    return std::nullopt;
  }
  if (state_->frames.empty()) {
    return std::nullopt;
  }

  const std::size_t consumer_discarded = state_->frames.size() - 1U;
  LiveFrame latest = std::move(state_->frames.back());
  state_->frames.clear();
  LiveFrameBatch batch{
    .latest = std::move(latest),
    .producer_replaced = state_->producer_replaced,
    .consumer_discarded = consumer_discarded,
  };
  state_->producer_replaced = 0;
  return batch;
}

void LatestFrameQueue::close() {
  {
    std::lock_guard lock(state_->mutex);
    state_->closed = true;
  }
  state_->ready.notify_all();
}

bool LatestFrameQueue::closed() const {
  std::lock_guard lock(state_->mutex);
  return state_->closed;
}

std::size_t LatestFrameQueue::capacity() const noexcept {
  return state_->capacity;
}

std::string_view liveSourceStateName(LiveSourceState state) noexcept {
  switch (state) {
    case LiveSourceState::Connecting:
      return "connecting";
    case LiveSourceState::Streaming:
      return "streaming";
    case LiveSourceState::Reconnecting:
      return "reconnecting";
    case LiveSourceState::Stopped:
      return "stopped";
    case LiveSourceState::Failed:
      return "failed";
  }
  return "unknown";
}

struct LiveFrameSource::Impl {
  explicit Impl(std::filesystem::path source_input, LiveSourceOptions source_options)
      : input(std::move(source_input)), options(std::move(source_options)), queue(2), worker([this] { decode(); }) {}

  ~Impl() {
    stop();
    if (worker.joinable()) {
      worker.join();
    }
  }

  void decode() {
    int reconnect_attempts = 0;
    int consecutive_failures = 0;
    while (!stop_requested.load(std::memory_order_relaxed)) {
      updateStatus(reconnect_attempts == 0 ? LiveSourceState::Connecting : LiveSourceState::Reconnecting,
                   reconnect_attempts,
                   reconnect_attempts == 0 ? std::string{} : "opening live source");
      try {
        VideoDecoder decoder(input, options.decoder, &stop_requested);
        const std::optional<double> average_fps = decoder.averageFps();
        updateStatus(LiveSourceState::Streaming, reconnect_attempts, {}, average_fps);
        bool produced_frame = false;
        while (!stop_requested.load(std::memory_order_relaxed)) {
          std::optional<Frame> frame = decoder.nextFrame();
          if (!frame.has_value()) {
            if (stop_requested.load(std::memory_order_relaxed)) {
              break;
            }
            throw std::runtime_error("live input ended");
          }
          if (!produced_frame) {
            produced_frame = true;
            consecutive_failures = 0;
          }
          if (!queue.push(LiveFrame{
                .frame = std::move(*frame),
                .decoded_at = std::chrono::steady_clock::now(),
              })) {
            break;
          }
        }
        if (stop_requested.load(std::memory_order_relaxed)) {
          break;
        }
        if (!produced_frame) {
          throw std::runtime_error("live input ended before a frame was decoded");
        }
        throw std::runtime_error("live input stopped producing frames");
      } catch (const std::exception& exception) {
        if (stop_requested.load(std::memory_order_relaxed)) {
          break;
        }
        if (!scheduleReconnect(std::current_exception(), exception.what(), &reconnect_attempts, &consecutive_failures)) {
          break;
        }
      } catch (...) {
        if (stop_requested.load(std::memory_order_relaxed)) {
          break;
        }
        if (!scheduleReconnect(std::current_exception(), "unexpected live input failure", &reconnect_attempts, &consecutive_failures)) {
          break;
        }
      }
    }
    if (stop_requested.load(std::memory_order_relaxed)) {
      updateStatus(LiveSourceState::Stopped, reconnect_attempts, {});
    }
    queue.close();
  }

  bool scheduleReconnect(std::exception_ptr attempt_error,
                         std::string message,
                         int* reconnect_attempts,
                         int* consecutive_failures) {
    if (!options.reconnect) {
      {
        std::lock_guard lock(error_mutex);
        error = std::move(attempt_error);
      }
      updateStatus(LiveSourceState::Failed, *reconnect_attempts, std::move(message));
      return false;
    }
    ++*reconnect_attempts;
    ++*consecutive_failures;
    const std::chrono::milliseconds delay = reconnectDelay(*consecutive_failures);
    updateStatus(LiveSourceState::Reconnecting,
                 *reconnect_attempts,
                 std::move(message) + "; retrying in " + std::to_string(delay.count()) + "ms");
    std::unique_lock lock(reconnect_mutex);
    reconnect_ready.wait_for(lock, delay, [&] { return stop_requested.load(std::memory_order_relaxed); });
    return !stop_requested.load(std::memory_order_relaxed);
  }

  std::chrono::milliseconds reconnectDelay(int consecutive_failures) const {
    int64_t delay_ms = std::max<int64_t>(1, options.reconnect_backoff.count());
    for (int attempt = 1; attempt < consecutive_failures && delay_ms < 30000; ++attempt) {
      delay_ms = std::min<int64_t>(30000, delay_ms * 2);
    }
    return std::chrono::milliseconds(delay_ms);
  }

  void updateStatus(LiveSourceState state,
                    int reconnect_attempts,
                    std::string message,
                    std::optional<double> average_fps = std::nullopt) {
    std::lock_guard lock(status_mutex);
    status.state = state;
    status.reconnect_attempts = reconnect_attempts;
    status.message = std::move(message);
    status.average_fps = average_fps;
  }

  std::optional<LiveFrameBatch> waitForLatest() {
    const std::optional<LiveFrameBatch> batch = queue.waitForLatest();
    rethrowWorkerErrorIfClosed(batch);
    return batch;
  }

  std::optional<LiveFrameBatch> waitForLatestFor(std::chrono::milliseconds timeout) {
    const std::optional<LiveFrameBatch> batch = queue.waitForLatestFor(timeout);
    rethrowWorkerErrorIfClosed(batch);
    return batch;
  }

  void rethrowWorkerErrorIfClosed(const std::optional<LiveFrameBatch>& batch) {
    if (!batch.has_value()) {
      if (!queue.closed()) {
        return;
      }
      std::exception_ptr worker_error;
      {
        std::lock_guard lock(error_mutex);
        worker_error = error;
      }
      if (worker_error != nullptr) {
        std::rethrow_exception(worker_error);
      }
    }
  }

  void stop() noexcept {
    stop_requested.store(true, std::memory_order_relaxed);
    reconnect_ready.notify_all();
    queue.close();
  }

  std::filesystem::path input;
  LiveSourceOptions options;
  LatestFrameQueue queue;
  std::atomic<bool> stop_requested = false;
  std::thread worker;
  std::mutex error_mutex;
  std::exception_ptr error;
  std::mutex reconnect_mutex;
  std::condition_variable reconnect_ready;
  mutable std::mutex status_mutex;
  LiveSourceStatus status;
};

LiveFrameSource::LiveFrameSource(const std::filesystem::path& input, LiveSourceOptions options)
    : impl_(std::make_unique<Impl>(input, std::move(options))) {}

LiveFrameSource::~LiveFrameSource() = default;

std::optional<LiveFrameBatch> LiveFrameSource::waitForLatest() {
  return impl_->waitForLatest();
}

std::optional<LiveFrameBatch> LiveFrameSource::waitForLatestFor(std::chrono::milliseconds timeout) {
  return impl_->waitForLatestFor(timeout);
}

bool LiveFrameSource::closed() const {
  return impl_->queue.closed();
}

std::optional<double> LiveFrameSource::averageFps() const {
  return status().average_fps;
}

LiveSourceStatus LiveFrameSource::status() const {
  std::lock_guard lock(impl_->status_mutex);
  return impl_->status;
}

void LiveFrameSource::stop() noexcept {
  impl_->stop();
}

}  // namespace strok
