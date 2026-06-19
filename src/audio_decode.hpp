#pragma once

#include <cstdint>
#include <filesystem>
#include <vector>

namespace contourtty {

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

DecodedAudio decodeAudioFile(const std::filesystem::path& input, const AudioDecodeOptions& options = {});

}  // namespace contourtty
