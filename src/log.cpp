#include "log.hpp"

#include <stdexcept>
#include <string>

namespace contourtty {

Logger::Logger(const std::filesystem::path& path) : sink_(path, std::ios::out | std::ios::app) {
  if (!sink_) {
    throw std::runtime_error("failed to open log file: " + path.string());
  }
}

bool Logger::enabled() const noexcept {
  return sink_.is_open();
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
  if (!enabled()) {
    return;
  }
  sink_ << '[' << level << "] " << message << '\n';
  sink_.flush();
}

}  // namespace contourtty
