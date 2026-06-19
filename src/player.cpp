#include "player.hpp"

#include "audio_backend.hpp"
#include "audio_decode.hpp"
#include "braille_renderer.hpp"
#include "cell_buffer.hpp"
#include "color_dither.hpp"
#include "color_mode.hpp"
#include "diff_emitter.hpp"
#include "frame_sampling.hpp"
#include "glyph_ramp.hpp"
#include "glyph_shape.hpp"
#include "halfblock_renderer.hpp"
#include "luminance.hpp"
#include "media_input.hpp"
#include "render_layout.hpp"
#include "renderer.hpp"
#include "structure_edges.hpp"
#include "structure_sampling.hpp"
#include "terminal.hpp"
#include "video_decoder.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <memory>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <sys/select.h>
#include <thread>
#include <unistd.h>
#include <vector>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/error.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/pixfmt.h>
#include <libswscale/swscale.h>
}

namespace contourtty {
namespace {

class FramePacer {
 public:
  explicit FramePacer(const CliOptions& options) {
    if (options.fps.has_value() && *options.fps > 0.0) {
      override_frame_us_ = static_cast<int64_t>(std::llround(1000000.0 / *options.fps));
      frame_duration_us_ = *override_frame_us_;
    }
  }

  void waitForFrame(const Frame& frame) {
    if (!start_.has_value()) {
      start_ = std::chrono::steady_clock::now();
      first_pts_us_ = frame.pts_us;
      last_media_us_ = 0;
      last_deadline_ = *start_;
      ++frame_index_;
      return;
    }

    const int64_t media_us = mediaTimeUs(frame);
    const int64_t delta_us = media_us - last_media_us_;
    if (delta_us > 0 && !override_frame_us_.has_value()) {
      frame_duration_us_ = delta_us;
    }
    const auto deadline = *start_ + std::chrono::microseconds(media_us);
    last_deadline_ = deadline;
    if (deadline > std::chrono::steady_clock::now()) {
      std::this_thread::sleep_until(deadline);
    }
    last_media_us_ = media_us;
    ++frame_index_;
  }

  void finish() const {
    if (!last_deadline_.has_value() || frame_duration_us_ <= 0) {
      return;
    }
    const auto deadline = *last_deadline_ + std::chrono::microseconds(frame_duration_us_);
    if (deadline > std::chrono::steady_clock::now()) {
      std::this_thread::sleep_until(deadline);
    }
  }

  void reset() {
    start_.reset();
    last_deadline_.reset();
    first_pts_us_ = 0;
    last_media_us_ = 0;
    frame_index_ = 0;
  }

 private:
  int64_t mediaTimeUs(const Frame& frame) const {
    if (override_frame_us_.has_value()) {
      return static_cast<int64_t>(frame_index_) * *override_frame_us_;
    }
    return std::max<int64_t>(0, frame.pts_us - first_pts_us_);
  }

