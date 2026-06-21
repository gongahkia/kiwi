#include "captions.hpp"

#include <algorithm>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace contourtty {

std::string summariseFrameCaption(const Frame& frame) {
  if (frame.w <= 0 || frame.h <= 0 || frame.rgb.size() != static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h) * 3U) {
    throw std::invalid_argument("invalid frame for caption summary");
  }
  double luma_sum = 0.0;
  double red_sum = 0.0;
  double green_sum = 0.0;
  double blue_sum = 0.0;
  double min_luma = 255.0;
  double max_luma = 0.0;
  for (std::size_t index = 0; index < frame.rgb.size(); index += 3U) {
    const double red = frame.rgb[index];
    const double green = frame.rgb[index + 1U];
    const double blue = frame.rgb[index + 2U];
    const double luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    red_sum += red;
    green_sum += green;
    blue_sum += blue;
    luma_sum += luma;
    min_luma = std::min(min_luma, luma);
    max_luma = std::max(max_luma, luma);
  }
  const double pixels = static_cast<double>(frame.w) * static_cast<double>(frame.h);
  const double avg_luma = luma_sum / pixels;
  const std::string brightness = avg_luma < 64.0 ? "dark" : (avg_luma > 192.0 ? "bright" : "mid-tone");
  const std::string contrast = (max_luma - min_luma) > 96.0 ? "high contrast" : "low contrast";
  std::string dominant = "balanced color";
  if (red_sum > green_sum * 1.15 && red_sum > blue_sum * 1.15) {
    dominant = "red dominant";
  } else if (green_sum > red_sum * 1.15 && green_sum > blue_sum * 1.15) {
    dominant = "green dominant";
  } else if (blue_sum > red_sum * 1.15 && blue_sum > green_sum * 1.15) {
    dominant = "blue dominant";
  }
  return brightness + ", " + contrast + ", " + dominant;
}

std::string formatSrtTimestamp(int64_t pts_us) {
  if (pts_us < 0) {
    pts_us = 0;
  }
  const int64_t total_ms = pts_us / 1000;
  const int64_t ms = total_ms % 1000;
  const int64_t total_seconds = total_ms / 1000;
  const int64_t seconds = total_seconds % 60;
  const int64_t total_minutes = total_seconds / 60;
  const int64_t minutes = total_minutes % 60;
  const int64_t hours = total_minutes / 60;
  std::ostringstream out;
  out << std::setfill('0') << std::setw(2) << hours << ':'
      << std::setw(2) << minutes << ':'
      << std::setw(2) << seconds << ','
      << std::setw(3) << ms;
  return out.str();
}

std::string formatSrtCue(int index, int64_t start_us, int64_t end_us, const std::string& text) {
  std::ostringstream out;
  out << index << '\n'
      << formatSrtTimestamp(start_us) << " --> " << formatSrtTimestamp(end_us) << '\n'
      << text << "\n\n";
  return out.str();
}

}  // namespace contourtty
