#pragma once

#include <cstdint>

namespace contourtty {

struct SineSmokeOptions {
  double seconds = 0.5;
  double frequency_hz = 440.0;
  uint32_t sample_rate = 48000;
  uint32_t channels = 2;
};

struct SineSmokeResult {
  uint64_t frames_generated = 0;
  uint32_t sample_rate = 0;
  uint32_t channels = 0;
};

SineSmokeResult playSineSmoke(const SineSmokeOptions& options = {});

}  // namespace contourtty
