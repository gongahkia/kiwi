#include "live_presentation_pacer.hpp"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <optional>

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
    strok::LivePresentationPacer pacer(std::nullopt, std::nullopt, 30.0);
    expect(pacer.ready(start), "first presentation is ready");
    const strok::LivePresentationTiming timing = pacer.recordWrite(std::chrono::milliseconds(50), start);
    expect(timing.interval == std::chrono::milliseconds(50), "slow write sets effective interval");
    expect(timing.terminal_overrun, "slow write records terminal overrun");
    expect(!pacer.ready(start + std::chrono::milliseconds(49)), "slow write defers next presentation");
    expect(pacer.ready(start + std::chrono::milliseconds(50)), "next presentation resumes after write interval");
    expect(pacer.isLate(start, start + std::chrono::milliseconds(34)), "frame older than source interval is late");
  }

  {
    strok::LivePresentationPacer pacer(60.0, 15.0, 30.0);
    const strok::LivePresentationTiming timing = pacer.recordWrite(std::chrono::milliseconds(10), start);
    expect(timing.interval == std::chrono::microseconds(66667), "max fps remains a presentation cap");
    expect(!timing.terminal_overrun, "short write is not an overrun");
    expect(!pacer.ready(start + std::chrono::microseconds(66666)), "max fps defers next presentation");
    expect(pacer.ready(start + std::chrono::microseconds(66667)), "max fps interval permits next presentation");
  }

  {
    strok::LivePresentationPacer pacer(std::nullopt, std::nullopt, 5.0);
    expect(!pacer.isLate(start, start + std::chrono::milliseconds(50)), "late drop budget is inclusive at 50ms");
    expect(pacer.isLate(start, start + std::chrono::milliseconds(51)), "late drop budget is capped at 50ms");
  }
}
