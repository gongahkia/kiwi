#pragma once

#include <cstdint>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <vector>

namespace strok {

struct AudioDecodeOptions {
  int sample_rate = 48000;
  int channels = 2;
};

struct DecodedAudio {
  int sample_rate = 0;
  int channels = 0;
  int64_t duration_us = 0;
  int64_t decoded_frames = 0;
  std::vector<float> samples;
};

class NoAudioStreamError : public std::runtime_error {
 public:
  explicit NoAudioStreamError(const std::string& message) : std::runtime_error(message) {}
};

DecodedAudio decodeAudioFile(const std::filesystem::path& input, const AudioDecodeOptions& options = {});

}  // namespace strok
