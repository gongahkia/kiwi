#include "metrics_jsonl.hpp"

#include <fstream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>

namespace strok {

struct MetricsJsonlWriter::State {
  explicit State(const std::filesystem::path &path)
      : sink(path, std::ios::out | std::ios::app) {}

  std::mutex mutex;
  std::ofstream sink;
};

MetricsJsonlWriter::MetricsJsonlWriter(const std::filesystem::path &path)
    : state_(std::make_shared<State>(path)) {
  if (!state_->sink) {
    throw std::runtime_error("failed to open metrics JSONL file: " +
                             path.string());
  }
}

bool MetricsJsonlWriter::write(std::string_view line) noexcept {
  const std::shared_ptr<State> state = state_;
  if (state == nullptr) {
    return false;
  }
  std::lock_guard lock(state->mutex);
  if (!state->sink.is_open()) {
    return false;
  }
  state->sink << line << '\n';
  state->sink.flush();
  return static_cast<bool>(state->sink);
}

} // namespace strok
