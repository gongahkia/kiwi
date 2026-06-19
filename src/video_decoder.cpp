#include "video_decoder.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

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

struct AvFrameDeleter {
  void operator()(AVFrame* frame) const noexcept {
    av_frame_free(&frame);
  }
};

using AvFramePtr = std::unique_ptr<AVFrame, AvFrameDeleter>;

struct SwsContextDeleter {
  void operator()(SwsContext* context) const noexcept {
    sws_freeContext(context);
  }
};

using SwsContextPtr = std::unique_ptr<SwsContext, SwsContextDeleter>;

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

std::optional<double> rationalToDouble(AVRational rational) {
  if (rational.num == 0 || rational.den == 0) {
    return std::nullopt;
  }
  return av_q2d(rational);
}

int64_t framePtsUs(const AVFrame* frame, AVRational time_base, int64_t frame_index, std::optional<double> average_fps) {
  int64_t pts = frame->best_effort_timestamp;
  if (pts == AV_NOPTS_VALUE) {
    pts = frame->pts;
  }
  if (pts != AV_NOPTS_VALUE) {
    return static_cast<int64_t>(std::llround(static_cast<double>(pts) * av_q2d(time_base) * 1000000.0));
  }
  if (average_fps.has_value() && *average_fps > 0.0) {
    return static_cast<int64_t>(std::llround(static_cast<double>(frame_index) * 1000000.0 / *average_fps));
  }
  return frame_index * 33333;
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

Frame makeOwnedFrame(const AVFrame* frame, SwsContext** context, std::vector<uint8_t>* scratch, AVRational time_base, int64_t frame_index, std::optional<double> average_fps) {
  const auto format = static_cast<AVPixelFormat>(frame->format);
  if (frame->width <= 0 || frame->height <= 0 || format == AV_PIX_FMT_NONE) {
    throw std::runtime_error("decoded frame has invalid geometry or pixel format");
  }
  SwsContext* converted_context = sws_getCachedContext(
    *context,
    frame->width,
    frame->height,
    format,
    frame->width,
    frame->height,
    AV_PIX_FMT_RGB24,
    SWS_BILINEAR,
    nullptr,
    nullptr,
    nullptr);
  if (converted_context == nullptr) {
    throw std::runtime_error("failed to create RGB24 scaler");
  }
  *context = converted_context;

  scratch->assign(static_cast<std::size_t>(frame->width) * static_cast<std::size_t>(frame->height) * 3, 0);
  uint8_t* dst_data[4] {scratch->data(), nullptr, nullptr, nullptr};
  int dst_linesize[4] {frame->width * 3, 0, 0, 0};
  const int scaled = sws_scale(*context, frame->data, frame->linesize, 0, frame->height, dst_data, dst_linesize);
  if (scaled != frame->height) {
    throw std::runtime_error("failed to convert frame to RGB24");
  }

  Frame owned;
  owned.w = frame->width;
  owned.h = frame->height;
  owned.rgb = *scratch;
  owned.pts_us = framePtsUs(frame, time_base, frame_index, average_fps);
  return owned;
}

}  // namespace

struct VideoDecoder::Impl {
  explicit Impl(const std::filesystem::path& media) {
    av_log_set_level(AV_LOG_QUIET);
    const std::string input_string = media.string();
    if (!looksRemote(input_string)) {
      std::error_code stat_error;
      if (!std::filesystem::exists(media, stat_error)) {
        throw std::runtime_error("missing file: " + input_string);
      }
      if (!std::filesystem::is_regular_file(media, stat_error)) {
        throw std::runtime_error("not a regular file: " + input_string);
      }
      if (std::filesystem::file_size(media, stat_error) == 0 && !stat_error) {
        throw std::runtime_error("empty file: " + input_string);
      }
    }

    AVFormatContext* raw_context = nullptr;
    int result = avformat_open_input(&raw_context, input_string.c_str(), nullptr, nullptr);
    if (result < 0) {
      throw std::runtime_error("could not open media: " + input_string + ": " + ffmpegError(result));
    }
    format_context.reset(raw_context);

    result = avformat_find_stream_info(format_context.get(), nullptr);
    if (result < 0) {
      throw std::runtime_error("could not read stream info: " + input_string + ": " + ffmpegError(result));
    }

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

    stream = format_context->streams[video_stream_index];
    codec_context = openVideoDecoder(stream->codecpar);
    average_fps = rationalToDouble(stream->avg_frame_rate);
    packet.reset(av_packet_alloc());
    frame.reset(av_frame_alloc());
    if (packet == nullptr || frame == nullptr) {
      throw std::runtime_error("failed to allocate video packet/frame");
    }
  }