  std::optional<std::chrono::steady_clock::time_point> start_;
  std::optional<std::chrono::steady_clock::time_point> last_deadline_;
  std::optional<int64_t> override_frame_us_;
  int64_t first_pts_us_ = 0;
  int64_t last_media_us_ = 0;
  int64_t frame_duration_us_ = 33333;
  int64_t frame_index_ = 0;
};

struct DriftStats {
  int64_t samples = 0;
  int64_t max_abs_us = 0;
  int64_t sum_abs_us = 0;
  int64_t rendered_frames = 0;
  int64_t dropped_frames = 0;
};

enum class FrameAction {
  Render,
  Drop,
  Quit,
  Control,
};

enum class PlaybackCommand {
  None,
  Quit,
  TogglePause,
  SeekBackward,
  SeekForward,
};

std::deque<PlaybackCommand> g_pending_commands;

struct AudioSyncState {
  int64_t first_video_pts_us = -1;
  int64_t previous_video_us = -1;
  int64_t frame_interval_us = 33333;
  int64_t last_rendered_video_us = -1;
};

void resetSyncForSeek(AudioSyncState* sync) {
  sync->previous_video_us = -1;
  sync->last_rendered_video_us = -1;
}

int64_t frameMediaUs(const Frame& frame, int64_t first_pts_us) {
  return std::max<int64_t>(0, frame.pts_us - first_pts_us);
}

PlaybackCommand pollKeyboardCommand() {
  if (!g_pending_commands.empty()) {
    const PlaybackCommand command = g_pending_commands.front();
    g_pending_commands.pop_front();
    return command;
  }

  fd_set read_set;
  FD_ZERO(&read_set);
  FD_SET(STDIN_FILENO, &read_set);
  timeval timeout {};
  const int ready = select(STDIN_FILENO + 1, &read_set, nullptr, nullptr, &timeout);
  if (ready <= 0 || !FD_ISSET(STDIN_FILENO, &read_set)) {
    return PlaybackCommand::None;
  }

  char buffer[32] {};
  const ssize_t n = ::read(STDIN_FILENO, buffer, sizeof(buffer));
  if (n <= 0) {
    return PlaybackCommand::None;
  }
  for (ssize_t i = 0; i < n; ++i) {
    if (buffer[i] == 'q' || buffer[i] == 'Q') {
      g_pending_commands.push_back(PlaybackCommand::Quit);
      continue;
    }
    if (buffer[i] == ' ') {
      g_pending_commands.push_back(PlaybackCommand::TogglePause);
      continue;
    }
    if (buffer[i] == '\x1b' && i + 2 < n && buffer[i + 1] == '[') {
      if (buffer[i + 2] == 'D') {
        g_pending_commands.push_back(PlaybackCommand::SeekBackward);
        i += 2;
        continue;
      }
      if (buffer[i + 2] == 'C') {
        g_pending_commands.push_back(PlaybackCommand::SeekForward);
        i += 2;
        continue;
      }
    }
  }
  if (g_pending_commands.empty()) {
    return PlaybackCommand::None;
  }
  const PlaybackCommand command = g_pending_commands.front();
  g_pending_commands.pop_front();
  return command;
}

bool shouldDropForMaxFps(int64_t video_us, const CliOptions& options, AudioSyncState* sync) {
  if (!options.max_fps.has_value() || *options.max_fps <= 0.0 || sync->last_rendered_video_us < 0) {
    return false;
  }
  const int64_t min_interval_us = static_cast<int64_t>(std::llround(1000000.0 / *options.max_fps));
  return video_us - sync->last_rendered_video_us < min_interval_us;
}

FrameAction waitForAudioClock(const Frame& frame, const CliOptions& options, PcmPlayer& player, AudioSyncState* sync, DriftStats* stats, PlaybackCommand* command) {
  if (sync->first_video_pts_us < 0) {
    sync->first_video_pts_us = frame.pts_us;
  }
  const int64_t video_us = frameMediaUs(frame, sync->first_video_pts_us);
  if (sync->previous_video_us >= 0 && video_us > sync->previous_video_us) {
    sync->frame_interval_us = video_us - sync->previous_video_us;
  }
  sync->previous_video_us = video_us;

  if (shouldDropForMaxFps(video_us, options, sync)) {
    ++stats->dropped_frames;
    return FrameAction::Drop;
  }

  while (!shouldQuit()) {
    *command = pollKeyboardCommand();
    if (*command == PlaybackCommand::Quit) {
      return FrameAction::Quit;
    }
    if (*command != PlaybackCommand::None) {
      return FrameAction::Control;
    }
    if (player.paused()) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }
    const int64_t audio_us = player.masterClockUs();
    const int64_t late_drop_us = std::min<int64_t>(sync->frame_interval_us, 50000);
    if (audio_us - video_us > late_drop_us) {
      ++stats->dropped_frames;
      return FrameAction::Drop;
    }
    if (audio_us >= video_us) {
      const int64_t drift_abs = std::llabs(video_us - audio_us);
      ++stats->samples;
      stats->max_abs_us = std::max(stats->max_abs_us, drift_abs);
      stats->sum_abs_us += drift_abs;
      ++stats->rendered_frames;
      sync->last_rendered_video_us = video_us;
      return FrameAction::Render;
    }
    const int64_t remaining_us = video_us - audio_us;
    const auto sleep_us = std::clamp<int64_t>(remaining_us / 2, 1000, 5000);
    std::this_thread::sleep_for(std::chrono::microseconds(sleep_us));
  }
  return FrameAction::Quit;
}

bool writeAll(int fd, const std::string& bytes) {
  std::size_t written = 0;
  while (written < bytes.size()) {
    const ssize_t n = ::write(fd, bytes.data() + written, bytes.size() - written);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return false;
    }
    written += static_cast<std::size_t>(n);
  }
  return true;
}

EmissionOptions centeredEmissionOptions(EmissionOptions options, TerminalSize terminal, const CellBuffer& cells) {
  const RenderOrigin origin = centeredOrigin(RenderSize{.cols = cells.cols(), .rows = cells.rows()}, terminal);
  options.origin_row = origin.row;
  options.origin_col = origin.col;
  return options;
}

bool renderStillResize(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize* terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, DiffEmitter* emitter, const EmissionOptions& emission_options, RenderStats* render_stats) {
  *terminal = queryTerminalSize();
  emitter->reset();
  std::string clear = "\x1b[2J";
  if (!writeAll(STDOUT_FILENO, clear)) {
    return false;
  }
  renderFrame(frame, ramp, options, *terminal, shape_table, cells, render_stats);
  const EmissionResult emission = emitter->emit(*cells, centeredEmissionOptions(emission_options, *terminal, *cells));
  return emission.bytes.empty() || writeAll(STDOUT_FILENO, emission.bytes);
}

