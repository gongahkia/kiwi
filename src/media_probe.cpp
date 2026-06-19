#include "media_probe.hpp"

#include "frame.hpp"
#include "media_input.hpp"
#include "png_writer.hpp"

#include <array>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <deque>
#include <exception>
#include <filesystem>
#include <iomanip>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavdevice/avdevice.h>
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
  std::span<const uint8_t> convert(const AVFrame* frame, int dst_width, int dst_height) {
    const auto format = static_cast<AVPixelFormat>(frame->format);
    if (frame->width <= 0 || frame->height <= 0 || dst_width <= 0 || dst_height <= 0 || format == AV_PIX_FMT_NONE) {
      throw std::runtime_error("decoded frame has invalid geometry or pixel format");
    }
    if (context_ == nullptr || src_width_ != frame->width || src_height_ != frame->height ||
        dst_width_ != dst_width || dst_height_ != dst_height || format_ != format) {
      reset(frame->width, frame->height, dst_width, dst_height, format);
    }
    uint8_t* dst_data[4] {rgb_.data(), nullptr, nullptr, nullptr};
    int dst_linesize[4] {dst_width_ * 3, 0, 0, 0};
    const int scaled = sws_scale(context_.get(), frame->data, frame->linesize, 0, src_height_, dst_data, dst_linesize);
    if (scaled != dst_height_) {
      throw std::runtime_error("failed to convert frame to RGB24");
    }
    return rgb_;
  }

  int width() const noexcept {
    return dst_width_;
  }

  int height() const noexcept {
    return dst_height_;
  }

 private:
  void reset(int src_width, int src_height, int dst_width, int dst_height, AVPixelFormat format) {
    SwsContext* raw_context = sws_getContext(src_width, src_height, format, dst_width, dst_height, AV_PIX_FMT_RGB24, SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (raw_context == nullptr) {
      throw std::runtime_error("failed to create RGB24 scaler");
    }
    context_.reset(raw_context);
    src_width_ = src_width;
    src_height_ = src_height;
    dst_width_ = dst_width;
    dst_height_ = dst_height;
    format_ = format;
    rgb_.assign(static_cast<std::size_t>(dst_width_) * static_cast<std::size_t>(dst_height_) * 3, 0);
  }

  SwsContextPtr context_;
  int src_width_ = 0;
  int src_height_ = 0;
  int dst_width_ = 0;
  int dst_height_ = 0;
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

struct WorkingSize {
  int w = 0;
  int h = 0;
};

WorkingSize computeWorkingSize(int src_width, int src_height, const MediaProbeOptions& options) {
  if (src_width <= 0 || src_height <= 0) {
    throw std::runtime_error("invalid source size");
  }
  if (options.cell_aspect <= 0.0) {
    throw std::runtime_error("cell aspect must be positive");
  }

  const double img_aspect = static_cast<double>(src_width) / static_cast<double>(src_height);
  const auto rows_for_cols = [&](int cols) {
    return std::max(1, static_cast<int>(std::llround(static_cast<double>(cols) * (1.0 / img_aspect) * options.cell_aspect)));
  };
  const auto cols_for_rows = [&](int rows) {
    return std::max(1, static_cast<int>(std::llround(static_cast<double>(rows) * img_aspect / options.cell_aspect)));
  };

  if (options.target_cols.has_value() && options.target_rows.has_value()) {
    const int rows = rows_for_cols(*options.target_cols);
    if (rows <= *options.target_rows) {
      return WorkingSize{.w = *options.target_cols, .h = rows};
    }
    return WorkingSize{.w = cols_for_rows(*options.target_rows), .h = *options.target_rows};
  }
  if (options.target_cols.has_value()) {
    return WorkingSize{.w = *options.target_cols, .h = rows_for_cols(*options.target_cols)};
  }
  if (options.target_rows.has_value()) {
    return WorkingSize{.w = cols_for_rows(*options.target_rows), .h = *options.target_rows};
  }
  return WorkingSize{.w = src_width, .h = src_height};
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
  int64_t owned_frames = 0;
  std::optional<int64_t> first_pts_us;
  std::optional<int64_t> last_pts_us;
  bool pts_monotonic = true;
  int frame_queue_capacity = 0;
  bool threaded_decode = false;
  std::optional<std::filesystem::path> dumped_png;
  WorkingSize working_size;
};

Frame makeOwnedFrame(int width, int height, std::span<const uint8_t> rgb, int64_t pts_us) {
  Frame frame;
  frame.w = width;
  frame.h = height;
  frame.rgb.assign(rgb.begin(), rgb.end());
  frame.pts_us = pts_us;
  return frame;
}

class FrameQueue {
 public:
  explicit FrameQueue(std::size_t capacity) : capacity_(capacity) {
    if (capacity_ == 0) {
      throw std::runtime_error("frame queue capacity must be positive");
    }
  }

  bool push(Frame frame) {
    std::unique_lock lock(mutex_);
    not_full_.wait(lock, [&] { return closed_ || queue_.size() < capacity_; });
    if (closed_) {
      return false;
    }
    queue_.push_back(std::move(frame));
    not_empty_.notify_one();
    return true;
  }

  bool pop(Frame* frame) {
    std::unique_lock lock(mutex_);
    not_empty_.wait(lock, [&] { return closed_ || !queue_.empty(); });
    if (queue_.empty()) {
      return false;
    }
    *frame = std::move(queue_.front());
    queue_.pop_front();
    not_full_.notify_one();
    return true;
  }

  void close() {
    {
      std::lock_guard lock(mutex_);
      closed_ = true;
    }
    not_empty_.notify_all();
    not_full_.notify_all();
  }

  std::size_t capacity() const noexcept {
    return capacity_;
  }

 private:
  std::size_t capacity_;
  std::mutex mutex_;
  std::condition_variable not_empty_;
  std::condition_variable not_full_;
  std::deque<Frame> queue_;
  bool closed_ = false;
};

class DecodeCancelled : public std::exception {
 public:
  const char* what() const noexcept override {
    return "decode cancelled";
  }
};

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

void recordPts(DecodeStats* stats, int64_t pts_us) {
  if (!stats->first_pts_us.has_value()) {
    stats->first_pts_us = pts_us;
  }
  if (stats->last_pts_us.has_value() && pts_us <= *stats->last_pts_us) {
    stats->pts_monotonic = false;
  }
  stats->last_pts_us = pts_us;
}

void receiveDecodedFrames(AVCodecContext* codec_context, AVFrame* frame, RgbConverter* converter, int64_t* frame_index, AVRational time_base, std::optional<double> average_fps, const MediaProbeOptions& options, FrameQueue* queue) {
  while (true) {
    const int result = avcodec_receive_frame(codec_context, frame);
    if (result == 0) {
      if (converter != nullptr) {
        const WorkingSize working_size = computeWorkingSize(frame->width, frame->height, options);
        const auto rgb = converter->convert(frame, working_size.w, working_size.h);
        const int64_t pts_us = framePtsUs(frame, time_base, *frame_index, average_fps);
        Frame owned_frame = makeOwnedFrame(converter->width(), converter->height(), rgb, pts_us);
        if (owned_frame.w != working_size.w || owned_frame.h != working_size.h ||
            owned_frame.rgb.size() != rgb.size() || owned_frame.pts_us != pts_us) {
          throw std::runtime_error("owned frame RGB24 copy failed");
        }
        if (!queue->push(std::move(owned_frame))) {
          av_frame_unref(frame);
          throw DecodeCancelled();
        }
      }
      ++(*frame_index);
      av_frame_unref(frame);
      continue;
    }
    if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
      return;
    }
    throw std::runtime_error("failed to receive decoded frame: " + ffmpegError(result));
  }
}

