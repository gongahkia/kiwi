#pragma once

#include <cstdint>
#include <memory>
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

class PcmPlayer {
 public:
  PcmPlayer(std::span<const float> samples, const PcmPlaybackOptions& options);
  PcmPlayer(const PcmPlayer&) = delete;
  PcmPlayer& operator=(const PcmPlayer&) = delete;
  PcmPlayer(PcmPlayer&&) noexcept;
  PcmPlayer& operator=(PcmPlayer&&) noexcept;
  ~PcmPlayer();

  void start();
  void setPaused(bool paused) noexcept;
  bool paused() const noexcept;
  void seekToUs(int64_t position_us) noexcept;
  int64_t masterClockUs() const noexcept;
  int64_t durationUs() const noexcept;
  bool complete() const noexcept;
  PcmPlaybackResult waitUntilComplete();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

PcmPlaybackResult playPcm(std::span<const float> samples, const PcmPlaybackOptions& options);
SineSmokeResult playSineSmoke(const SineSmokeOptions& options = {});

}  // namespace contourtty
