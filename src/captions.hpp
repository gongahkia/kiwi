#pragma once

#include "frame.hpp"

#include <cstdint>
#include <optional>
#include <string>

namespace strok {

std::string summariseFrameCaption(const Frame& frame);
std::string formatSrtTimestamp(int64_t pts_us);
std::string formatSrtCue(int index, int64_t start_us, int64_t end_us, const std::string& text);

class CaptionSrtBuilder {
 public:
  explicit CaptionSrtBuilder(int64_t fallback_duration_us = 33333);

  void recordFrame(const Frame& frame, int64_t start_us);
  std::string finish();
  int cueCount() const noexcept;

 private:
  struct PendingCue {
    int64_t start_us = 0;
    std::string text;
  };

  int64_t fallback_duration_us_ = 33333;
  int next_index_ = 1;
  int cue_count_ = 0;
  bool finished_ = false;
  std::optional<PendingCue> pending_;
  std::string srt_;
};

}  // namespace strok