void decodeWorker(AVFormatContext* format_context, AVCodecContext* codec_context, int video_stream_index, AVRational time_base, std::optional<double> average_fps, const MediaProbeOptions& options, FrameQueue* queue) {
  PacketPtr packet(av_packet_alloc());
  if (packet == nullptr) {
    throw std::runtime_error("failed to allocate packet");
  }
  FramePtr frame(av_frame_alloc());
  if (frame == nullptr) {
    throw std::runtime_error("failed to allocate frame");
  }

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
        receiveDecodedFrames(codec_context, frame.get(), &converter, &frame_index, time_base, average_fps, options, queue);
        send_result = avcodec_send_packet(codec_context, packet.get());
      }
      if (send_result < 0) {
        av_packet_unref(packet.get());
        throw std::runtime_error("failed to send packet to decoder: " + ffmpegError(send_result));
      }
      receiveDecodedFrames(codec_context, frame.get(), &converter, &frame_index, time_base, average_fps, options, queue);
    }

    av_packet_unref(packet.get());
  }

  const int drain_result = avcodec_send_packet(codec_context, nullptr);
  if (drain_result < 0 && drain_result != AVERROR_EOF) {
    throw std::runtime_error("failed to drain decoder: " + ffmpegError(drain_result));
  }
  receiveDecodedFrames(codec_context, frame.get(), &converter, &frame_index, time_base, average_fps, options, queue);
}