bool holdStillFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize* terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, DiffEmitter* emitter, const EmissionOptions& emission_options, RenderStats* render_stats) {
  while (!shouldQuit()) {
    const PlaybackCommand command = pollKeyboardCommand();
    if (command == PlaybackCommand::Quit) {
      return true;
    }
    if (consumeResizeFlag() && !renderStillResize(frame, ramp, options, terminal, shape_table, cells, emitter, emission_options, render_stats)) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return true;
}

struct OutputFormatContextDeleter {
  void operator()(AVFormatContext* context) const noexcept {
    if (context == nullptr) {
      return;
    }
    if ((context->oformat->flags & AVFMT_NOFILE) == 0 && context->pb != nullptr) {
      avio_closep(&context->pb);
    }
    avformat_free_context(context);
  }
};

using OutputFormatContextPtr = std::unique_ptr<AVFormatContext, OutputFormatContextDeleter>;

struct EncoderContextDeleter {
  void operator()(AVCodecContext* context) const noexcept {
    avcodec_free_context(&context);
  }
};

using EncoderContextPtr = std::unique_ptr<AVCodecContext, EncoderContextDeleter>;

struct EncodeFrameDeleter {
  void operator()(AVFrame* frame) const noexcept {
    av_frame_free(&frame);
  }
};

using EncodeFramePtr = std::unique_ptr<AVFrame, EncodeFrameDeleter>;

struct EncodePacketDeleter {
  void operator()(AVPacket* packet) const noexcept {
    av_packet_free(&packet);
  }
};

using EncodePacketPtr = std::unique_ptr<AVPacket, EncodePacketDeleter>;

struct ExportSwsContextDeleter {
  void operator()(SwsContext* context) const noexcept {
    sws_freeContext(context);
  }
};

using ExportSwsContextPtr = std::unique_ptr<SwsContext, ExportSwsContextDeleter>;

std::string ffmpegError(int error_code) {
  std::array<char, AV_ERROR_MAX_STRING_SIZE> buffer {};
  if (av_strerror(error_code, buffer.data(), buffer.size()) < 0) {
    return "unknown ffmpeg error";
  }
  return buffer.data();
}

void throwFfmpegError(const std::string& action, int result) {
  if (result < 0) {
    throw std::runtime_error(action + ": " + ffmpegError(result));
  }
}

AVPixelFormat chooseEncoderPixelFormat(const AVCodec* codec) {
#if LIBAVCODEC_VERSION_MAJOR >= 61
  const void* configs = nullptr;
  int config_count = 0;
  const int result = avcodec_get_supported_config(nullptr, codec, AV_CODEC_CONFIG_PIX_FORMAT, 0, &configs, &config_count);
  if (result >= 0 && configs != nullptr && config_count > 0) {
    const auto* formats = static_cast<const AVPixelFormat*>(configs);
    for (int i = 0; i < config_count; ++i) {
      if (formats[i] == AV_PIX_FMT_YUV420P) {
        return AV_PIX_FMT_YUV420P;
      }
    }
    return formats[0];
  }
  return AV_PIX_FMT_YUV420P;
#else
  if (codec->pix_fmts == nullptr) {
    return AV_PIX_FMT_YUV420P;
  }
  for (const AVPixelFormat* format = codec->pix_fmts; *format != AV_PIX_FMT_NONE; ++format) {
    if (*format == AV_PIX_FMT_YUV420P) {
      return AV_PIX_FMT_YUV420P;
    }
  }
  return codec->pix_fmts[0];
#endif
}

const AVCodec* chooseMp4Encoder() {
  if (const AVCodec* encoder = avcodec_find_encoder(AV_CODEC_ID_H264)) {
    return encoder;
  }
  if (const AVCodec* encoder = avcodec_find_encoder(AV_CODEC_ID_MPEG4)) {
    return encoder;
  }
  throw std::runtime_error("no MP4-compatible video encoder found");
}

class Mp4VideoWriter {
 public:
  Mp4VideoWriter(const std::filesystem::path& path, int width, int height, double fps) {
    AVFormatContext* raw_format_context = nullptr;
    throwFfmpegError("could not allocate MP4 output", avformat_alloc_output_context2(&raw_format_context, nullptr, "mp4", path.string().c_str()));
    if (raw_format_context == nullptr) {
      throw std::runtime_error("could not allocate MP4 output");
    }
    format_context_.reset(raw_format_context);
    encoder_ = chooseMp4Encoder();
    stream_ = avformat_new_stream(format_context_.get(), nullptr);
    if (stream_ == nullptr) {
      throw std::runtime_error("could not create MP4 video stream");
    }

    codec_context_.reset(avcodec_alloc_context3(encoder_));
    if (codec_context_ == nullptr) {
      throw std::runtime_error("could not allocate MP4 encoder context");
    }

    const double bounded_fps = std::clamp(fps, 1.0, 240.0);
    const AVRational framerate = av_d2q(bounded_fps, 100000);
    codec_context_->codec_id = encoder_->id;
    codec_context_->codec_type = AVMEDIA_TYPE_VIDEO;
    codec_context_->width = width;
    codec_context_->height = height;
    codec_context_->pix_fmt = chooseEncoderPixelFormat(encoder_);
    codec_context_->time_base = AVRational{framerate.den, framerate.num};
    codec_context_->framerate = framerate;
    codec_context_->bit_rate = std::max<int64_t>(400000, static_cast<int64_t>(std::llround(static_cast<double>(width) * static_cast<double>(height) * bounded_fps * 2.0)));
    codec_context_->gop_size = std::max(1, static_cast<int>(std::llround(bounded_fps * 2.0)));
    codec_context_->max_b_frames = 0;
    if ((format_context_->oformat->flags & AVFMT_GLOBALHEADER) != 0) {
      codec_context_->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }
    if (encoder_->id == AV_CODEC_ID_H264) {
      av_opt_set(codec_context_->priv_data, "preset", "veryfast", 0);
      av_opt_set(codec_context_->priv_data, "crf", "20", 0);
    }
    throwFfmpegError("could not open MP4 encoder", avcodec_open2(codec_context_.get(), encoder_, nullptr));
    throwFfmpegError("could not copy MP4 encoder parameters", avcodec_parameters_from_context(stream_->codecpar, codec_context_.get()));
    stream_->time_base = codec_context_->time_base;

    if ((format_context_->oformat->flags & AVFMT_NOFILE) == 0) {
      throwFfmpegError("could not open MP4 output file", avio_open(&format_context_->pb, path.string().c_str(), AVIO_FLAG_WRITE));
    }
    throwFfmpegError("could not write MP4 header", avformat_write_header(format_context_.get(), nullptr));

    frame_.reset(av_frame_alloc());
    if (frame_ == nullptr) {
      throw std::runtime_error("could not allocate MP4 frame");
    }
    frame_->format = codec_context_->pix_fmt;
    frame_->width = codec_context_->width;
    frame_->height = codec_context_->height;
    throwFfmpegError("could not allocate MP4 frame buffer", av_frame_get_buffer(frame_.get(), 32));

    packet_.reset(av_packet_alloc());
    if (packet_ == nullptr) {
      throw std::runtime_error("could not allocate MP4 packet");
    }
    sws_context_.reset(sws_getContext(width, height, AV_PIX_FMT_RGB24, width, height, codec_context_->pix_fmt, SWS_BILINEAR, nullptr, nullptr, nullptr));
    if (sws_context_ == nullptr) {
      throw std::runtime_error("could not create MP4 RGB converter");
    }
  }

  void writeFrame(const std::vector<uint8_t>& rgb) {
    if (rgb.size() != static_cast<std::size_t>(codec_context_->width) * static_cast<std::size_t>(codec_context_->height) * 3U) {
      throw std::runtime_error("MP4 raster frame size mismatch");
    }
    throwFfmpegError("could not make MP4 frame writable", av_frame_make_writable(frame_.get()));
    const uint8_t* src_data[4] = {rgb.data(), nullptr, nullptr, nullptr};
    const int src_linesize[4] = {codec_context_->width * 3, 0, 0, 0};
    const int scaled = sws_scale(sws_context_.get(), src_data, src_linesize, 0, codec_context_->height, frame_->data, frame_->linesize);
    if (scaled != codec_context_->height) {
      throw std::runtime_error("could not convert MP4 RGB frame");
    }
    frame_->pts = next_pts_++;
    encode(frame_.get());
  }

  void finish() {
    encode(nullptr);
    throwFfmpegError("could not write MP4 trailer", av_write_trailer(format_context_.get()));
  }

 private:
  void encode(AVFrame* frame) {
    throwFfmpegError("could not send MP4 frame to encoder", avcodec_send_frame(codec_context_.get(), frame));
    while (true) {
      const int result = avcodec_receive_packet(codec_context_.get(), packet_.get());
      if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
        return;
      }
      throwFfmpegError("could not receive MP4 packet", result);
      av_packet_rescale_ts(packet_.get(), codec_context_->time_base, stream_->time_base);
      packet_->stream_index = stream_->index;
      throwFfmpegError("could not write MP4 packet", av_interleaved_write_frame(format_context_.get(), packet_.get()));
      av_packet_unref(packet_.get());
    }
  }

  const AVCodec* encoder_ = nullptr;
  AVStream* stream_ = nullptr;
  OutputFormatContextPtr format_context_;
  EncoderContextPtr codec_context_;
  EncodeFramePtr frame_;
  EncodePacketPtr packet_;
  ExportSwsContextPtr sws_context_;
  int64_t next_pts_ = 0;
};

