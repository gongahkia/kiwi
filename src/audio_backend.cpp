#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "audio_backend.hpp"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
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

}  // namespace

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
