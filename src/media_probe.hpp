#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>

namespace contourtty {

struct MediaProbeInfo {
  std::filesystem::path input;
  int video_stream_index = -1;
  std::string codec;
  int width = 0;
  int height = 0;
  std::string pixel_format;
  std::optional<int64_t> duration_us;
  std::optional<double> average_fps;
};

MediaProbeInfo probeMedia(const std::filesystem::path& input);
std::string formatMediaProbeInfo(const MediaProbeInfo& info);

}  // namespace contourtty
