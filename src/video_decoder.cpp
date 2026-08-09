#include "video_decoder.hpp"

#include "media_input.hpp"
#include "terminal.hpp"
#include "worker_count.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavdevice/avdevice.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/pixdesc.h>
#include <libswscale/swscale.h>
}

namespace strok {
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

struct DecoderInterruptState {
  std::atomic<bool> stop_requested = false;
  const std::atomic<bool>* external_stop_requested = nullptr;
  std::atomic<int64_t> deadline_ns = 0;
  std::atomic<bool> timed_out = false;
};

int64_t steadyNowNs() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
           std::chrono::steady_clock::now().time_since_epoch())
    .count();
}

bool decoderStopRequested(const DecoderInterruptState& state) {
  return state.stop_requested.load(std::memory_order_relaxed) ||
         (state.external_stop_requested != nullptr && state.external_stop_requested->load(std::memory_order_relaxed));
}

int interruptIfStopped(void* opaque) {
  auto* state = static_cast<DecoderInterruptState*>(opaque);
  if (shouldQuit() || (state != nullptr && decoderStopRequested(*state))) {
    return 1;
  }
  if (state != nullptr) {
    const int64_t deadline_ns = state->deadline_ns.load(std::memory_order_relaxed);
    if (deadline_ns > 0 && steadyNowNs() >= deadline_ns) {
      state->timed_out.store(true, std::memory_order_relaxed);
      return 1;
    }
  }
  return 0;
}

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

bool isStillImageFormat(std::string_view format_name) {
  constexpr std::array<std::string_view, 8> formats {
    "png_pipe",
    "jpeg_pipe",
    "webp_pipe",
    "bmp_pipe",
    "tiff_pipe",
    "image2",
    "mjpeg",
    "singlejpeg",
  };
  return std::find(formats.begin(), formats.end(), format_name) != formats.end();
}

bool isAnimatedImageFormat(std::string_view format_name) {
  return format_name == "gif";
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

  codec_context->thread_count = configuredWorkerLimit().value_or(0);
  result = avcodec_open2(codec_context.get(), decoder, nullptr);
  if (result < 0) {
    throw std::runtime_error("failed to open decoder: " + std::string(decoder->name) + ": " + ffmpegError(result));
  }

  return codec_context;
}

Frame makeOwnedFrame(const AVFrame* frame, SwsContext** context, AVRational time_base, int64_t frame_index, std::optional<double> average_fps) {
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

  Frame owned;
  owned.w = frame->width;
  owned.h = frame->height;
  owned.rgb.assign(static_cast<std::size_t>(frame->width) * static_cast<std::size_t>(frame->height) * 3, 0);
  uint8_t* dst_data[4] {owned.rgb.data(), nullptr, nullptr, nullptr};
  int dst_linesize[4] {frame->width * 3, 0, 0, 0};
  const int scaled = sws_scale(*context, frame->data, frame->linesize, 0, frame->height, dst_data, dst_linesize);
  if (scaled != frame->height) {
    throw std::runtime_error("failed to convert frame to RGB24");
  }

  owned.pts_us = framePtsUs(frame, time_base, frame_index, average_fps);
  return owned;
}

}  // namespace

