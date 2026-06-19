#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "audio_backend.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

namespace contourtty {
namespace {

constexpr double kPi = 3.14159265358979323846;

struct SineState {
  std::atomic<uint64_t> frames_generated = 0;
  uint64_t total_frames = 0;
  double phase = 0.0;
  double phase_step = 0.0;
};

struct PcmState {
  std::span<const float> samples;
  std::atomic<uint64_t> frames_played = 0;
  std::atomic<uint64_t> trailing_silence_frames = 0;
  uint64_t total_frames = 0;
  uint32_t channels = 0;
};

std::string miniaudioError(ma_result result) {
  return std::string(ma_result_description(result)) + " (" + std::to_string(static_cast<int>(result)) + ")";
}

void sineCallback(ma_device* device, void* output, const void*, ma_uint32 frame_count) {
  auto* state = static_cast<SineState*>(device->pUserData);
  auto* out = static_cast<float*>(output);
  const ma_uint32 channels = device->playback.channels;
  uint64_t generated = state->frames_generated.load(std::memory_order_relaxed);

  for (ma_uint32 frame = 0; frame < frame_count; ++frame) {
    float sample = 0.0F;
    if (generated < state->total_frames) {
      sample = static_cast<float>(std::sin(state->phase) * 0.20);
      state->phase += state->phase_step;
      if (state->phase >= 2.0 * kPi) {
        state->phase -= 2.0 * kPi;
      }
      ++generated;
    }
    for (ma_uint32 channel = 0; channel < channels; ++channel) {
      out[static_cast<std::size_t>(frame) * channels + channel] = sample;
    }
  }

  state->frames_generated.store(generated, std::memory_order_release);
}

void pcmCallback(ma_device* device, void* output, const void*, ma_uint32 frame_count) {
  auto* state = static_cast<PcmState*>(device->pUserData);
  auto* out = static_cast<float*>(output);
  uint64_t frame_cursor = state->frames_played.load(std::memory_order_relaxed);
  uint64_t trailing_silence = state->trailing_silence_frames.load(std::memory_order_relaxed);
  const ma_uint32 output_channels = device->playback.channels;

  for (ma_uint32 frame = 0; frame < frame_count; ++frame) {
    if (frame_cursor < state->total_frames) {
      const std::size_t input_offset = static_cast<std::size_t>(frame_cursor) * state->channels;
      for (ma_uint32 channel = 0; channel < output_channels; ++channel) {
        out[static_cast<std::size_t>(frame) * output_channels + channel] = state->samples[input_offset + channel];
      }
      ++frame_cursor;
    } else {
      for (ma_uint32 channel = 0; channel < output_channels; ++channel) {
        out[static_cast<std::size_t>(frame) * output_channels + channel] = 0.0F;
      }
      ++trailing_silence;
    }
  }

  state->frames_played.store(frame_cursor, std::memory_order_release);
  state->trailing_silence_frames.store(trailing_silence, std::memory_order_release);
}

}  // namespace

struct PcmPlayer::Impl {
  explicit Impl(const PcmPlaybackOptions& playback_options) : options(playback_options) {}

  ~Impl() {
    if (initialized) {
      ma_device_uninit(&device);
    }
  }

