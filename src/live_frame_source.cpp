#include "live_frame_source.hpp"

#include "video_decoder.hpp"

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

void LatestFrameQueue::close() {
  {
    std::lock_guard lock(state_->mutex);
    state_->closed = true;
  }
  state_->ready.notify_all();
}

std::size_t LatestFrameQueue::capacity() const noexcept {
  return state_->capacity;
}

struct LiveFrameSource::Impl {
  explicit Impl(const std::filesystem::path& input)
      : decoder(input), average_fps(decoder.averageFps()), queue(2), worker([this] { decode(); }) {}

  ~Impl() {
    stop();
    if (worker.joinable()) {
      worker.join();
    }
  }

  void decode() {
    try {
      while (!stop_requested.load(std::memory_order_relaxed)) {
        std::optional<Frame> frame = decoder.nextFrame();
        if (!frame.has_value()) {
          break;
        }
        if (!queue.push(LiveFrame{
              .frame = std::move(*frame),
              .decoded_at = std::chrono::steady_clock::now(),
            })) {
          break;
        }
      }
    } catch (...) {
      if (!stop_requested.load(std::memory_order_relaxed)) {
        std::lock_guard lock(error_mutex);
        error = std::current_exception();
      }
    }
    queue.close();
  }

  std::optional<LiveFrameBatch> waitForLatest() {
    const std::optional<LiveFrameBatch> batch = queue.waitForLatest();
    if (!batch.has_value()) {
      std::exception_ptr worker_error;
      {
        std::lock_guard lock(error_mutex);
        worker_error = error;
      }
      if (worker_error != nullptr) {
        std::rethrow_exception(worker_error);
      }
    }
    return batch;
  }

  void stop() noexcept {
    stop_requested.store(true, std::memory_order_relaxed);
    decoder.stop();
    queue.close();
  }

  VideoDecoder decoder;
  std::optional<double> average_fps;
  LatestFrameQueue queue;
  std::atomic<bool> stop_requested = false;
  std::thread worker;
  std::mutex error_mutex;
  std::exception_ptr error;
};

LiveFrameSource::LiveFrameSource(const std::filesystem::path& input) : impl_(std::make_unique<Impl>(input)) {}

LiveFrameSource::~LiveFrameSource() = default;

std::optional<LiveFrameBatch> LiveFrameSource::waitForLatest() {
  return impl_->waitForLatest();
}

std::optional<double> LiveFrameSource::averageFps() const noexcept {
  return impl_->average_fps;
}

void LiveFrameSource::stop() noexcept {
  impl_->stop();
}

}  // namespace strok
