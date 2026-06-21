#include "bandwidth_guard.hpp"

#include <stdexcept>

namespace contourtty {
namespace {

constexpr double kBytesPerMegabyte = 1000000.0;

}  // namespace

BandwidthGuard::BandwidthGuard(double cap_mb_per_s, std::chrono::steady_clock::duration window)
    : cap_bytes_per_s_(cap_mb_per_s * kBytesPerMegabyte), window_(window) {
  if (cap_mb_per_s <= 0.0 || window_ <= std::chrono::steady_clock::duration::zero()) {
    throw std::invalid_argument("bandwidth cap and window must be positive");
  }
}

BandwidthDecision BandwidthGuard::recordFrame(std::size_t bytes, std::chrono::steady_clock::time_point now) {
  while (!samples_.empty() && now - samples_.front().first >= window_) {
    window_bytes_ -= samples_.front().second;
    samples_.pop_front();
  }

  const double cap_bytes = cap_bytes_per_s_ * std::chrono::duration<double>(window_).count();
  if (static_cast<double>(window_bytes_ + bytes) > cap_bytes) {
    const bool warn = !warned_;
    warned_ = true;
    return BandwidthDecision{.send = false, .warn = warn, .window_bytes = window_bytes_};
  }

  samples_.push_back({now, bytes});
  window_bytes_ += bytes;
  return BandwidthDecision{.send = true, .warn = false, .window_bytes = window_bytes_};
}

void BandwidthGuard::reset() {
  samples_.clear();
  window_bytes_ = 0;
  warned_ = false;
}

}  // namespace contourtty
