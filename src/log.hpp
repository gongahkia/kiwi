#pragma once

#include <filesystem>
#include <fstream>
#include <string_view>

namespace strok {

class Logger {
 public:
  Logger() = default;
  explicit Logger(const std::filesystem::path& path);

  bool enabled() const noexcept;
  void info(std::string_view message);
  void warn(std::string_view message);
  void error(std::string_view message);

 private:
  void write(std::string_view level, std::string_view message);

  std::ofstream sink_;
};

}  // namespace strok

#define STROK_LOG_INFO(logger, message) (logger).info(message)
#define STROK_LOG_WARN(logger, message) (logger).warn(message)
#define STROK_LOG_ERROR(logger, message) (logger).error(message)