constexpr int kExportCellPixelWidth = 8;
constexpr int kExportCellPixelHeight = 12;

std::array<uint8_t, 7> asciiGlyphPattern(char32_t glyph) {
  switch (glyph) {
    case U' ':
      return {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000};
    case U'.':
      return {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b00100};
    case U':':
      return {0b00000, 0b00100, 0b00100, 0b00000, 0b00100, 0b00100, 0b00000};
    case U'-':
      return {0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000};
    case U'=':
      return {0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000};
    case U'+':
      return {0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000};
    case U'*':
      return {0b00000, 0b10101, 0b01110, 0b11111, 0b01110, 0b10101, 0b00000};
    case U'#':
      return {0b01010, 0b11111, 0b01010, 0b01010, 0b11111, 0b01010, 0b00000};
    case U'%':
      return {0b11001, 0b11010, 0b00100, 0b01000, 0b10110, 0b00110, 0b00000};
    case U'@':
      return {0b01110, 0b10001, 0b10111, 0b10101, 0b10111, 0b10000, 0b01110};
    case U'|':
      return {0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100};
    case U'/':
      return {0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b00000, 0b00000};
    case U'\\':
      return {0b10000, 0b01000, 0b00100, 0b00010, 0b00001, 0b00000, 0b00000};
    case U'_':
      return {0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b11111};
    case U'?':
      return {0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b00000, 0b00100};
    default:
      return asciiGlyphPattern(U'?');
  }
}

bool asciiGlyphPixel(const std::array<uint8_t, 7>& pattern, int x, int y) {
  if (x < 1 || x > 6 || y < 2 || y > 9) {
    return false;
  }
  const int source_x = (x - 1) * 5 / 6;
  const int source_y = (y - 2) * 7 / 8;
  return ((pattern[static_cast<std::size_t>(source_y)] >> (4 - source_x)) & 1U) != 0;
}

void writeRasterPixel(std::vector<uint8_t>* raster, int width, int x, int y, Rgb color) {
  const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)) * 3U;
  raster->at(index) = color.r;
  raster->at(index + 1U) = color.g;
  raster->at(index + 2U) = color.b;
}

bool brailleDotSet(char32_t glyph, int dot_col, int dot_row) {
  if (glyph < 0x2800U || glyph > 0x28ffU) {
    return false;
  }
  static constexpr uint8_t kBrailleBits[4][2] {
    {0x01, 0x08},
    {0x02, 0x10},
    {0x04, 0x20},
    {0x40, 0x80},
  };
  const uint8_t mask = static_cast<uint8_t>(glyph - 0x2800U);
  return (mask & kBrailleBits[dot_row][dot_col]) != 0;
}

