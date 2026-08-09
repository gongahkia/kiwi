#pragma once

#include "log.hpp"

#include <memory>
#include <string_view>

namespace strok {

// FFmpeg logging is process-global. The CLI creates exactly one scope before
// opening any media and tears it down after all decoder workers have stopped.
class FfmpegLogScope {
public:
  FfmpegLogScope(std::string_view level, Logger logger);
  FfmpegLogScope(const FfmpegLogScope &) = delete;
  FfmpegLogScope &operator=(const FfmpegLogScope &) = delete;
  FfmpegLogScope(FfmpegLogScope &&) = delete;
  FfmpegLogScope &operator=(FfmpegLogScope &&) = delete;
  ~FfmpegLogScope();

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace strok
