#include "media_probe.hpp"

#include "png_writer.hpp"

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
#include <libswscale/swscale.h>
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

struct SwsContextDeleter {
  void operator()(SwsContext* context) const noexcept {
    sws_freeContext(context);
  }
};

using SwsContextPtr = std::unique_ptr<SwsContext, SwsContextDeleter>;

class RgbConverter {
 public:
  std::span<const uint8_t> convert(const AVFrame* frame) {
    const auto format = static_cast<AVPixelFormat>(frame->format);
    if (frame->width <= 0 || frame->height <= 0 || format == AV_PIX_FMT_NONE) {
      throw std::runtime_error("decoded frame has invalid geometry or pixel format");
    }
    if (context_ == nullptr || width_ != frame->width || height_ != frame->height || format_ != format) {
      reset(frame->width, frame->height, format);
    }
    uint8_t* dst_data[4] {rgb_.data(), nullptr, nullptr, nullptr};
    int dst_linesize[4] {width_ * 3, 0, 0, 0};
    const int scaled = sws_scale(context_.get(), frame->data, frame->linesize, 0, height_, dst_data, dst_linesize);
    if (scaled != height_) {
      throw std::runtime_error("failed to convert frame to RGB24");
    }
    return rgb_;
  }

  int width() const noexcept {
    return width_;
  }

  int height() const noexcept {
    return height_;
  }

 private:
  void reset(int width, int height, AVPixelFormat format) {
    SwsContext* raw_context = sws_getContext(width, height, format, width, height, AV_PIX_FMT_RGB24, SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (raw_context == nullptr) {
      throw std::runtime_error("failed to create RGB24 scaler");
    }
    context_.reset(raw_context);
    width_ = width;
    height_ = height;
    format_ = format;
    rgb_.assign(static_cast<std::size_t>(width_) * static_cast<std::size_t>(height_) * 3, 0);
  }

  SwsContextPtr context_;
  int width_ = 0;
  int height_ = 0;
  AVPixelFormat format_ = AV_PIX_FMT_NONE;
  std::vector<uint8_t> rgb_;
};

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

struct DecodeStats {
  int64_t decoded_frames = 0;
  int64_t converted_rgb_frames = 0;
  std::optional<std::filesystem::path> dumped_png;
};

DecodeStats receiveDecodedFrames(AVCodecContext* codec_context, AVFrame* frame, RgbConverter* converter, int64_t* frame_index, const MediaProbeOptions& options) {
  DecodeStats stats;
  while (true) {
    const int result = avcodec_receive_frame(codec_context, frame);
    if (result == 0) {
      ++stats.decoded_frames;
      if (converter != nullptr) {
        const auto rgb = converter->convert(frame);
        ++stats.converted_rgb_frames;
        if (options.dump_png.has_value() && options.dump_frame_index.has_value() &&
            *frame_index == *options.dump_frame_index) {
          writePngRgb24(*options.dump_png, converter->width(), converter->height(), rgb);
          stats.dumped_png = *options.dump_png;
        }
      }
      ++(*frame_index);
      av_frame_unref(frame);
      continue;
    }
    if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
      return stats;
    }
    throw std::runtime_error("failed to receive decoded frame: " + ffmpegError(result));
  }
}

void mergeStats(DecodeStats* target, const DecodeStats& update) {
  target->decoded_frames += update.decoded_frames;
  target->converted_rgb_frames += update.converted_rgb_frames;
  if (update.dumped_png.has_value()) {
    target->dumped_png = update.dumped_png;
  }
}

DecodeStats decodeFrames(AVFormatContext* format_context, AVCodecContext* codec_context, int video_stream_index, const MediaProbeOptions& options) {
  PacketPtr packet(av_packet_alloc());
  if (packet == nullptr) {
    throw std::runtime_error("failed to allocate packet");
  }
  FramePtr frame(av_frame_alloc());
  if (frame == nullptr) {
    throw std::runtime_error("failed to allocate frame");
  }

  DecodeStats stats;
  RgbConverter converter;
  int64_t frame_index = 0;
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
        mergeStats(&stats, receiveDecodedFrames(codec_context, frame.get(), &converter, &frame_index, options));
        send_result = avcodec_send_packet(codec_context, packet.get());
      }
      if (send_result < 0) {
        av_packet_unref(packet.get());
        throw std::runtime_error("failed to send packet to decoder: " + ffmpegError(send_result));
      }
      mergeStats(&stats, receiveDecodedFrames(codec_context, frame.get(), &converter, &frame_index, options));
    }

    av_packet_unref(packet.get());
  }

  const int drain_result = avcodec_send_packet(codec_context, nullptr);
  if (drain_result < 0 && drain_result != AVERROR_EOF) {
    throw std::runtime_error("failed to drain decoder: " + ffmpegError(drain_result));
  }
  mergeStats(&stats, receiveDecodedFrames(codec_context, frame.get(), &converter, &frame_index, options));
  if (options.dump_png.has_value() && !stats.dumped_png.has_value()) {
    throw std::runtime_error("requested frame was not decoded: " + std::to_string(*options.dump_frame_index));
  }
  return stats;
}

}  // namespace

MediaProbeInfo probeMedia(const std::filesystem::path& input, const MediaProbeOptions& options) {
  if (options.dump_png.has_value() != options.dump_frame_index.has_value()) {
    throw std::runtime_error("--dump-frame and --dump-png must be used together");
  }

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
  const DecodeStats decode_stats = decodeFrames(format_context.get(), decoder_context.get(), video_stream_index, options);

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
  info.decoded_frames = decode_stats.decoded_frames;
  info.converted_rgb_frames = decode_stats.converted_rgb_frames;
  info.dumped_png = decode_stats.dumped_png;
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
      << "decoded_frames: " << info.decoded_frames << '\n'
      << "converted_rgb_frames: " << info.converted_rgb_frames << '\n';
  if (info.dumped_png.has_value()) {
    out << "dumped_png: " << info.dumped_png->string() << '\n';
  }
  return out.str();
}

}  // namespace contourtty
