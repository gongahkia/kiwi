#include "media_probe.hpp"

#include <array>
#include <filesystem>
#include <iomanip>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>

extern "C" {
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/pixdesc.h>
}

namespace contourtty {
namespace {

struct FormatContextDeleter {
  void operator()(AVFormatContext* context) const noexcept {
    if (context == nullptr) {
      return;
    }
    AVFormatContext* owned = context;
    avformat_close_input(&owned);
  }
};

using FormatContextPtr = std::unique_ptr<AVFormatContext, FormatContextDeleter>;

std::string ffmpegError(int error_code) {
  std::array<char, AV_ERROR_MAX_STRING_SIZE> buffer {};
  if (av_strerror(error_code, buffer.data(), buffer.size()) < 0) {
    return "unknown ffmpeg error";
  }
  return buffer.data();
}

bool looksRemote(std::string_view input) {
  return input.find("://") != std::string_view::npos;
}

std::string pixelFormatName(int format) {
  if (format < 0) {
    return "unknown";
  }
  const char* name = av_get_pix_fmt_name(static_cast<AVPixelFormat>(format));
  return name == nullptr ? "unknown" : name;
}

std::optional<double> rationalToDouble(AVRational rational) {
  if (rational.num == 0 || rational.den == 0) {
    return std::nullopt;
  }
  return av_q2d(rational);
}

}  // namespace

MediaProbeInfo probeMedia(const std::filesystem::path& input) {
  const std::string input_string = input.string();
  if (!looksRemote(input_string)) {
    std::error_code stat_error;
    if (!std::filesystem::exists(input, stat_error)) {
      throw std::runtime_error("missing file: " + input_string);
    }
    if (!std::filesystem::is_regular_file(input, stat_error)) {
      throw std::runtime_error("not a regular file: " + input_string);
    }
    if (std::filesystem::file_size(input, stat_error) == 0 && !stat_error) {
      throw std::runtime_error("empty file: " + input_string);
    }
  }

  AVFormatContext* raw_context = nullptr;
  int result = avformat_open_input(&raw_context, input_string.c_str(), nullptr, nullptr);
  if (result < 0) {
    throw std::runtime_error("could not open media: " + input_string + ": " + ffmpegError(result));
  }
  FormatContextPtr format_context(raw_context);

  result = avformat_find_stream_info(format_context.get(), nullptr);
  if (result < 0) {
    throw std::runtime_error("could not read stream info: " + input_string + ": " + ffmpegError(result));
  }

  int video_stream_index = -1;
  for (unsigned int i = 0; i < format_context->nb_streams; ++i) {
    const AVStream* stream = format_context->streams[i];
    if (stream != nullptr && stream->codecpar != nullptr &&
        stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
      video_stream_index = static_cast<int>(i);
      break;
    }
  }

  if (video_stream_index < 0) {
    throw std::runtime_error("no video stream found: " + input_string);
  }

  const AVStream* video_stream = format_context->streams[video_stream_index];
  const AVCodecParameters* codec_parameters = video_stream->codecpar;

  MediaProbeInfo info;
  info.input = input;
  info.video_stream_index = video_stream_index;
  info.codec = avcodec_get_name(codec_parameters->codec_id);
  info.width = codec_parameters->width;
  info.height = codec_parameters->height;
  info.pixel_format = pixelFormatName(codec_parameters->format);
  if (format_context->duration != AV_NOPTS_VALUE) {
    info.duration_us = format_context->duration;
  }
  info.average_fps = rationalToDouble(video_stream->avg_frame_rate);
  return info;
}

std::string formatMediaProbeInfo(const MediaProbeInfo& info) {
  std::ostringstream out;
  out << "input: " << info.input.string() << '\n'
      << "video_stream: " << info.video_stream_index << '\n'
      << "codec: " << info.codec << '\n'
      << "resolution: " << info.width << 'x' << info.height << '\n'
      << "pix_fmt: " << info.pixel_format << '\n';

  out << "duration: ";
  if (info.duration_us.has_value()) {
    out << std::fixed << std::setprecision(3) << static_cast<double>(*info.duration_us) / 1000000.0 << "s";
  } else {
    out << "unknown";
  }
  out << '\n';

  out << "avg_fps: ";
  if (info.average_fps.has_value()) {
    out << std::fixed << std::setprecision(3) << *info.average_fps;
  } else {
    out << "unknown";
  }
  out << '\n';
  return out.str();
}

}  // namespace contourtty
