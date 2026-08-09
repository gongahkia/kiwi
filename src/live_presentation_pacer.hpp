#pragma once

#include <algorithm>
#include <chrono>
#include <cmath>
#include <optional>

namespace strok {

struct LivePresentationTiming {
  std::chrono::microseconds interval {0};
  bool terminal_overrun = false;
};

class LivePresentationPacer {
 public:
  LivePresentationPacer(std::optional<double> fps,
                        std::optional<double> max_fps,
                        std::optional<double> source_fps) {
    std::optional<double> cap;
    if (fps.has_value() && *fps > 0.0) {
      cap = *fps;
    }
    if (max_fps.has_value() && *max_fps > 0.0) {
      cap = cap.has_value() ? std::min(*cap, *max_fps) : *max_fps;
    }
    if (cap.has_value()) {
      requested_interval_ = frameInterval(*cap);
    }
    const double nominal_fps = source_fps.has_value() && *source_fps > 0.0 ? *source_fps : 30.0;
    source_interval_ = frameInterval(nominal_fps);
    late_budget_ = std::min(source_interval_, std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::milliseconds(50)));
  }

  bool ready(std::chrono::steady_clock::time_point now) const {
    return !next_presentation_.has_value() || now >= *next_presentation_;
  }

  bool isLate(std::chrono::steady_clock::time_point decoded_at,
              std::chrono::steady_clock::time_point now) const {
    return now - decoded_at > late_budget_;
  }

  LivePresentationTiming recordWrite(std::chrono::nanoseconds write_time,
                                     std::chrono::steady_clock::time_point completed_at) {
    const auto write_interval = std::min(
      std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::seconds(1)),
      std::max(std::chrono::microseconds(0), std::chrono::duration_cast<std::chrono::microseconds>(write_time)));
    const std::chrono::microseconds interval = requested_interval_.has_value()
                                                  ? std::max(*requested_interval_, write_interval)
                                                  : write_interval;
    if (interval.count() > 0) {
      next_presentation_ = completed_at + interval;
    } else {
      next_presentation_.reset();
    }
    return LivePresentationTiming{
      .interval = interval,
      .terminal_overrun = write_interval > source_interval_,
    };
  }

 private:
  static std::chrono::microseconds frameInterval(double fps) {
    return std::chrono::microseconds(static_cast<int64_t>(std::llround(1000000.0 / fps)));
  }

  std::optional<std::chrono::microseconds> requested_interval_;
  std::optional<std::chrono::steady_clock::time_point> next_presentation_;
  std::chrono::microseconds source_interval_ {33333};
  std::chrono::microseconds late_budget_ {33333};
};

}  // namespace strok
