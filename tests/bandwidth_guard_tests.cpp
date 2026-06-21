#include "bandwidth_guard.hpp"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <stdexcept>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  using clock = std::chrono::steady_clock;
  const auto start = clock::time_point{};

  {
    contourtty::BandwidthGuard guard(0.00001);
    const auto first = guard.recordFrame(6, start);
    expect(first.send, "first frame under cap sends");
    expect(first.window_bytes == 6, "first frame counted");

    const auto second = guard.recordFrame(6, start + std::chrono::milliseconds(100));
    expect(!second.send, "over cap frame drops");
    expect(second.warn, "first drop warns");
    expect(second.window_bytes == 6, "dropped frame not counted");

    const auto third = guard.recordFrame(6, start + std::chrono::milliseconds(200));
    expect(!third.send, "second over cap frame drops");
    expect(!third.warn, "second drop does not warn again");

    const auto fourth = guard.recordFrame(6, start + std::chrono::milliseconds(1000));
    expect(fourth.send, "window expiry allows frame");
    expect(fourth.window_bytes == 6, "expired bytes pruned");
  }

  {
    contourtty::BandwidthGuard guard(0.00001);
    (void)guard.recordFrame(11, start);
    guard.reset();
    const auto after_reset = guard.recordFrame(6, start);
    expect(after_reset.send, "reset clears bytes");
    expect(!after_reset.warn, "reset clears warning state");
  }

  {
    bool threw = false;
    try {
      contourtty::BandwidthGuard guard(0.0);
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "zero bandwidth cap rejected");
  }
}