bool brailleGlyphPixel(char32_t glyph, int x, int y) {
  static constexpr int kDotCentersX[2] {2, 5};
  static constexpr int kDotCentersY[4] {1, 4, 7, 10};
  for (int dot_row = 0; dot_row < 4; ++dot_row) {
    for (int dot_col = 0; dot_col < 2; ++dot_col) {
      if (!brailleDotSet(glyph, dot_col, dot_row)) {
        continue;
      }
      if (std::abs(x - kDotCentersX[dot_col]) <= 1 && std::abs(y - kDotCentersY[dot_row]) <= 1) {
        return true;
      }
    }
  }
  return false;
}

Rgb exportForegroundColor(const Cell& cell, ColorMode color_mode) {
  if (color_mode == ColorMode::Mono) {
    return Rgb{.r = 255, .g = 255, .b = 255};
  }
  return cell.fg;
}

Rgb exportBackgroundColor(const Cell& cell, ColorMode color_mode) {
  if (color_mode == ColorMode::Mono) {
    return Rgb{};
  }
  return cell.bg;
}

std::vector<uint8_t> rasterizeCells(const CellBuffer& cells, ColorMode color_mode, DitherMode dither_mode) {
  CellBuffer quantized;
  const CellBuffer* source = &cells;
  if (supportsPaletteDither(color_mode)) {
    quantized = applyPaletteDither(cells, color_mode, dither_mode);
    source = &quantized;
  }
  const int width = source->cols() * kExportCellPixelWidth;
  const int height = source->rows() * kExportCellPixelHeight;
  std::vector<uint8_t> raster(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 3U, 0);
  for (int cell_row = 0; cell_row < source->rows(); ++cell_row) {
    for (int cell_col = 0; cell_col < source->cols(); ++cell_col) {
      const Cell& cell = source->at(cell_col, cell_row);
      const Rgb fg = exportForegroundColor(cell, color_mode);
      const Rgb bg = exportBackgroundColor(cell, color_mode);
      const auto pattern = asciiGlyphPattern(cell.glyph);
      for (int y = 0; y < kExportCellPixelHeight; ++y) {
        for (int x = 0; x < kExportCellPixelWidth; ++x) {
          Rgb color = bg;
          if (cell.glyph == U'▀') {
            color = y < kExportCellPixelHeight / 2 ? fg : bg;
          } else if (cell.glyph == U'▄') {
            color = y < kExportCellPixelHeight / 2 ? bg : fg;
          } else if (cell.glyph == U'█') {
            color = fg;
          } else if (cell.glyph >= 0x2800U && cell.glyph <= 0x28ffU) {
            color = brailleGlyphPixel(cell.glyph, x, y) ? fg : bg;
          } else if (asciiGlyphPixel(pattern, x, y)) {
            color = fg;
          }
          writeRasterPixel(&raster, width, cell_col * kExportCellPixelWidth + x, cell_row * kExportCellPixelHeight + y, color);
        }
      }
    }
  }
  return raster;
}

double mp4ExportFps(const CliOptions& options, const Frame& first_frame, const std::optional<Frame>& second_frame) {
  if (options.fps.has_value() && *options.fps > 0.0) {
    return *options.fps;
  }
  if (second_frame.has_value()) {
    const int64_t delta_us = second_frame->pts_us - first_frame.pts_us;
    if (delta_us > 0) {
      return 1000000.0 / static_cast<double>(delta_us);
    }
  }
  return 30.0;
}

enum class ExportKind {
  Ansi,
  Cast,
  Mp4,
};

ExportKind exportKindForPath(const std::filesystem::path& path) {
  const std::string extension = path.extension().string();
  if (extension == ".ansi") {
    return ExportKind::Ansi;
  }
  if (extension == ".cast") {
    return ExportKind::Cast;
  }
  if (extension == ".mp4") {
    return ExportKind::Mp4;
  }
  throw std::runtime_error("unsupported export extension: expected .ansi, .cast, or .mp4");
}

TerminalSize exportTerminalSize(const CliOptions& options) {
  return TerminalSize{
    .cols = options.width.value_or(80),
    .rows = options.height.value_or(24),
    .xpixel = 0,
    .ypixel = 0,
  };
}

std::u32string exportRampFromOptions(const CliOptions& options) {
  if (options.charset.has_value() && !isBrailleCharset(*options.charset)) {
    return resolveCharsetRamp(*options.charset);
  }
  return kDefaultGlyphRamp.data();
}

std::optional<GlyphShapeTable> exportShapeTableFromOptions(const CliOptions& options) {
  if (options.mode == "structure" && !(options.charset.has_value() && isBrailleCharset(*options.charset))) {
    return buildGlyphShapeTable(kDefaultStructureShapeGlyphs, 10, 14);
  }
  return std::nullopt;
}

std::string jsonEscape(std::string_view value) {
  std::ostringstream out;
  out << std::hex << std::setfill('0');
  for (const unsigned char ch : value) {
    switch (ch) {
      case '"':
        out << "\\\"";
        break;
      case '\\':
        out << "\\\\";
        break;
      case '\b':
        out << "\\b";
        break;
      case '\f':
        out << "\\f";
        break;
      case '\n':
        out << "\\n";
        break;
      case '\r':
        out << "\\r";
        break;
      case '\t':
        out << "\\t";
        break;
      default:
        if (ch < 0x20) {
          out << "\\u00" << std::setw(2) << static_cast<int>(ch);
        } else {
          out << static_cast<char>(ch);
        }
        break;
    }
  }
  return out.str();
}