struct VideoDecoder::Impl {
  explicit Impl(std::filesystem::path media,
                VideoDecoderOptions decoder_options,
                const std::atomic<bool>* external_stop)
      : input(std::move(media)), options(std::move(decoder_options)) {
    interrupt_state.external_stop_requested = external_stop;
    const std::string input_string = input.string();
    const std::optional<CameraInputSpec> camera = cameraInputSpec(input_string);
    if (!camera.has_value() && !looksRemote(input_string)) {
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

    std::string open_input = input_string;
    const AVInputFormat* input_format = nullptr;
    AVDictionary* input_options = nullptr;
    live_input = isLatencySensitiveInput(input_string);
    const std::chrono::milliseconds open_timeout = live_input ? options.input_open_timeout : std::chrono::milliseconds(0);
    if (camera.has_value()) {
      avdevice_register_all();
      input_format = av_find_input_format(camera->format.c_str());
      if (input_format == nullptr) {
        throw std::runtime_error("FFmpeg input device unavailable: " + camera->format);
      }
      open_input = camera->device;
      av_dict_set(&input_options, "video_size", "640x480", 0);
      av_dict_set(&input_options, "framerate", "30", 0);
      if (camera->format == "avfoundation") {
        av_dict_set(&input_options, "pixel_format", "nv12", 0);
      }
      av_dict_set(&input_options, "fflags", "nobuffer", 0);
      av_dict_set(&input_options, "flags", "low_delay", 0);
    } else if (isRtspInput(input_string)) {
      av_dict_set(&input_options, "fflags", "nobuffer", 0);
      av_dict_set(&input_options, "flags", "low_delay", 0);
      if (options.read_timeout.count() > 0) {
        const std::string timeout_us = std::to_string(options.read_timeout.count() * 1000);
        av_dict_set(&input_options, "timeout", timeout_us.c_str(), 0);
      }
      if (options.rtsp_transport == RtspTransport::Tcp) {
        av_dict_set(&input_options, "rtsp_transport", "tcp", 0);
      } else if (options.rtsp_transport == RtspTransport::Udp) {
        av_dict_set(&input_options, "rtsp_transport", "udp", 0);
      }
    }

    AVFormatContext* raw_context = avformat_alloc_context();
    if (raw_context == nullptr) {
      throw std::runtime_error("failed to allocate media context");
    }
    raw_context->interrupt_callback.callback = interruptIfStopped;
    raw_context->interrupt_callback.opaque = &interrupt_state;
    armIoTimeout(open_timeout);
    int result = avformat_open_input(&raw_context, open_input.c_str(), input_format, &input_options);
    const bool open_timed_out = interrupt_state.timed_out.load(std::memory_order_relaxed);
    disarmIoTimeout();
    av_dict_free(&input_options);
    if (result < 0) {
      AVFormatContext* owned = raw_context;
      avformat_close_input(&owned);
      if (open_timed_out) {
        throw std::runtime_error("timed out opening media after " + std::to_string(open_timeout.count()) + "ms: " + input_string);
      }
      throw std::runtime_error("could not open media: " + input_string + ": " + ffmpegError(result));
    }
    format_context.reset(raw_context);
    if (format_context->iformat != nullptr && format_context->iformat->name != nullptr) {
      const std::string_view format_name = format_context->iformat->name;
      still_image = isStillImageFormat(format_name);
      animated_image = isAnimatedImageFormat(format_name);
    }

    armIoTimeout(open_timeout);
    result = avformat_find_stream_info(format_context.get(), nullptr);
    const bool probe_timed_out = interrupt_state.timed_out.load(std::memory_order_relaxed);
    disarmIoTimeout();
    if (result < 0) {
      if (probe_timed_out) {
        throw std::runtime_error("timed out probing media after " + std::to_string(open_timeout.count()) + "ms: " + input_string);
      }
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

  bool stopRequested() const {
    return decoderStopRequested(interrupt_state);
  }

  void armIoTimeout(std::chrono::milliseconds timeout) {
    interrupt_state.timed_out.store(false, std::memory_order_relaxed);
    if (timeout.count() <= 0) {
      interrupt_state.deadline_ns.store(0, std::memory_order_relaxed);
      return;
    }
    const int64_t timeout_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(timeout).count();
    interrupt_state.deadline_ns.store(steadyNowNs() + timeout_ns, std::memory_order_relaxed);
  }

  void disarmIoTimeout() {
    interrupt_state.deadline_ns.store(0, std::memory_order_relaxed);
  }

  std::optional<Frame> receiveFrame() {
    while (true) {
      const int result = avcodec_receive_frame(codec_context.get(), frame.get());
      if (result == 0) {
        Frame owned = makeOwnedFrame(frame.get(), &sws_context, stream->time_base, frame_index, average_fps);
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
      if (stopRequested()) {
        return std::nullopt;
      }
      throw std::runtime_error("failed to receive decoded frame: " + ffmpegError(result));
    }
  }

  std::optional<Frame> decodeNextFrame() {
    while (true) {
      if (stopRequested()) {
        return std::nullopt;
      }
      if (auto decoded = receiveFrame()) {
        return decoded;
      }
      if (eof) {
        return std::nullopt;
      }
      armIoTimeout(live_input ? options.read_timeout : std::chrono::milliseconds(0));
      const int read_result = av_read_frame(format_context.get(), packet.get());
      const bool read_timed_out = interrupt_state.timed_out.load(std::memory_order_relaxed);
      disarmIoTimeout();
      if (read_result == AVERROR_EOF) {
        const int drain_result = avcodec_send_packet(codec_context.get(), nullptr);
        if (drain_result < 0 && drain_result != AVERROR_EOF) {
          throw std::runtime_error("failed to drain decoder: " + ffmpegError(drain_result));
        }
        continue;
      }
      if (read_result == AVERROR(EAGAIN) && live_input && !shouldQuit()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
        continue;
      }
      if (read_result < 0) {
        if (stopRequested() || shouldQuit()) {
          return std::nullopt;
        }
        if (read_timed_out) {
          throw std::runtime_error("timed out reading media after " + std::to_string(options.read_timeout.count()) + "ms: " + input.string());
        }
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

  std::optional<Frame> nextFrame() {
    if (pending_frame.has_value()) {
      Frame frame = std::move(*pending_frame);
      pending_frame.reset();
      return frame;
    }
    return decodeNextFrame();
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
    pending_frame.reset();
    if (clamped_us == 0) {
      return;
    }
    std::optional<Frame> last_frame;
    while (auto frame = decodeNextFrame()) {
      if (frame->pts_us >= clamped_us) {
        pending_frame = std::move(*frame);
        return;
      }
      last_frame = std::move(*frame);
    }
    pending_frame = std::move(last_frame);
  }

  FormatContextPtr format_context;
  CodecContextPtr codec_context;
  PacketPtr packet;
  AvFramePtr frame;
  std::filesystem::path input;
  const AVStream* stream = nullptr;
  int video_stream_index = -1;
  std::optional<double> average_fps;
  int64_t frame_index = 0;
  bool eof = false;
  bool live_input = false;
  VideoDecoderOptions options;
  DecoderInterruptState interrupt_state;
  bool still_image = false;
  bool animated_image = false;
  SwsContext* sws_context = nullptr;
  std::optional<Frame> pending_frame;
};

VideoDecoder::VideoDecoder(const std::filesystem::path& input,
                           VideoDecoderOptions options,
                           const std::atomic<bool>* external_stop_requested)
    : impl_(std::make_unique<Impl>(input, std::move(options), external_stop_requested)) {}

VideoDecoder::VideoDecoder(VideoDecoder&&) noexcept = default;

VideoDecoder& VideoDecoder::operator=(VideoDecoder&&) noexcept = default;

VideoDecoder::~VideoDecoder() = default;

std::optional<Frame> VideoDecoder::nextFrame() {
  return impl_->nextFrame();
}

void VideoDecoder::stop() noexcept {
  impl_->interrupt_state.stop_requested.store(true, std::memory_order_relaxed);
}

void VideoDecoder::seekToUs(int64_t position_us) {
  impl_->seekToUs(position_us);
}

void VideoDecoder::restart() {
  impl_->seekToUs(0);
}

bool VideoDecoder::isStillImage() const noexcept {
  return impl_->still_image;
}

bool VideoDecoder::isAnimatedImage() const noexcept {
  return impl_->animated_image;
}

std::optional<double> VideoDecoder::averageFps() const noexcept {
  return impl_->average_fps;
}

}  // namespace strok
