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
  int64_t decoded_frames = 0;
  int64_t converted_rgb_frames = 0;
  int64_t owned_frames = 0;
  int working_width = 0;
  int working_height = 0;
  std::optional<std::filesystem::path> dumped_png;
};

struct MediaProbeOptions {
  std::optional<int64_t> dump_frame_index;
  std::optional<std::filesystem::path> dump_png;
  std::optional<int> target_cols;
  std::optional<int> target_rows;
  double cell_aspect = 0.5;
};

MediaProbeInfo probeMedia(const std::filesystem::path& input, const MediaProbeOptions& options = {});
std::string formatMediaProbeInfo(const MediaProbeInfo& info);

}  // namespace contourtty
