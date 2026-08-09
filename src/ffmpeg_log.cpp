#include "ffmpeg_log.hpp"

#include <algorithm>
#include <cstdarg>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <string_view>

extern "C" {
#include <libavutil/log.h>
}

namespace strok {
namespace {

struct CallbackTarget {
  Logger logger;
  int maximum_level = AV_LOG_QUIET;
};

std::mutex g_callback_mutex;
std::shared_ptr<CallbackTarget> g_callback_target;

int ffmpegLevel(std::string_view level) {
  if (level == "off") {
    return AV_LOG_QUIET;
  }
  if (level == "error") {
    return AV_LOG_ERROR;
  }
  if (level == "warning") {
    return AV_LOG_WARNING;
  }
  if (level == "info") {
    return AV_LOG_INFO;
  }
  if (level == "debug") {
    return AV_LOG_DEBUG;
  }
  if (level == "trace") {
    return AV_LOG_TRACE;
  }
  throw std::invalid_argument("invalid FFmpeg log level");
}

std::string_view ffmpegLevelName(int level) {
  if (level <= AV_LOG_ERROR) {
    return "error";
  }
  if (level <= AV_LOG_WARNING) {
    return "warning";
  }
  if (level <= AV_LOG_INFO) {
    return "info";
  }
  if (level <= AV_LOG_DEBUG) {
    return "debug";
  }
  return "trace";
}

void trimLine(std::string *line) {
  while (!line->empty() && (line->back() == '\n' || line->back() == '\r' ||
                            line->back() == ' ' || line->back() == '\t')) {
    line->pop_back();
  }
}

void ffmpegLogCallback(void *context, int level, const char *format,
                       va_list arguments) {
  std::shared_ptr<CallbackTarget> target;
  {
    std::lock_guard lock(g_callback_mutex);
    target = g_callback_target;
  }
  const int normalized_level = level & 0xff;
  if (target == nullptr || normalized_level > target->maximum_level) {
    return;
  }
  thread_local int print_prefix = 1;
  char buffer[2048]{};
  av_log_format_line2(context, level, format, arguments, buffer, sizeof(buffer),
                      &print_prefix);
  std::string message(buffer);
  trimLine(&message);
  if (!message.empty()) {
    target->logger.info(
        "ffmpeg level=" + std::string(ffmpegLevelName(normalized_level)) +
        " message=" + message);
  }
}

} // namespace

struct FfmpegLogScope::Impl {
  int previous_level = AV_LOG_INFO;
  bool installed_callback = false;
};

FfmpegLogScope::FfmpegLogScope(std::string_view level, Logger logger)
    : impl_(std::make_unique<Impl>()) {
  const int selected_level = ffmpegLevel(level);
  std::lock_guard lock(g_callback_mutex);
  impl_->previous_level = av_log_get_level();
  if (selected_level == AV_LOG_QUIET) {
    g_callback_target.reset();
    av_log_set_callback(av_log_default_callback);
    av_log_set_level(AV_LOG_QUIET);
    return;
  }
  if (!logger.enabled()) {
    throw std::invalid_argument("FFmpeg diagnostics require an enabled logger");
  }
  g_callback_target = std::make_shared<CallbackTarget>(CallbackTarget{
      .logger = std::move(logger),
      .maximum_level = selected_level,
  });
  av_log_set_callback(ffmpegLogCallback);
  av_log_set_level(selected_level);
  impl_->installed_callback = true;
}

FfmpegLogScope::~FfmpegLogScope() {
  if (impl_ == nullptr) {
    return;
  }
  std::lock_guard lock(g_callback_mutex);
  g_callback_target.reset();
  av_log_set_callback(av_log_default_callback);
  av_log_set_level(impl_->previous_level);
}

} // namespace strok
