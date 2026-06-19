#include "media_probe.hpp"

#include <array>
#include <filesystem>
#include <iomanip>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>

extern "C" {
#include <libavcodec/avcodec.h>
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

struct CodecContextDeleter {
  void operator()(AVCodecContext* context) const noexcept {
    avcodec_free_context(&context);
  }
};

using CodecContextPtr = std::unique_ptr<AVCodecContext, CodecContextDeleter>;

struct PacketDeleter {
  void operator()(AVPacket* packet) const noexcept {
    av_packet_free(&packet);
  }
};

using PacketPtr = std::unique_ptr<AVPacket, PacketDeleter>;

struct FrameDeleter {
  void operator()(AVFrame* frame) const noexcept {
    av_frame_free(&frame);
  }
};

using FramePtr = std::unique_ptr<AVFrame, FrameDeleter>;

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

CodecContextPtr openVideoDecoder(const AVCodecParameters* codec_parameters) {
  const AVCodec* decoder = avcodec_find_decoder(codec_parameters->codec_id);
  if (decoder == nullptr) {
    throw std::runtime_error("unsupported codec: " + std::string(avcodec_get_name(codec_parameters->codec_id)));
  }

  CodecContextPtr codec_context(avcodec_alloc_context3(decoder));
  if (codec_context == nullptr) {
    throw std::runtime_error("failed to allocate decoder context");
  }

  int result = avcodec_parameters_to_context(codec_context.get(), codec_parameters);
  if (result < 0) {
    throw std::runtime_error("failed to copy decoder parameters: " + ffmpegError(result));
  }

  codec_context->thread_count = 0;
  result = avcodec_open2(codec_context.get(), decoder, nullptr);
  if (result < 0) {
    throw std::runtime_error("failed to open decoder: " + std::string(decoder->name) + ": " + ffmpegError(result));
  }

  return codec_context;
}

int64_t receiveDecodedFrames(AVCodecContext* codec_context, AVFrame* frame) {
  int64_t decoded = 0;
  while (true) {
    const int result = avcodec_receive_frame(codec_context, frame);
    if (result == 0) {
      ++decoded;
      av_frame_unref(frame);
      continue;
    }
    if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
      return decoded;
    }
    throw std::runtime_error("failed to receive decoded frame: " + ffmpegError(result));
  }
}

int64_t countDecodedFrames(AVFormatContext* format_context, AVCodecContext* codec_context, int video_stream_index) {
  PacketPtr packet(av_packet_alloc());
  if (packet == nullptr) {
    throw std::runtime_error("failed to allocate packet");
  }
  FramePtr frame(av_frame_alloc());
  if (frame == nullptr) {
    throw std::runtime_error("failed to allocate frame");
  }

  int64_t decoded_frames = 0;
  while (true) {
    const int read_result = av_read_frame(format_context, packet.get());
    if (read_result == AVERROR_EOF) {
      break;
    }
    if (read_result < 0) {
      throw std::runtime_error("failed to read packet: " + ffmpegError(read_result));
    }

    if (packet->stream_index == video_stream_index) {
      int send_result = avcodec_send_packet(codec_context, packet.get());
      if (send_result == AVERROR(EAGAIN)) {
        decoded_frames += receiveDecodedFrames(codec_context, frame.get());
        send_result = avcodec_send_packet(codec_context, packet.get());
      }
      if (send_result < 0) {
        av_packet_unref(packet.get());
        throw std::runtime_error("failed to send packet to decoder: " + ffmpegError(send_result));
      }
      decoded_frames += receiveDecodedFrames(codec_context, frame.get());
    }

    av_packet_unref(packet.get());
  }

  const int drain_result = avcodec_send_packet(codec_context, nullptr);
  if (drain_result < 0 && drain_result != AVERROR_EOF) {
    throw std::runtime_error("failed to drain decoder: " + ffmpegError(drain_result));
  }
  decoded_frames += receiveDecodedFrames(codec_context, frame.get());
  return decoded_frames;
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
  const auto decoder_context = openVideoDecoder(codec_parameters);
  const int64_t decoded_frames = countDecodedFrames(format_context.get(), decoder_context.get(), video_stream_index);

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
  info.decoded_frames = decoded_frames;
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
  out << '\n'
      << "decoded_frames: " << info.decoded_frames << '\n';
  return out.str();
}

}  // namespace contourtty