  PcmPlaybackOptions options;
  PcmState state;
  ma_device device {};
  bool initialized = false;
  bool started = false;
};

PcmPlayer::PcmPlayer(std::span<const float> samples, const PcmPlaybackOptions& options)
    : impl_(std::make_unique<Impl>(options)) {
  if (options.sample_rate == 0) {
    throw std::runtime_error("PCM playback sample rate must be positive");
  }
  if (options.channels == 0) {
    throw std::runtime_error("PCM playback channel count must be positive");
  }
  if (samples.empty()) {
    throw std::runtime_error("PCM playback requires samples");
  }
  if (samples.size() % options.channels != 0) {
    throw std::runtime_error("PCM sample count is not divisible by channel count");
  }

  impl_->state.samples = samples;
  impl_->state.channels = options.channels;
  impl_->state.total_frames = static_cast<uint64_t>(samples.size() / options.channels);

  ma_device_config config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32;
  config.playback.channels = options.channels;
  config.sampleRate = options.sample_rate;
  config.dataCallback = pcmCallback;
  config.pUserData = &impl_->state;

  ma_result result = ma_device_init(nullptr, &config, &impl_->device);
  if (result != MA_SUCCESS) {
    throw std::runtime_error("failed to initialize audio playback device: " + miniaudioError(result));
  }
  impl_->initialized = true;
}

PcmPlayer::PcmPlayer(PcmPlayer&&) noexcept = default;

PcmPlayer& PcmPlayer::operator=(PcmPlayer&&) noexcept = default;

PcmPlayer::~PcmPlayer() = default;

void PcmPlayer::start() {
  ma_result result = ma_device_start(&impl_->device);
  if (result != MA_SUCCESS) {
    throw std::runtime_error("failed to start audio playback device: " + miniaudioError(result));
  }
  impl_->started = true;
}

int64_t PcmPlayer::masterClockUs() const noexcept {
  const uint64_t frames = std::min(
    impl_->state.frames_played.load(std::memory_order_acquire),
    impl_->state.total_frames);
  return static_cast<int64_t>(static_cast<double>(frames) * 1000000.0 / static_cast<double>(impl_->options.sample_rate));
}

bool PcmPlayer::complete() const noexcept {
  return impl_->state.frames_played.load(std::memory_order_acquire) >= impl_->state.total_frames;
}

PcmPlaybackResult PcmPlayer::waitUntilComplete() {
  const auto timeout = std::chrono::steady_clock::now() +
                       std::chrono::duration_cast<std::chrono::steady_clock::duration>(
                         std::chrono::duration<double>(static_cast<double>(impl_->state.total_frames) / static_cast<double>(impl_->options.sample_rate))) +
                       std::chrono::seconds(5);
  while (!complete() && std::chrono::steady_clock::now() < timeout) {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(100));

  return PcmPlaybackResult{
    .frames_played = impl_->state.frames_played.load(std::memory_order_acquire),
    .trailing_silence_frames = impl_->state.trailing_silence_frames.load(std::memory_order_acquire),
  };
}

PcmPlaybackResult playPcm(std::span<const float> samples, const PcmPlaybackOptions& options) {
  PcmPlayer player(samples, options);
  player.start();
  return player.waitUntilComplete();
}

SineSmokeResult playSineSmoke(const SineSmokeOptions& options) {
  if (options.seconds <= 0.0) {
    throw std::runtime_error("sine smoke duration must be positive");
  }
  if (options.frequency_hz <= 0.0) {
    throw std::runtime_error("sine smoke frequency must be positive");
  }
  if (options.sample_rate == 0) {
    throw std::runtime_error("sine smoke sample rate must be positive");
  }
  if (options.channels == 0) {
    throw std::runtime_error("sine smoke channel count must be positive");
  }

  SineState state;
  state.total_frames = static_cast<uint64_t>(std::llround(options.seconds * static_cast<double>(options.sample_rate)));
  state.phase_step = 2.0 * kPi * options.frequency_hz / static_cast<double>(options.sample_rate);

  ma_device_config config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32;
  config.playback.channels = options.channels;
  config.sampleRate = options.sample_rate;
  config.dataCallback = sineCallback;
  config.pUserData = &state;

  ma_device device {};
  ma_result result = ma_device_init(nullptr, &config, &device);
  if (result != MA_SUCCESS) {
    throw std::runtime_error("failed to initialize audio playback device: " + miniaudioError(result));
  }

  result = ma_device_start(&device);
  if (result != MA_SUCCESS) {
    ma_device_uninit(&device);
    throw std::runtime_error("failed to start audio playback device: " + miniaudioError(result));
  }

  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(options.seconds)) +
                        std::chrono::milliseconds(100);
  while (std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }

  ma_device_uninit(&device);
  const uint64_t frames_generated = state.frames_generated.load(std::memory_order_acquire);
  if (frames_generated < state.total_frames) {
    throw std::runtime_error("audio callback did not consume the full sine buffer");
  }

  return SineSmokeResult{
    .frames_generated = frames_generated,
    .sample_rate = options.sample_rate,
    .channels = options.channels,
  };
}

}  // namespace contourtty
