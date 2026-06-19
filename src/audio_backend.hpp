#pragma once

#include <cstdint>
#include <span>

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

struct PcmPlaybackOptions {
  uint32_t sample_rate = 48000;
  uint32_t channels = 2;
};

struct PcmPlaybackResult {
  uint64_t frames_played = 0;
  uint64_t trailing_silence_frames = 0;
};

PcmPlaybackResult playPcm(std::span<const float> samples, const PcmPlaybackOptions& options);
SineSmokeResult playSineSmoke(const SineSmokeOptions& options = {});

}  // namespace contourtty