DecodeStats decodeFrames(AVFormatContext* format_context, AVCodecContext* codec_context, int video_stream_index, AVRational time_base, std::optional<double> average_fps, const MediaProbeOptions& options) {
  constexpr std::size_t queue_capacity = 6;
  FrameQueue queue(queue_capacity);
  DecodeStats stats;
  stats.frame_queue_capacity = static_cast<int>(queue.capacity());
  stats.threaded_decode = true;

  std::exception_ptr worker_error;
  std::thread worker([&] {
    try {
      decodeWorker(format_context, codec_context, video_stream_index, time_base, average_fps, options, &queue);
    } catch (const DecodeCancelled&) {
    } catch (...) {
      worker_error = std::current_exception();
    }
    queue.close();
  });

  Frame frame;
  int64_t consume_index = 0;
  while (queue.pop(&frame)) {
    ++stats.decoded_frames;
    ++stats.converted_rgb_frames;
    ++stats.owned_frames;
    recordPts(&stats, frame.pts_us);
    stats.working_size = WorkingSize{.w = frame.w, .h = frame.h};
    if (options.dump_png.has_value() && options.dump_frame_index.has_value() &&
        consume_index == *options.dump_frame_index) {
      writePngRgb24(*options.dump_png, frame.w, frame.h, frame.rgb);
      stats.dumped_png = *options.dump_png;
    }
    if (options.on_frame && !options.on_frame(frame, consume_index)) {
      queue.close();
      ++consume_index;
      break;
    }
    ++consume_index;
  }

  worker.join();
  if (worker_error != nullptr) {
    std::rethrow_exception(worker_error);
  }
  if (options.dump_png.has_value() && !stats.dumped_png.has_value()) {
    throw std::runtime_error("requested frame was not decoded: " + std::to_string(*options.dump_frame_index));
  }
  return stats;
}

}  // namespace

MediaProbeInfo probeMedia(const std::filesystem::path& input, const MediaProbeOptions& options) {
  av_log_set_level(AV_LOG_QUIET);
  if (options.dump_png.has_value() != options.dump_frame_index.has_value()) {
    throw std::runtime_error("--dump-frame and --dump-png must be used together");
  }
  if (options.target_cols.has_value() && *options.target_cols <= 0) {
    throw std::runtime_error("target columns must be positive");
  }
  if (options.target_rows.has_value() && *options.target_rows <= 0) {
    throw std::runtime_error("target rows must be positive");
  }

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
  AVDictionary* open_options = nullptr;
  if (camera.has_value()) {
    avdevice_register_all();
    input_format = av_find_input_format(camera->format.c_str());
    if (input_format == nullptr) {
      throw std::runtime_error("FFmpeg input device unavailable: " + camera->format);
    }
    open_input = camera->device;
    av_dict_set(&open_options, "framerate", "30", 0);
    if (camera->format == "avfoundation") {
      av_dict_set(&open_options, "pixel_format", "nv12", 0);
    }
    av_dict_set(&open_options, "fflags", "nobuffer", 0);
    av_dict_set(&open_options, "flags", "low_delay", 0);
  }

  AVFormatContext* raw_context = nullptr;
  int result = avformat_open_input(&raw_context, open_input.c_str(), input_format, &open_options);
  av_dict_free(&open_options);
  if (result < 0) {
    if (result == AVERROR_INVALIDDATA) {
      throw std::runtime_error("corrupt or unsupported media: " + input_string + ": " + ffmpegError(result));
    }
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
  const auto average_fps = rationalToDouble(video_stream->avg_frame_rate);
  const auto decode_started = std::chrono::steady_clock::now();
  const DecodeStats decode_stats = decodeFrames(format_context.get(), decoder_context.get(), video_stream_index, video_stream->time_base, average_fps, options);
  const std::chrono::duration<double> decode_elapsed = std::chrono::steady_clock::now() - decode_started;

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
  info.average_fps = average_fps;
  info.decoded_frames = decode_stats.decoded_frames;
  info.converted_rgb_frames = decode_stats.converted_rgb_frames;
  info.owned_frames = decode_stats.owned_frames;
  info.first_pts_us = decode_stats.first_pts_us;
  info.last_pts_us = decode_stats.last_pts_us;
  info.pts_monotonic = decode_stats.pts_monotonic;
  info.decode_seconds = decode_elapsed.count();
  if (info.decode_seconds > 0.0) {
    info.decode_fps = static_cast<double>(info.decoded_frames) / info.decode_seconds;
  }
  info.frame_queue_capacity = decode_stats.frame_queue_capacity;
  info.threaded_decode = decode_stats.threaded_decode;
  info.working_width = decode_stats.working_size.w;
  info.working_height = decode_stats.working_size.h;
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
      << "converted_rgb_frames: " << info.converted_rgb_frames << '\n'
      << "owned_frames: " << info.owned_frames << '\n'
      << "first_pts_us: " << (info.first_pts_us.has_value() ? std::to_string(*info.first_pts_us) : "unknown") << '\n'
      << "last_pts_us: " << (info.last_pts_us.has_value() ? std::to_string(*info.last_pts_us) : "unknown") << '\n'
      << "pts_monotonic: " << (info.pts_monotonic ? "yes" : "no") << '\n'
      << "decode_seconds: " << std::fixed << std::setprecision(6) << info.decode_seconds << '\n'
      << "decode_fps: " << std::fixed << std::setprecision(3) << info.decode_fps << '\n'
      << "threaded_decode: " << (info.threaded_decode ? "yes" : "no") << '\n'
      << "frame_queue_capacity: " << info.frame_queue_capacity << '\n'
      << "working_resolution: " << info.working_width << 'x' << info.working_height << '\n';
  if (info.dumped_png.has_value()) {
    out << "dumped_png: " << info.dumped_png->string() << '\n';
  }
  return out.str();
}

}  // namespace contourtty