  ~Impl() {
    sws_freeContext(sws_context);
  }

  std::optional<Frame> receiveFrame() {
    while (true) {
      const int result = avcodec_receive_frame(codec_context.get(), frame.get());
      if (result == 0) {
        Frame owned = makeOwnedFrame(frame.get(), &sws_context, &rgb_scratch, stream->time_base, frame_index, average_fps);
        ++frame_index;
        av_frame_unref(frame.get());
        return owned;
      }
      if (result == AVERROR(EAGAIN)) {
        return std::nullopt;
      }
      if (result == AVERROR_EOF) {
        eof = true;
        return std::nullopt;
      }
      throw std::runtime_error("failed to receive decoded frame: " + ffmpegError(result));
    }
  }

  std::optional<Frame> nextFrame() {
    while (true) {
      if (auto decoded = receiveFrame()) {
        return decoded;
      }
      if (eof) {
        return std::nullopt;
      }
      const int read_result = av_read_frame(format_context.get(), packet.get());
      if (read_result == AVERROR_EOF) {
        const int drain_result = avcodec_send_packet(codec_context.get(), nullptr);
        if (drain_result < 0 && drain_result != AVERROR_EOF) {
          throw std::runtime_error("failed to drain decoder: " + ffmpegError(drain_result));
        }
        continue;
      }
      if (read_result < 0) {
        throw std::runtime_error("failed to read packet: " + ffmpegError(read_result));
      }
      if (packet->stream_index == video_stream_index) {
        int send_result = avcodec_send_packet(codec_context.get(), packet.get());
        std::optional<Frame> decoded_after_eagain;
        if (send_result == AVERROR(EAGAIN)) {
          decoded_after_eagain = receiveFrame();
          send_result = avcodec_send_packet(codec_context.get(), packet.get());
        }
        if (send_result < 0) {
          av_packet_unref(packet.get());
          throw std::runtime_error("failed to send packet to decoder: " + ffmpegError(send_result));
        }
        if (decoded_after_eagain.has_value()) {
          av_packet_unref(packet.get());
          return decoded_after_eagain;
        }
      }
      av_packet_unref(packet.get());
    }
  }

  void seekToUs(int64_t position_us) {
    const int64_t clamped_us = std::max<int64_t>(0, position_us);
    const int64_t timestamp = av_rescale_q(clamped_us, AVRational{1, 1000000}, stream->time_base);
    const int result = av_seek_frame(format_context.get(), video_stream_index, timestamp, AVSEEK_FLAG_BACKWARD);
    if (result < 0) {
      throw std::runtime_error("failed to seek video: " + ffmpegError(result));
    }
    avcodec_flush_buffers(codec_context.get());
    eof = false;
    frame_index = average_fps.has_value() && *average_fps > 0.0
                    ? static_cast<int64_t>(std::llround(static_cast<double>(clamped_us) * *average_fps / 1000000.0))
                    : 0;
  }

  FormatContextPtr format_context;
  CodecContextPtr codec_context;
  PacketPtr packet;
  AvFramePtr frame;
  const AVStream* stream = nullptr;
  int video_stream_index = -1;
  std::optional<double> average_fps;
  int64_t frame_index = 0;
  bool eof = false;
  SwsContext* sws_context = nullptr;
  std::vector<uint8_t> rgb_scratch;
};

VideoDecoder::VideoDecoder(const std::filesystem::path& input) : impl_(std::make_unique<Impl>(input)) {}

VideoDecoder::VideoDecoder(VideoDecoder&&) noexcept = default;

VideoDecoder& VideoDecoder::operator=(VideoDecoder&&) noexcept = default;

VideoDecoder::~VideoDecoder() = default;

std::optional<Frame> VideoDecoder::nextFrame() {
  return impl_->nextFrame();
}

void VideoDecoder::seekToUs(int64_t position_us) {
  impl_->seekToUs(position_us);
}

}  // namespace contourtty
