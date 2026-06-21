#pragma once

#include <chrono>
#include <cstddef>
#include <deque>

namespace contourtty {

struct BandwidthDecision {
  bool send = true;
  bool warn = false;
  std::size_t window_bytes = 0;
};

class BandwidthGuard {
 public:
  explicit BandwidthGuard(double cap_mb_per_s, std::chrono::steady_clock::duration window = std::chrono::seconds(1));

  BandwidthDecision recordFrame(std::size_t bytes, std::chrono::steady_clock::time_point now);
  void reset();

 private:
  double cap_bytes_per_s_ = 0.0;
  std::chrono::steady_clock::duration window_;
  std::deque<std::pair<std::chrono::steady_clock::time_point, std::size_t>> samples_;
  std::size_t window_bytes_ = 0;
  bool warned_ = false;
};

}  // namespace contourtty
