#include "log.hpp"

#include <fstream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>

namespace strok {

struct Logger::State {
  explicit State(const std::filesystem::path& path) : sink(path, std::ios::out | std::ios::app) {}

  mutable std::mutex mutex;
  std::ofstream sink;
};

Logger::Logger(const std::filesystem::path& path) : state_(std::make_shared<State>(path)) {
  if (!state_->sink) {
    throw std::runtime_error("failed to open log file: " + path.string());
  }
}

bool Logger::enabled() const noexcept {
  const std::shared_ptr<State> state = state_;
  if (state == nullptr) {
    return false;
  }
  std::lock_guard lock(state->mutex);
  return state->sink.is_open();
}

void Logger::info(std::string_view message) {
  write("info", message);
}

void Logger::warn(std::string_view message) {
  write("warn", message);
}

void Logger::error(std::string_view message) {
  write("error", message);
}

void Logger::write(std::string_view level, std::string_view message) {
  const std::shared_ptr<State> state = state_;
  if (state == nullptr) {
    return;
  }
  std::lock_guard lock(state->mutex);
  if (!state->sink.is_open()) {
    return;
  }
  state->sink << '[' << level << "] " << message << '\n';
  if (level == "error") {
    state->sink.flush();
  }
}

}  // namespace strok