double exportFrameTimeSeconds(const Frame& frame, int64_t first_pts_us, int64_t frame_index, const CliOptions& options) {
  if (options.fps.has_value() && *options.fps > 0.0) {
    return static_cast<double>(frame_index) / *options.fps;
  }
  return static_cast<double>(std::max<int64_t>(0, frame.pts_us - first_pts_us)) / 1000000.0;
}

void writeCastEvent(std::ofstream& out, double timestamp, std::string_view bytes) {
  out << '[' << std::fixed << std::setprecision(6) << timestamp << ",\"o\",\"" << jsonEscape(bytes) << "\"]\n";
}

void logGpuFallback(const CliOptions& options, Logger& logger) {
  if (options.gpu) {
    CONTOURTTY_LOG_WARN(logger, "gpu analysis requested but unavailable; using cpu renderer");
  }
}

}  // namespace

int exportMedia(const CliOptions& options, Logger& logger) {
  if (!options.input.has_value()) {
    throw std::runtime_error("missing input");
  }
  if (!options.export_file.has_value()) {
    throw std::runtime_error("missing export file");
  }
  logGpuFallback(options, logger);

  const std::filesystem::path output_path = *options.export_file;
  const ExportKind kind = exportKindForPath(output_path);
  VideoDecoder video_decoder(*options.input);
  auto frame = video_decoder.nextFrame();
  if (!frame.has_value()) {
    throw std::runtime_error("input contains no video frames");
  }

  const std::u32string ramp = exportRampFromOptions(options);
  std::optional<GlyphShapeTable> shape_vectors = exportShapeTableFromOptions(options);
  TerminalSize terminal = exportTerminalSize(options);
  const ColorMode color_mode = resolveColorMode(options.color_mode, "xterm-256color", std::getenv("COLORTERM"), std::getenv("NO_COLOR"));
  const EmissionOptions emission_options{.color_mode = color_mode, .dither_mode = ditherModeFromString(options.dither), .origin_row = 1, .origin_col = 1};
  CellBuffer cells;
  DiffEmitter emitter;
  RenderStats render_stats;
  const int64_t first_pts_us = frame->pts_us;
  int64_t frame_index = 0;
  int64_t exported_frames = 0;
  double last_timestamp = 0.0;
  const auto log_export = [&] {
    CONTOURTTY_LOG_INFO(logger, "exported frames=" + std::to_string(exported_frames) + " path=" + output_path.string());
    if (logger.enabled()) {
      CONTOURTTY_LOG_INFO(logger, "render stats frames=" + std::to_string(render_stats.frames) +
                                    " cells=" + std::to_string(render_stats.cells) +
                                    " render_us=" + std::to_string(render_stats.render_ns / 1000) +
                                    " shape_match_cells=" + std::to_string(render_stats.shape_match_cells));
    }
  };

  if (kind == ExportKind::Mp4) {
    std::optional<Frame> second_frame = video_decoder.nextFrame();
    renderFrame(*frame, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, logger.enabled() ? &render_stats : nullptr);
    Mp4VideoWriter writer(output_path,
                          cells.cols() * kExportCellPixelWidth,
                          cells.rows() * kExportCellPixelHeight,
                          mp4ExportFps(options, *frame, second_frame));
    writer.writeFrame(rasterizeCells(cells, color_mode, emission_options.dither_mode));
    ++exported_frames;

    const auto write_mp4_frame = [&](const Frame& current_frame) {
      renderFrame(current_frame, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, logger.enabled() ? &render_stats : nullptr);
      writer.writeFrame(rasterizeCells(cells, color_mode, emission_options.dither_mode));
    };
    if (second_frame.has_value()) {
      write_mp4_frame(*second_frame);
      ++exported_frames;
    }
    while ((frame = video_decoder.nextFrame()).has_value()) {
      write_mp4_frame(*frame);
      ++exported_frames;
    }
    writer.finish();
    log_export();
    return 0;
  }

  std::ofstream output(output_path, std::ios::binary);
  if (!output) {
    throw std::runtime_error("could not open export file: " + output_path.string());
  }

  const auto write_emission = [&](double timestamp, std::string_view bytes) {
    if (bytes.empty()) {
      return;
    }
    last_timestamp = timestamp;
    if (kind == ExportKind::Ansi) {
      output.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    } else {
      writeCastEvent(output, timestamp, bytes);
    }
  };

  const auto write_frame = [&](const Frame& current_frame) {
    renderFrame(current_frame, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, logger.enabled() ? &render_stats : nullptr);
    const EmissionResult emission = emitter.emit(cells, emission_options);
    write_emission(exportFrameTimeSeconds(current_frame, first_pts_us, frame_index, options), emission.bytes);
  };

  renderFrame(*frame, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, logger.enabled() ? &render_stats : nullptr);
  const int export_cols = cells.cols();
  const int export_rows = cells.rows();
  emitter.reset();
  if (kind == ExportKind::Ansi) {
    const std::string clear = "\x1b[2J\x1b[H\x1b[?25l";
    output.write(clear.data(), static_cast<std::streamsize>(clear.size()));
  } else {
    output << "{\"version\":2,\"width\":" << export_cols << ",\"height\":" << export_rows << "}\n";
    writeCastEvent(output, 0.0, "\x1b[2J\x1b[H\x1b[?25l");
  }

  write_emission(0.0, emitter.emit(cells, emission_options).bytes);
  ++exported_frames;
  while ((frame = video_decoder.nextFrame()).has_value()) {
    ++frame_index;
    write_frame(*frame);
    ++exported_frames;
  }
  const std::string reset = "\x1b[0m\x1b[?25h\n";
  if (kind == ExportKind::Ansi) {
    output.write(reset.data(), static_cast<std::streamsize>(reset.size()));
  } else {
    writeCastEvent(output, last_timestamp, reset);
  }
  if (!output) {
    throw std::runtime_error("failed to write export file: " + output_path.string());
  }
  log_export();
  return 0;
}

int playMedia(const CliOptions& options, Logger& logger) {
  if (!options.input.has_value()) {
    throw std::runtime_error("missing input");
  }
  logGpuFallback(options, logger);

  std::optional<DecodedAudio> decoded_audio;
  if (isCameraInput(*options.input)) {
    CONTOURTTY_LOG_INFO(logger, "no audio stream; using wall-clock pacing");
  } else {
    try {
      decoded_audio = decodeAudioFile(*options.input);
      CONTOURTTY_LOG_INFO(logger, "audio decoded frames=" + std::to_string(decoded_audio->decoded_frames) +
                                    " duration_us=" + std::to_string(decoded_audio->duration_us));
    } catch (const NoAudioStreamError&) {
      CONTOURTTY_LOG_INFO(logger, "no audio stream; using wall-clock pacing");
    }
  }

  resetQuitFlag();
  g_pending_commands.clear();
  installQuitSignalHandlers();
  installResizeSignalHandler();
  TerminalSession session;
  CONTOURTTY_LOG_INFO(logger, "playback started");

  std::u32string ramp = kDefaultGlyphRamp.data();
  if (options.charset.has_value()) {
    if (!isBrailleCharset(*options.charset)) {
      ramp = resolveCharsetRamp(*options.charset);
    }
  }
  std::optional<GlyphShapeTable> shape_vectors;
  if (options.mode == "structure" && !(options.charset.has_value() && isBrailleCharset(*options.charset))) {
    shape_vectors = buildGlyphShapeTable(kDefaultStructureShapeGlyphs, 10, 14);
    CONTOURTTY_LOG_INFO(logger, "shape vectors entries=" + std::to_string(shape_vectors->entries.size()) +
                                  " features=" + std::to_string(kShapeRegionCount));
  }

  TerminalSize terminal = queryTerminalSize();
  VideoDecoder video_decoder(*options.input);
  CellBuffer cells;
  DiffEmitter emitter;
  FramePacer pacer(options);
  std::unique_ptr<PcmPlayer> audio_player;
  if (decoded_audio.has_value()) {
    audio_player = std::make_unique<PcmPlayer>(
      decoded_audio->samples,
      PcmPlaybackOptions{
        .sample_rate = static_cast<uint32_t>(decoded_audio->sample_rate),
        .channels = static_cast<uint32_t>(decoded_audio->channels),
      });
  }
  const ColorMode color_mode = resolveColorMode(options.color_mode, std::getenv("TERM"), std::getenv("COLORTERM"), std::getenv("NO_COLOR"));
  CONTOURTTY_LOG_INFO(logger, "color mode " + std::string(colorModeName(color_mode)));
  const EmissionOptions emission_options{.color_mode = color_mode, .dither_mode = ditherModeFromString(options.dither)};
  DriftStats drift_stats;
  RenderStats render_stats;
  RenderStats* render_stats_ptr = logger.enabled() ? &render_stats : nullptr;
  AudioSyncState audio_sync;
  bool quit = false;
  bool paused_without_audio = false;
  bool audio_started = false;
  int64_t current_video_us = 0;
  std::optional<Frame> still_frame;

  std::string clear = "\x1b[2J";
  writeAll(STDOUT_FILENO, clear);
  consumeResizeFlag();

  const auto seek_to = [&](int64_t target_us) {
    const int64_t clamped_us = audio_player != nullptr
                                 ? std::clamp<int64_t>(target_us, 0, audio_player->durationUs())
                                 : std::max<int64_t>(0, target_us);
    if (audio_player != nullptr) {
      audio_player->seekToUs(clamped_us);
    } else {
      pacer.reset();
    }
    video_decoder.seekToUs(clamped_us);
    resetSyncForSeek(&audio_sync);
    current_video_us = clamped_us;
    emitter.reset();
    std::string clear_seek = "\x1b[2J";
    writeAll(STDOUT_FILENO, clear_seek);
    CONTOURTTY_LOG_INFO(logger, "seek target_us=" + std::to_string(clamped_us));
  };

  const auto apply_command = [&](PlaybackCommand command) {
    switch (command) {
      case PlaybackCommand::None:
        return true;
      case PlaybackCommand::Quit:
        quit = true;
        return false;
      case PlaybackCommand::TogglePause:
        if (audio_player != nullptr) {
          audio_player->setPaused(!audio_player->paused());
          CONTOURTTY_LOG_INFO(logger, audio_player->paused() ? "playback paused" : "playback resumed");
        } else {
          paused_without_audio = !paused_without_audio;
          CONTOURTTY_LOG_INFO(logger, paused_without_audio ? "playback paused" : "playback resumed");
        }
        return true;
      case PlaybackCommand::SeekBackward:
        seek_to((audio_player != nullptr ? audio_player->masterClockUs() : current_video_us) - 5000000);
        return true;
      case PlaybackCommand::SeekForward:
        seek_to((audio_player != nullptr ? audio_player->masterClockUs() : current_video_us) + 5000000);
        return true;
    }
    return true;
  };

  while (!shouldQuit()) {
    if (!apply_command(pollKeyboardCommand())) {
      quit = true;
      break;
    }
    if (audio_player != nullptr && audio_player->paused()) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }
    if (audio_player == nullptr && paused_without_audio) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }

    auto frame = video_decoder.nextFrame();
    if (!frame.has_value()) {
      if (video_decoder.isAnimatedImage()) {
        video_decoder.restart();
        pacer.reset();
        emitter.reset();
        std::string clear_loop = "\x1b[2J";
        writeAll(STDOUT_FILENO, clear_loop);
        CONTOURTTY_LOG_INFO(logger, "animated image loop restarted");
        continue;
      }
      if (options.loop && !video_decoder.isStillImage()) {
        video_decoder.restart();
        if (audio_player != nullptr) {
          audio_player->seekToUs(0);
        }
        pacer.reset();
        resetSyncForSeek(&audio_sync);
        current_video_us = 0;
        emitter.reset();
        std::string clear_loop = "\x1b[2J";
        writeAll(STDOUT_FILENO, clear_loop);
        CONTOURTTY_LOG_INFO(logger, "input loop restarted");
        continue;
      }
      if (video_decoder.isStillImage() && still_frame.has_value()) {
        quit = holdStillFrame(*still_frame, ramp, options, &terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, &emitter, emission_options, render_stats_ptr);
      }
      break;
    }
    if (audio_player != nullptr && !audio_started) {
      audio_player->start();
      audio_started = true;
    }
    if (audio_player != nullptr) {
      PlaybackCommand command = PlaybackCommand::None;
      const FrameAction action = waitForAudioClock(*frame, options, *audio_player, &audio_sync, &drift_stats, &command);
      if (action == FrameAction::Quit) {
        quit = true;
        break;
      }
      if (action == FrameAction::Control) {
        if (!apply_command(command)) {
          quit = true;
          break;
        }
        continue;
      }
      if (action == FrameAction::Drop) {
        continue;
      }
    } else {
      pacer.waitForFrame(*frame);
    }
    if (shouldQuit()) {
      quit = true;
      break;
    }
    if (consumeResizeFlag()) {
      terminal = queryTerminalSize();
      emitter.reset();
      std::string clear_resize = "\x1b[2J";
      writeAll(STDOUT_FILENO, clear_resize);
    }

    if (audio_sync.first_video_pts_us >= 0) {
      current_video_us = frameMediaUs(*frame, audio_sync.first_video_pts_us);
    } else {
      current_video_us = frame->pts_us;
    }
    renderFrame(*frame, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, render_stats_ptr);
    if (video_decoder.isStillImage()) {
      still_frame = *frame;
    }
    const EmissionResult emission = emitter.emit(cells, centeredEmissionOptions(emission_options, terminal, cells));
    if (!emission.bytes.empty() && !writeAll(STDOUT_FILENO, emission.bytes)) {
      quit = true;
      break;
    }
  }
  if (!quit && !shouldQuit()) {
    if (audio_player != nullptr && audio_started) {
      (void)audio_player->waitUntilComplete();
    } else {
      pacer.finish();
    }
  }
  if (drift_stats.samples > 0 || drift_stats.dropped_frames > 0 || drift_stats.rendered_frames > 0) {
    const int64_t avg_abs_us = drift_stats.samples > 0 ? drift_stats.sum_abs_us / drift_stats.samples : 0;
    CONTOURTTY_LOG_INFO(logger, "audio sync drift samples=" + std::to_string(drift_stats.samples) +
                                  " max_abs_us=" + std::to_string(drift_stats.max_abs_us) +
                                  " avg_abs_us=" + std::to_string(avg_abs_us) +
                                  " rendered_frames=" + std::to_string(drift_stats.rendered_frames) +
                                  " dropped_frames=" + std::to_string(drift_stats.dropped_frames));
  }
  if (render_stats.frames > 0) {
    const int64_t render_us = render_stats.render_ns / 1000;
    const int64_t shape_match_us = render_stats.shape_match_ns / 1000;
    const double avg_shape_match_ns = render_stats.shape_match_cells > 0
                                        ? static_cast<double>(render_stats.shape_match_ns) / static_cast<double>(render_stats.shape_match_cells)
                                        : 0.0;
    CONTOURTTY_LOG_INFO(logger, "render stats frames=" + std::to_string(render_stats.frames) +
                                  " cells=" + std::to_string(render_stats.cells) +
                                  " render_us=" + std::to_string(render_us) +
                                  " shape_match_cells=" + std::to_string(render_stats.shape_match_cells) +
                                  " shape_match_us=" + std::to_string(shape_match_us) +
                                  " avg_shape_match_ns=" + std::to_string(avg_shape_match_ns));
  }
  if (quit || shouldQuit()) {
    CONTOURTTY_LOG_INFO(logger, "playback quit before eof");
  } else {
    CONTOURTTY_LOG_INFO(logger, "playback reached eof");
  }
  return 0;
}

}  // namespace contourtty
