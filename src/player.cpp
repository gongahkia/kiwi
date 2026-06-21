#include "player.hpp"

#include "ansi.hpp"
#include "asciinema_source.hpp"
#include "audio_backend.hpp"
#include "audio_decode.hpp"
#include "bandwidth_guard.hpp"
#include "braille_renderer.hpp"
#include "captions.hpp"
#include "cell_buffer.hpp"
#include "color_mode.hpp"
#include "diff_emitter.hpp"
#include "frame_sampling.hpp"
#include "glyph_font.hpp"
#include "glyph_hog.hpp"
#include "glyph_kdtree.hpp"
#include "glyph_ramp.hpp"
#include "glyph_sdf.hpp"
#include "glyph_shape.hpp"
#include "graphics_emitter.hpp"
#include "gpu_sobel.hpp"
#include "halfblock_renderer.hpp"
#include "kitty_graphics.hpp"
#include "luminance.hpp"
#include "media_input.hpp"
#include "overlay_compose.hpp"
#include "png_writer.hpp"
#include "raster_compose.hpp"
#include "render_mode.hpp"
#include "render_layout.hpp"
#include "renderer.hpp"
#include "structure_edges.hpp"
#include "structure_overlay.hpp"
#include "structure_sampling.hpp"
#include "stream_resolver.hpp"
#include "terminal_caps.hpp"
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
#include <string_view>
#include <sys/resource.h>
#include <sys/select.h>
#include <thread>
#include <unistd.h>
#include <vector>

#if defined(__APPLE__)
#include <mach/mach.h>
#endif

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/pixfmt.h>
#include <libavutil/samplefmt.h>
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

bool writeAll(int fd, const std::string& bytes);

double timevalSeconds(timeval value) {
  return static_cast<double>(value.tv_sec) + (static_cast<double>(value.tv_usec) / 1000000.0);
}

uint64_t currentResidentBytes() {
#if defined(__APPLE__)
  mach_task_basic_info info {};
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, reinterpret_cast<task_info_t>(&info), &count) == KERN_SUCCESS) {
    return static_cast<uint64_t>(info.resident_size);
  }
#elif defined(__linux__)
  std::ifstream statm("/proc/self/statm");
  long size_pages = 0;
  long resident_pages = 0;
  if (statm >> size_pages >> resident_pages) {
    const long page_size = ::sysconf(_SC_PAGESIZE);
    if (page_size > 0 && resident_pages >= 0) {
      return static_cast<uint64_t>(resident_pages) * static_cast<uint64_t>(page_size);
    }
  }
#endif
  return 0;
}

struct ProcessMetrics {
  double user_seconds = 0.0;
  double system_seconds = 0.0;
  uint64_t rss_bytes = 0;

  double cpuSeconds() const noexcept {
    return user_seconds + system_seconds;
  }
};

ProcessMetrics sampleProcessMetrics() {
  ProcessMetrics metrics;
  rusage usage {};
  if (::getrusage(RUSAGE_SELF, &usage) == 0) {
    metrics.user_seconds = timevalSeconds(usage.ru_utime);
    metrics.system_seconds = timevalSeconds(usage.ru_stime);
  }
  metrics.rss_bytes = currentResidentBytes();
  return metrics;
}

TerminalSize debugRenderTerminal(TerminalSize terminal, const CliOptions& options) {
  if (options.debug_stats && terminal.rows > 1) {
    --terminal.rows;
  }
  return terminal;
}

CliOptions debugRenderOptions(const CliOptions& options, TerminalSize terminal) {
  CliOptions render_options = options;
  if (options.debug_stats && terminal.rows > 1) {
    const int max_rows = terminal.rows - 1;
    if (!render_options.height.has_value() || *render_options.height > max_rows) {
      render_options.height = max_rows;
    }
  }
  return render_options;
}

bool writeDebugStatusLine(TerminalSize terminal, std::string_view line) {
  if (terminal.rows <= 0 || terminal.cols <= 0) {
    return true;
  }
  std::string clipped(line.substr(0, static_cast<std::size_t>(terminal.cols)));
  std::string out;
  appendSgrReset(out);
  appendCursorMove(out, terminal.rows, 1);
  out += "\x1b[2K";
  out += clipped;
  appendSgrReset(out);
  return writeAll(STDOUT_FILENO, out);
}

class RuntimeDebugStats {
 public:
  RuntimeDebugStats(const CliOptions& options, Logger* logger)
      : enabled_(options.debug_stats),
        logger_(logger),
        started_(std::chrono::steady_clock::now()),
        last_sample_(started_),
        last_metrics_(sampleProcessMetrics()) {}

  bool enabled() const noexcept {
    return enabled_;
  }

  void recordInputFrame() noexcept {
    ++input_frames_;
    ++window_input_frames_;
  }

  void recordDroppedFrame() noexcept {
    ++dropped_frames_;
    ++window_dropped_frames_;
  }

  void recordPresentedFrame(const CellBuffer& cells, const EmissionResult& emission) noexcept {
    ++presented_frames_;
    ++window_presented_frames_;
    window_changed_cells_ += static_cast<int64_t>(emission.changed_cells);
    window_emitted_bytes_ += static_cast<int64_t>(emission.bytes.size());
    last_cols_ = cells.cols();
    last_rows_ = cells.rows();
  }

  bool maybeReport(TerminalSize terminal, bool force = false) {
    if (!enabled_) {
      return true;
    }
    const auto now = std::chrono::steady_clock::now();
    const std::chrono::duration<double> window_elapsed = now - last_sample_;
    if (!force && window_elapsed.count() < 1.0) {
      return true;
    }
    const ProcessMetrics metrics = sampleProcessMetrics();
    const std::string line = formatLine(now, metrics, std::max(window_elapsed.count(), 0.001));
    if (logger_ != nullptr && logger_->enabled()) {
      CONTOURTTY_LOG_INFO(*logger_, line);
    }
    last_sample_ = now;
    last_metrics_ = metrics;
    window_input_frames_ = 0;
    window_presented_frames_ = 0;
    window_dropped_frames_ = 0;
    window_changed_cells_ = 0;
    window_emitted_bytes_ = 0;
    return writeDebugStatusLine(terminal, line);
  }

 private:
  std::string formatLine(std::chrono::steady_clock::time_point now, ProcessMetrics metrics, double window_seconds) const {
    const std::chrono::duration<double> elapsed = now - started_;
    const double cpu_pct = 100.0 * ((metrics.cpuSeconds() - last_metrics_.cpuSeconds()) / window_seconds);
    std::ostringstream out;
    out << std::fixed << std::setprecision(1)
        << "debug elapsed=" << elapsed.count() << "s"
        << " input_fps=" << (static_cast<double>(window_input_frames_) / window_seconds)
        << " output_fps=" << (static_cast<double>(window_presented_frames_) / window_seconds)
        << " drop_fps=" << (static_cast<double>(window_dropped_frames_) / window_seconds)
        << " frames=" << presented_frames_ << "/" << input_frames_
        << " dropped=" << dropped_frames_
        << " cpu=" << std::max(0.0, cpu_pct) << "%"
        << " changed_cells=" << window_changed_cells_
        << " bytes=" << window_emitted_bytes_
        << " size=" << last_cols_ << "x" << last_rows_;
    if (metrics.rss_bytes > 0) {
      out << " rss=" << (static_cast<double>(metrics.rss_bytes) / (1024.0 * 1024.0)) << "MiB";
    } else {
      out << " rss=unknown";
    }
    return out.str();
  }

  bool enabled_ = false;
  Logger* logger_ = nullptr;
  std::chrono::steady_clock::time_point started_;
  std::chrono::steady_clock::time_point last_sample_;
  ProcessMetrics last_metrics_;
  int64_t input_frames_ = 0;
  int64_t presented_frames_ = 0;
  int64_t dropped_frames_ = 0;
  int64_t window_input_frames_ = 0;
  int64_t window_presented_frames_ = 0;
  int64_t window_dropped_frames_ = 0;
  int64_t window_changed_cells_ = 0;
  int64_t window_emitted_bytes_ = 0;
  int last_cols_ = 0;
  int last_rows_ = 0;
};

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

bool renderStillResize(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize* terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, DiffEmitter* emitter, const EmissionOptions& emission_options, RenderStats* render_stats, RuntimeDebugStats* debug_stats) {
  *terminal = queryTerminalSize();
  emitter->reset();
  std::string clear = "\x1b[2J";
  if (!writeAll(STDOUT_FILENO, clear)) {
    return false;
  }
  const TerminalSize render_terminal = debugRenderTerminal(*terminal, options);
  const CliOptions render_options = debugRenderOptions(options, *terminal);
  renderFrame(frame, ramp, render_options, render_terminal, shape_table, cells, render_stats);
  const EmissionResult emission = emitter->emit(*cells, centeredEmissionOptions(emission_options, render_terminal, *cells));
  if (debug_stats != nullptr && debug_stats->enabled()) {
    debug_stats->recordPresentedFrame(*cells, emission);
  }
  if (!emission.bytes.empty() && !writeAll(STDOUT_FILENO, emission.bytes)) {
    return false;
  }
  return debug_stats == nullptr || debug_stats->maybeReport(*terminal, true);
}

bool holdStillFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize* terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, DiffEmitter* emitter, const EmissionOptions& emission_options, RenderStats* render_stats, RuntimeDebugStats* debug_stats) {
  while (!shouldQuit()) {
    const PlaybackCommand command = pollKeyboardCommand();
    if (command == PlaybackCommand::Quit) {
      return true;
    }
    if (consumeResizeFlag() && !renderStillResize(frame, ramp, options, terminal, shape_table, cells, emitter, emission_options, render_stats, debug_stats)) {
      return true;
    }
    if (debug_stats != nullptr && !debug_stats->maybeReport(*terminal)) {
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

const AVCodec* chooseMp4AudioEncoder() {
  if (const AVCodec* encoder = avcodec_find_encoder(AV_CODEC_ID_AAC)) {
    return encoder;
  }
  throw std::runtime_error("no MP4-compatible AAC audio encoder found");
}

bool audioSampleFormatSupported(const AVCodec* codec, AVSampleFormat format) {
#if LIBAVCODEC_VERSION_MAJOR >= 61
  const void* configs = nullptr;
  int config_count = 0;
  const int result = avcodec_get_supported_config(nullptr, codec, AV_CODEC_CONFIG_SAMPLE_FORMAT, 0, &configs, &config_count);
  if (result >= 0 && configs != nullptr && config_count > 0) {
    const auto* formats = static_cast<const AVSampleFormat*>(configs);
    for (int i = 0; i < config_count; ++i) {
      if (formats[i] == format) {
        return true;
      }
    }
    return false;
  }
  return true;
#else
  if (codec->sample_fmts == nullptr) {
    return true;
  }
  for (const AVSampleFormat* candidate = codec->sample_fmts; *candidate != AV_SAMPLE_FMT_NONE; ++candidate) {
    if (*candidate == format) {
      return true;
    }
  }
  return false;
#endif
}

AVSampleFormat chooseAudioSampleFormat(const AVCodec* codec) {
  if (audioSampleFormatSupported(codec, AV_SAMPLE_FMT_FLTP)) {
    return AV_SAMPLE_FMT_FLTP;
  }
  if (audioSampleFormatSupported(codec, AV_SAMPLE_FMT_FLT)) {
    return AV_SAMPLE_FMT_FLT;
  }
  throw std::runtime_error("AAC encoder does not support float audio samples");
}

class Mp4VideoWriter {
 public:
  Mp4VideoWriter(const std::filesystem::path& path, int width, int height, double fps, const DecodedAudio* audio) {
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
    initAudio(audio);

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
    if (audio_codec_context_ != nullptr) {
      audio_frame_.reset(av_frame_alloc());
      if (audio_frame_ == nullptr) {
        throw std::runtime_error("could not allocate MP4 audio frame");
      }
      audio_frame_->format = audio_codec_context_->sample_fmt;
      audio_frame_->sample_rate = audio_codec_context_->sample_rate;
      audio_frame_->nb_samples = audio_frame_samples_;
      throwFfmpegError("could not copy MP4 audio frame layout", av_channel_layout_copy(&audio_frame_->ch_layout, &audio_codec_context_->ch_layout));
      throwFfmpegError("could not allocate MP4 audio frame buffer", av_frame_get_buffer(audio_frame_.get(), 0));
      audio_packet_.reset(av_packet_alloc());
      if (audio_packet_ == nullptr) {
        throw std::runtime_error("could not allocate MP4 audio packet");
      }
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
    encodeVideo(frame_.get());
    writeAudioThroughVideoTime();
  }

  void finish() {
    encodeVideo(nullptr);
    writeRemainingAudio();
    encodeAudio(nullptr);
    throwFfmpegError("could not write MP4 trailer", av_write_trailer(format_context_.get()));
  }

 private:
  void initAudio(const DecodedAudio* audio) {
    if (audio == nullptr || audio->samples.empty()) {
      return;
    }
    if (audio->sample_rate <= 0 || audio->channels <= 0) {
      throw std::runtime_error("invalid decoded audio for MP4 export");
    }
    audio_ = audio;
    audio_encoder_ = chooseMp4AudioEncoder();
    audio_stream_ = avformat_new_stream(format_context_.get(), nullptr);
    if (audio_stream_ == nullptr) {
      throw std::runtime_error("could not create MP4 audio stream");
    }
    audio_codec_context_.reset(avcodec_alloc_context3(audio_encoder_));
    if (audio_codec_context_ == nullptr) {
      throw std::runtime_error("could not allocate MP4 audio encoder context");
    }
    audio_codec_context_->codec_id = audio_encoder_->id;
    audio_codec_context_->codec_type = AVMEDIA_TYPE_AUDIO;
    audio_codec_context_->sample_rate = audio->sample_rate;
    audio_codec_context_->sample_fmt = chooseAudioSampleFormat(audio_encoder_);
    audio_codec_context_->bit_rate = std::max<int64_t>(64000, static_cast<int64_t>(audio->channels) * 64000);
    audio_codec_context_->time_base = AVRational{1, audio->sample_rate};
    av_channel_layout_default(&audio_codec_context_->ch_layout, audio->channels);
    if ((format_context_->oformat->flags & AVFMT_GLOBALHEADER) != 0) {
      audio_codec_context_->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }
    throwFfmpegError("could not open MP4 audio encoder", avcodec_open2(audio_codec_context_.get(), audio_encoder_, nullptr));
    throwFfmpegError("could not copy MP4 audio encoder parameters", avcodec_parameters_from_context(audio_stream_->codecpar, audio_codec_context_.get()));
    audio_stream_->time_base = audio_codec_context_->time_base;
    audio_frame_samples_ = audio_codec_context_->frame_size > 0 ? audio_codec_context_->frame_size : 1024;
  }

  std::size_t audioTotalSampleFrames() const {
    if (audio_ == nullptr || audio_->channels <= 0) {
      return 0;
    }
    return audio_->samples.size() / static_cast<std::size_t>(audio_->channels);
  }

  bool writeOneAudioFrame() {
    if (audio_ == nullptr || audio_codec_context_ == nullptr || audio_frame_ == nullptr) {
      return false;
    }
    const std::size_t total_frames = audioTotalSampleFrames();
    if (next_audio_sample_frame_ >= total_frames) {
      return false;
    }
    const int remaining = static_cast<int>(std::min<std::size_t>(total_frames - next_audio_sample_frame_, static_cast<std::size_t>(audio_frame_samples_)));
    const bool variable_frame_size = (audio_codec_context_->codec->capabilities & AV_CODEC_CAP_VARIABLE_FRAME_SIZE) != 0;
    const int send_samples = variable_frame_size ? remaining : audio_frame_samples_;
    audio_frame_->nb_samples = send_samples;
    throwFfmpegError("could not make MP4 audio frame writable", av_frame_make_writable(audio_frame_.get()));
    fillAudioFrame(remaining, send_samples);
    audio_frame_->pts = next_audio_pts_;
    next_audio_pts_ += send_samples;
    next_audio_sample_frame_ += static_cast<std::size_t>(remaining);
    encodeAudio(audio_frame_.get());
    return true;
  }

  void fillAudioFrame(int actual_samples, int send_samples) {
    const int channels = audio_codec_context_->ch_layout.nb_channels;
    if (channels != audio_->channels) {
      throw std::runtime_error("MP4 audio channel count mismatch");
    }
    if (audio_codec_context_->sample_fmt == AV_SAMPLE_FMT_FLTP) {
      for (int channel = 0; channel < channels; ++channel) {
        auto* dst = reinterpret_cast<float*>(audio_frame_->data[channel]);
        for (int i = 0; i < send_samples; ++i) {
          dst[i] = i < actual_samples ? audio_->samples[(next_audio_sample_frame_ + static_cast<std::size_t>(i)) * static_cast<std::size_t>(channels) + static_cast<std::size_t>(channel)] : 0.0F;
        }
      }
      return;
    }
    if (audio_codec_context_->sample_fmt == AV_SAMPLE_FMT_FLT) {
      auto* dst = reinterpret_cast<float*>(audio_frame_->data[0]);
      for (int i = 0; i < send_samples; ++i) {
        for (int channel = 0; channel < channels; ++channel) {
          const std::size_t dst_index = static_cast<std::size_t>(i) * static_cast<std::size_t>(channels) + static_cast<std::size_t>(channel);
          dst[dst_index] = i < actual_samples ? audio_->samples[(next_audio_sample_frame_ + static_cast<std::size_t>(i)) * static_cast<std::size_t>(channels) + static_cast<std::size_t>(channel)] : 0.0F;
        }
      }
      return;
    }
    throw std::runtime_error("unsupported MP4 audio sample format");
  }

  void writeAudioThroughVideoTime() {
    if (audio_ == nullptr || audio_codec_context_ == nullptr) {
      return;
    }
    const double video_seconds = static_cast<double>(next_pts_) * static_cast<double>(codec_context_->time_base.num) / static_cast<double>(codec_context_->time_base.den);
    const std::size_t target_frames = std::min(audioTotalSampleFrames(), static_cast<std::size_t>(std::ceil(video_seconds * static_cast<double>(audio_codec_context_->sample_rate))));
    while (next_audio_sample_frame_ < target_frames) {
      if (!writeOneAudioFrame()) {
        return;
      }
    }
  }

  void writeRemainingAudio() {
    while (writeOneAudioFrame()) {}
  }

  void encodeVideo(AVFrame* frame) {
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

  void encodeAudio(AVFrame* frame) {
    if (audio_codec_context_ == nullptr) {
      return;
    }
    throwFfmpegError("could not send MP4 audio frame to encoder", avcodec_send_frame(audio_codec_context_.get(), frame));
    while (true) {
      const int result = avcodec_receive_packet(audio_codec_context_.get(), audio_packet_.get());
      if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
        return;
      }
      throwFfmpegError("could not receive MP4 audio packet", result);
      av_packet_rescale_ts(audio_packet_.get(), audio_codec_context_->time_base, audio_stream_->time_base);
      audio_packet_->stream_index = audio_stream_->index;
      throwFfmpegError("could not write MP4 audio packet", av_interleaved_write_frame(format_context_.get(), audio_packet_.get()));
      av_packet_unref(audio_packet_.get());
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
  const DecodedAudio* audio_ = nullptr;
  const AVCodec* audio_encoder_ = nullptr;
  AVStream* audio_stream_ = nullptr;
  EncoderContextPtr audio_codec_context_;
  EncodeFramePtr audio_frame_;
  EncodePacketPtr audio_packet_;
  int audio_frame_samples_ = 0;
  int64_t next_audio_pts_ = 0;
  std::size_t next_audio_sample_frame_ = 0;
};

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

std::u32string rampFromOptions(const CliOptions& options, const GlyphFont* glyph_font) {
  std::u32string ramp = kDefaultGlyphRamp.data();
  const bool packed_braille = options.charset.has_value() && isBrailleCharset(*options.charset);
  if (options.charset.has_value() && !packed_braille) {
    ramp = resolveCharsetRamp(*options.charset);
  }
  if (options.ramp_sort && !packed_braille) {
    if (glyph_font == nullptr) {
      throw std::runtime_error("--ramp-sort requires --font PATH");
    }
    ramp = sortRampByInkDensity(ramp, *glyph_font, 10, 14);
  }
  return ramp;
}

std::optional<GlyphShapeTable> shapeTableFromOptions(const CliOptions& options, const GlyphFont* glyph_font) {
  if (!structureOverlayEnabled(options)) {
    return std::nullopt;
  }
  if (options.glyph_features == "hog") {
    GlyphShapeTable table;
    if (glyph_font != nullptr) {
      table = buildHogGlyphShapeTable(*glyph_font, kDefaultStructureShapeGlyphs, 10, 14);
    } else {
      table = buildHogGlyphShapeTable(kDefaultStructureShapeGlyphs, 10, 14);
    }
    attachGlyphKdTree(&table);
    return table;
  }
  if (options.glyph_features == "sdf") {
    if (glyph_font != nullptr) {
      return buildSdfGlyphShapeTable(*glyph_font, kDefaultStructureShapeGlyphs, 10, 14);
    }
    return buildSdfGlyphShapeTable(kDefaultStructureShapeGlyphs, 10, 14);
  }
  if (glyph_font != nullptr) {
    return buildGlyphShapeTable(*glyph_font, kDefaultStructureShapeGlyphs, 10, 14);
  }
  return buildGlyphShapeTable(kDefaultStructureShapeGlyphs, 10, 14);
}

std::optional<GlyphFont> glyphFontFromOptions(const CliOptions& options, Logger& logger) {
  if (!options.font_path.has_value()) {
    return std::nullopt;
  }
  std::optional<GlyphFont> font;
  font.emplace(*options.font_path);
  CONTOURTTY_LOG_INFO(logger, "font loaded path=" + font->path().string());
  return font;
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

void logGpuRequest(const CliOptions& options, Logger& logger) {
  if (options.gpu) {
    if (gpuSobelAvailable()) {
      CONTOURTTY_LOG_INFO(logger, "gpu analysis requested; using Metal structure backend");
    } else {
      CONTOURTTY_LOG_WARN(logger, "gpu analysis requested but unavailable; using cpu renderer");
    }
  }
}

std::optional<std::string> capsOverrideFromOptions(const CliOptions& options) {
  if (options.caps.has_value() && *options.caps != "dump") {
    return options.caps;
  }
  return std::nullopt;
}

std::optional<GraphicsFrameOptions> graphicsOptionsFromResolution(const CliOptions& options,
                                                                  const TerminalCaps& caps,
                                                                  ColorMode color_mode,
                                                                  DitherMode dither_mode,
                                                                  const GlyphFont* glyph_font,
                                                                  Logger& logger) {
  if (options.render_mode == "text") {
    return std::nullopt;
  }
  const RenderModeResolution resolution = resolveRenderMode(options, caps);
  if (resolution.degraded_to_text) {
    CONTOURTTY_LOG_INFO(logger, "render mode " + options.render_mode + " degraded to text");
    return std::nullopt;
  }
  if (resolution.mode == ResolvedRenderMode::Hybrid) {
    CONTOURTTY_LOG_INFO(logger, "hybrid render mode requested; sparse overlay path not wired yet, using text");
    return std::nullopt;
  }
  if (resolution.mode != ResolvedRenderMode::Pixel) {
    return std::nullopt;
  }
  if (resolution.protocol == GraphicsProtocol::Sixel || resolution.protocol == GraphicsProtocol::None) {
    CONTOURTTY_LOG_INFO(logger, "graphics protocol " + std::string(toString(resolution.protocol)) + " not implemented; using text");
    return std::nullopt;
  }
  CONTOURTTY_LOG_INFO(logger, "render mode pixel protocol=" + std::string(toString(resolution.protocol)));
  return GraphicsFrameOptions{
    .protocol = resolution.protocol,
    .color_mode = color_mode,
    .dither_mode = dither_mode,
    .glyph_font = glyph_font,
  };
}

TerminalCaps detectGraphicsCaps(const CliOptions& options) {
  return detectTerminalCapsFromEnvironment(options.font_path, capsOverrideFromOptions(options));
}

std::string graphicsFrameBytes(const CellBuffer& cells, const GraphicsFrameOptions& graphics_options, TerminalSize terminal) {
  const RenderOrigin origin = centeredOrigin(RenderSize{.cols = cells.cols(), .rows = cells.rows()}, terminal);
  std::string bytes;
  appendCursorMove(bytes, origin.row, origin.col);
  bytes += emitGraphicsFrame(cells, graphics_options).bytes;
  return bytes;
}

std::chrono::steady_clock::time_point exportTimepoint(double timestamp) {
  return std::chrono::steady_clock::time_point{} + std::chrono::microseconds(static_cast<int64_t>(std::llround(timestamp * 1000000.0)));
}

int64_t captionFrameTimeUs(const Frame& frame, int64_t first_pts_us, int64_t frame_index, const CliOptions& options) {
  if (options.fps.has_value() && *options.fps > 0.0) {
    return static_cast<int64_t>(std::llround((static_cast<double>(frame_index) * 1000000.0) / *options.fps));
  }
  return std::max<int64_t>(0, frame.pts_us - first_pts_us);
}

int64_t defaultCaptionDurationUs(const CliOptions& options) {
  if (options.fps.has_value() && *options.fps > 0.0) {
    return std::max<int64_t>(1000, static_cast<int64_t>(std::llround(1000000.0 / *options.fps)));
  }
  return 33333;
}

class CaptionSidecarWriter {
 public:
  CaptionSidecarWriter(const std::optional<std::string>& path, int64_t fallback_duration_us)
      : builder_(fallback_duration_us) {
    if (!path.has_value()) {
      return;
    }
    path_ = std::filesystem::path(*path);
    output_.emplace(*path_, std::ios::binary);
    if (!*output_) {
      throw std::runtime_error("could not open captions file: " + path_->string());
    }
  }

  bool enabled() const noexcept {
    return output_.has_value();
  }

  void recordFrame(const Frame& frame, int64_t start_us) {
    if (!output_.has_value()) {
      return;
    }
    builder_.recordFrame(frame, start_us);
  }

  void finish() {
    if (!output_.has_value() || finished_) {
      return;
    }
    const std::string srt = builder_.finish();
    output_->write(srt.data(), static_cast<std::streamsize>(srt.size()));
    output_->flush();
    if (!*output_) {
      throw std::runtime_error("failed to write captions file: " + path_->string());
    }
    finished_ = true;
  }

  int cueCount() const noexcept {
    return builder_.cueCount();
  }

  std::string pathString() const {
    return path_.has_value() ? path_->string() : std::string{};
  }

 private:
  std::optional<std::filesystem::path> path_;
  std::optional<std::ofstream> output_;
  CaptionSrtBuilder builder_;
  bool finished_ = false;
};

class SceneOverlaySource {
 public:
  explicit SceneOverlaySource(const CliOptions& options) {
    if (!options.overlay.has_value()) {
      return;
    }
    const std::string& overlay = *options.overlay;
    std::optional<std::filesystem::path> path = resolveBundledScene(overlay);
    if (!path.has_value()) {
      path = std::filesystem::path(overlay);
    }
    if (path->extension() != ".obj") {
      throw std::runtime_error("unsupported overlay source: " + overlay);
    }
    mesh_.emplace(loadObjScene(*path));
    path_ = path->string();
  }

  bool enabled() const noexcept {
    return mesh_.has_value();
  }

  const std::string& pathString() const noexcept {
    return path_;
  }

  Frame compose(const Frame& base, double time_seconds) const {
    if (!mesh_.has_value()) {
      return base;
    }
    const SceneGBuffer overlay = renderSceneGBuffer(*mesh_, SceneRenderOptions{.width = base.w, .height = base.h, .time_seconds = time_seconds});
    return composeDepthOverlay(base, overlay);
  }

 private:
  std::optional<SceneMesh> mesh_;
  std::string path_;
};

const Frame& frameWithOverlay(const Frame& base, const SceneOverlaySource& overlay_source, double time_seconds, std::optional<Frame>* storage) {
  storage->reset();
  if (!overlay_source.enabled()) {
    return base;
  }
  storage->emplace(overlay_source.compose(base, time_seconds));
  return **storage;
}

}  // namespace

int exportMedia(const CliOptions& options, Logger& logger) {
  if (!options.input.has_value()) {
    throw std::runtime_error("missing input");
  }
  if (!options.export_file.has_value()) {
    throw std::runtime_error("missing export file");
  }
  logGpuRequest(options, logger);

  const std::filesystem::path output_path = *options.export_file;
  const ExportKind kind = exportKindForPath(output_path);
  VideoDecoder video_decoder(*options.input);
  auto frame = video_decoder.nextFrame();
  if (!frame.has_value()) {
    throw std::runtime_error("input contains no video frames");
  }

  std::optional<GlyphFont> glyph_font = glyphFontFromOptions(options, logger);
  const GlyphFont* glyph_font_ptr = glyph_font.has_value() ? &*glyph_font : nullptr;
  const std::u32string ramp = rampFromOptions(options, glyph_font_ptr);
  std::optional<GlyphShapeTable> shape_vectors = shapeTableFromOptions(options, glyph_font_ptr);
  TerminalSize terminal = exportTerminalSize(options);
  const ColorMode color_mode = resolveColorMode(options.color_mode, "xterm-256color", std::getenv("COLORTERM"), std::getenv("NO_COLOR"));
  const DitherMode dither_mode = ditherModeFromString(options.dither);
  const EmissionOptions emission_options{.color_mode = color_mode, .dither_mode = dither_mode, .diff_oklab_eps = options.diff_oklab_eps.value_or(0.0), .origin_row = 1, .origin_col = 1};
  std::optional<GraphicsFrameOptions> graphics_options;
  if (kind != ExportKind::Mp4 && options.render_mode != "text") {
    graphics_options = graphicsOptionsFromResolution(options, detectGraphicsCaps(options), color_mode, dither_mode, glyph_font_ptr, logger);
  }
  std::optional<BandwidthGuard> graphics_bandwidth;
  if (graphics_options.has_value()) {
    graphics_bandwidth.emplace(options.bandwidth_cap_mb_s);
  }
  SceneOverlaySource overlay_source(options);
  if (overlay_source.enabled()) {
    CONTOURTTY_LOG_INFO(logger, "overlay scene=" + overlay_source.pathString());
  }
  CellBuffer cells;
  DiffEmitter emitter;
  RenderTemporalState temporal_state;
  RenderStats render_stats;
  const int64_t first_pts_us = frame->pts_us;
  int64_t frame_index = 0;
  int64_t exported_frames = 0;
  double last_timestamp = 0.0;
  CaptionSidecarWriter caption_writer(options.captions_file, defaultCaptionDurationUs(options));
  const auto log_export = [&] {
    CONTOURTTY_LOG_INFO(logger, "exported frames=" + std::to_string(exported_frames) + " path=" + output_path.string());
    if (caption_writer.enabled()) {
      CONTOURTTY_LOG_INFO(logger, "captions cues=" + std::to_string(caption_writer.cueCount()) + " path=" + caption_writer.pathString());
    }
    if (logger.enabled()) {
      const int64_t shape_match_us = render_stats.shape_match_ns / 1000;
      const double avg_shape_match_ns = render_stats.shape_match_cells > 0
                                          ? static_cast<double>(render_stats.shape_match_ns) / static_cast<double>(render_stats.shape_match_cells)
                                          : 0.0;
      CONTOURTTY_LOG_INFO(logger, "render stats frames=" + std::to_string(render_stats.frames) +
                                    " cells=" + std::to_string(render_stats.cells) +
                                    " render_us=" + std::to_string(render_stats.render_ns / 1000) +
                                    " shape_match_cells=" + std::to_string(render_stats.shape_match_cells) +
                                    " shape_match_us=" + std::to_string(shape_match_us) +
                                    " avg_shape_match_ns=" + std::to_string(avg_shape_match_ns) +
                                    " optical_flow_blocks=" + std::to_string(render_stats.optical_flow_blocks) +
                                    " optical_flow_us=" + std::to_string(render_stats.optical_flow_ns / 1000) +
                                    " warp_history_cells=" + std::to_string(render_stats.warp_history_cells) +
                                    " warp_history_us=" + std::to_string(render_stats.warp_history_ns / 1000));
    }
  };

  if (kind == ExportKind::Mp4) {
    std::optional<DecodedAudio> export_audio;
    try {
      export_audio = decodeAudioFile(std::filesystem::path(*options.input));
      CONTOURTTY_LOG_INFO(logger, "export audio decoded frames=" + std::to_string(export_audio->decoded_frames) +
                                    " duration_us=" + std::to_string(export_audio->duration_us));
    } catch (const NoAudioStreamError&) {
      CONTOURTTY_LOG_INFO(logger, "export input has no audio stream; writing silent MP4");
    }
    std::optional<Frame> second_frame = video_decoder.nextFrame();
    std::optional<Frame> overlay_frame;
    const Frame& render_input = frameWithOverlay(*frame, overlay_source, exportFrameTimeSeconds(*frame, first_pts_us, frame_index, options), &overlay_frame);
    renderFrame(render_input, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, logger.enabled() ? &render_stats : nullptr, &temporal_state);
    caption_writer.recordFrame(*frame, captionFrameTimeUs(*frame, first_pts_us, frame_index, options));
    RasterImage raster = rasterComposeCells(cells, color_mode, emission_options.dither_mode, glyph_font_ptr);
    Mp4VideoWriter writer(output_path,
                          raster.width,
                          raster.height,
                          mp4ExportFps(options, *frame, second_frame),
                          export_audio.has_value() ? &*export_audio : nullptr);
    writer.writeFrame(raster.rgb);
    ++exported_frames;

    const auto write_mp4_frame = [&](const Frame& current_frame) {
      std::optional<Frame> current_overlay_frame;
      const Frame& current_render_input = frameWithOverlay(current_frame, overlay_source, exportFrameTimeSeconds(current_frame, first_pts_us, frame_index, options), &current_overlay_frame);
      renderFrame(current_render_input, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, logger.enabled() ? &render_stats : nullptr, &temporal_state);
      caption_writer.recordFrame(current_frame, captionFrameTimeUs(current_frame, first_pts_us, frame_index, options));
      writer.writeFrame(rasterComposeCells(cells, color_mode, emission_options.dither_mode, glyph_font_ptr).rgb);
    };
    if (second_frame.has_value()) {
      ++frame_index;
      write_mp4_frame(*second_frame);
      ++exported_frames;
    }
    while ((frame = video_decoder.nextFrame()).has_value()) {
      ++frame_index;
      write_mp4_frame(*frame);
      ++exported_frames;
    }
    writer.finish();
    caption_writer.finish();
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

  const auto emit_cells = [&](double timestamp) -> std::optional<EmissionResult> {
    if (graphics_options.has_value()) {
      const std::string bytes = graphicsFrameBytes(cells, *graphics_options, terminal);
      const BandwidthDecision decision = graphics_bandwidth->recordFrame(bytes.size(), exportTimepoint(timestamp));
      if (!decision.send) {
        if (decision.warn) {
          CONTOURTTY_LOG_WARN(logger, "graphics bandwidth cap hit; dropping frames");
        }
        return std::nullopt;
      }
      return EmissionResult{.bytes = bytes, .changed_cells = cells.size()};
    }
    return emitter.emit(cells, emission_options);
  };

  const auto write_frame = [&](const Frame& current_frame) {
    const double timestamp = exportFrameTimeSeconds(current_frame, first_pts_us, frame_index, options);
    std::optional<Frame> overlay_frame;
    const Frame& render_input = frameWithOverlay(current_frame, overlay_source, timestamp, &overlay_frame);
    renderFrame(render_input, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, logger.enabled() ? &render_stats : nullptr, &temporal_state);
    caption_writer.recordFrame(current_frame, captionFrameTimeUs(current_frame, first_pts_us, frame_index, options));
    const std::optional<EmissionResult> emission = emit_cells(timestamp);
    if (emission.has_value()) {
      write_emission(timestamp, emission->bytes);
    }
  };

  temporal_state.reset();
  std::optional<Frame> first_overlay_frame;
  const Frame& first_render_input = frameWithOverlay(*frame, overlay_source, exportFrameTimeSeconds(*frame, first_pts_us, frame_index, options), &first_overlay_frame);
  renderFrame(first_render_input, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, logger.enabled() ? &render_stats : nullptr, &temporal_state);
  caption_writer.recordFrame(*frame, captionFrameTimeUs(*frame, first_pts_us, frame_index, options));
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

  if (const std::optional<EmissionResult> emission = emit_cells(0.0); emission.has_value()) {
    write_emission(0.0, emission->bytes);
    ++exported_frames;
  }
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
  caption_writer.finish();
  log_export();
  return 0;
}

int writeCaptionSidecar(const CliOptions& options, Logger& logger) {
  if (!options.input.has_value()) {
    throw std::runtime_error("missing input");
  }
  if (!options.captions_file.has_value()) {
    throw std::runtime_error("missing captions file");
  }
  VideoDecoder video_decoder(*options.input);
  auto frame = video_decoder.nextFrame();
  if (!frame.has_value()) {
    throw std::runtime_error("input contains no video frames");
  }
  CaptionSidecarWriter caption_writer(options.captions_file, defaultCaptionDurationUs(options));
  const int64_t first_pts_us = frame->pts_us;
  int64_t frame_index = 0;
  do {
    caption_writer.recordFrame(*frame, captionFrameTimeUs(*frame, first_pts_us, frame_index, options));
    ++frame_index;
    frame = video_decoder.nextFrame();
  } while (frame.has_value());
  caption_writer.finish();
  CONTOURTTY_LOG_INFO(logger, "captions cues=" + std::to_string(caption_writer.cueCount()) + " path=" + caption_writer.pathString());
  return 0;
}

int writeStillSnapshot(const CliOptions& options, Logger& logger) {
  if (!options.input.has_value()) {
    throw std::runtime_error("missing input");
  }
  if (!options.still_file.has_value()) {
    throw std::runtime_error("missing still output file");
  }
  logGpuRequest(options, logger);

  VideoDecoder video_decoder(*options.input);
  if (options.still_at_us.has_value()) {
    video_decoder.seekToUs(*options.still_at_us);
  }
  auto frame = video_decoder.nextFrame();
  if (!frame.has_value()) {
    throw std::runtime_error("input contains no video frames");
  }

  std::optional<GlyphFont> glyph_font = glyphFontFromOptions(options, logger);
  const GlyphFont* glyph_font_ptr = glyph_font.has_value() ? &*glyph_font : nullptr;
  const std::u32string ramp = rampFromOptions(options, glyph_font_ptr);
  std::optional<GlyphShapeTable> shape_vectors = shapeTableFromOptions(options, glyph_font_ptr);
  const TerminalSize terminal = exportTerminalSize(options);
  const ColorMode color_mode = resolveColorMode(options.color_mode, "xterm-256color", std::getenv("COLORTERM"), std::getenv("NO_COLOR"));
  const DitherMode dither_mode = ditherModeFromString(options.dither);
  SceneOverlaySource overlay_source(options);
  if (overlay_source.enabled()) {
    CONTOURTTY_LOG_INFO(logger, "overlay scene=" + overlay_source.pathString());
  }
  CellBuffer cells;
  RenderTemporalState temporal_state;
  RenderStats render_stats;
  std::optional<Frame> overlay_frame;
  const double overlay_time_seconds = static_cast<double>(options.still_at_us.value_or(frame->pts_us)) / 1000000.0;
  const Frame& render_input = frameWithOverlay(*frame, overlay_source, overlay_time_seconds, &overlay_frame);
  renderFrame(render_input, ramp, options, terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, logger.enabled() ? &render_stats : nullptr, &temporal_state);
  const RasterImage raster = rasterComposeCells(cells, color_mode, dither_mode, glyph_font_ptr);
  writePngRgb24(*options.still_file, raster.width, raster.height, raster.rgb);
  CONTOURTTY_LOG_INFO(logger, "still snapshot path=" + *options.still_file +
                                " width=" + std::to_string(raster.width) +
                                " height=" + std::to_string(raster.height));
  return 0;
}

bool isAsciinemaCastInput(std::string_view input) {
  return std::filesystem::path(std::string(input)).extension() == ".cast";
}

int playAsciinemaCast(const CliOptions& options, Logger& logger) {
  if (!options.input.has_value()) {
    throw std::runtime_error("missing input");
  }
  logGpuRequest(options, logger);

  AsciinemaFrameSource source = AsciinemaFrameSource::fromFile(*options.input);
  CONTOURTTY_LOG_INFO(logger, "asciinema cast width=" + std::to_string(source.header().width) +
                                " height=" + std::to_string(source.header().height));
  CONTOURTTY_LOG_INFO(logger, "no audio stream; using cast event pacing");

  resetQuitFlag();
  g_pending_commands.clear();
  installQuitSignalHandlers();
  installResizeSignalHandler();
  TerminalSession session;
  CONTOURTTY_LOG_INFO(logger, "playback started");

  std::optional<GlyphFont> glyph_font = glyphFontFromOptions(options, logger);
  const GlyphFont* glyph_font_ptr = glyph_font.has_value() ? &*glyph_font : nullptr;
  const std::u32string ramp = rampFromOptions(options, glyph_font_ptr);
  std::optional<GlyphShapeTable> shape_vectors = shapeTableFromOptions(options, glyph_font_ptr);
  if (shape_vectors.has_value()) {
    CONTOURTTY_LOG_INFO(logger, "shape vectors entries=" + std::to_string(shape_vectors->entries.size()) +
                                  " features=" + std::to_string(kShapeRegionCount));
  }

  TerminalSize terminal = queryTerminalSize();
  CellBuffer cells;
  DiffEmitter emitter;
  RenderTemporalState temporal_state;
  FramePacer pacer(options);
  const ColorMode color_mode = resolveColorMode(options.color_mode, std::getenv("TERM"), std::getenv("COLORTERM"), std::getenv("NO_COLOR"));
  CONTOURTTY_LOG_INFO(logger, "color mode " + std::string(colorModeName(color_mode)));
  const DitherMode dither_mode = ditherModeFromString(options.dither);
  const EmissionOptions emission_options{.color_mode = color_mode, .dither_mode = dither_mode, .diff_oklab_eps = options.diff_oklab_eps.value_or(0.0)};
  std::optional<GraphicsFrameOptions> graphics_options;
  if (options.render_mode != "text") {
    graphics_options = graphicsOptionsFromResolution(options, detectGraphicsCaps(options), color_mode, dither_mode, glyph_font_ptr, logger);
  }
  std::optional<BandwidthGuard> graphics_bandwidth;
  if (graphics_options.has_value()) {
    graphics_bandwidth.emplace(options.bandwidth_cap_mb_s);
  }
  RenderStats render_stats;
  RenderStats* render_stats_ptr = logger.enabled() ? &render_stats : nullptr;
  RuntimeDebugStats debug_stats(options, &logger);
  bool quit = false;
  bool paused = false;

  std::string clear = "\x1b[2J";
  writeAll(STDOUT_FILENO, clear);
  consumeResizeFlag();

  while (!shouldQuit()) {
    switch (pollKeyboardCommand()) {
      case PlaybackCommand::None:
        break;
      case PlaybackCommand::Quit:
        quit = true;
        break;
      case PlaybackCommand::TogglePause:
        paused = !paused;
        CONTOURTTY_LOG_INFO(logger, paused ? "playback paused" : "playback resumed");
        break;
      case PlaybackCommand::SeekBackward:
      case PlaybackCommand::SeekForward:
        break;
    }
    if (quit) {
      break;
    }
    if (paused) {
      if (!debug_stats.maybeReport(terminal)) {
        quit = true;
        break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }

    std::optional<Frame> frame = source.nextFrame();
    if (!frame.has_value()) {
      if (options.loop) {
        source.restart();
        pacer.reset();
        emitter.reset();
        if (graphics_bandwidth.has_value()) {
          graphics_bandwidth->reset();
        }
        temporal_state.reset();
        std::string clear_loop = "\x1b[2J";
        writeAll(STDOUT_FILENO, clear_loop);
        CONTOURTTY_LOG_INFO(logger, "asciinema cast loop restarted");
        continue;
      }
      break;
    }

    debug_stats.recordInputFrame();
    pacer.waitForFrame(*frame);
    if (shouldQuit()) {
      quit = true;
      break;
    }
    if (consumeResizeFlag()) {
      terminal = queryTerminalSize();
      emitter.reset();
      if (graphics_bandwidth.has_value()) {
        graphics_bandwidth->reset();
      }
      temporal_state.reset();
      std::string clear_resize = "\x1b[2J";
      writeAll(STDOUT_FILENO, clear_resize);
    }

    const TerminalSize render_terminal = debugRenderTerminal(terminal, options);
    const CliOptions render_options = debugRenderOptions(options, terminal);
    renderFrame(*frame, ramp, render_options, render_terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, render_stats_ptr, &temporal_state);
    EmissionResult emission;
    if (graphics_options.has_value()) {
      emission = EmissionResult{
        .bytes = graphicsFrameBytes(cells, *graphics_options, render_terminal),
        .changed_cells = cells.size(),
      };
      const BandwidthDecision decision = graphics_bandwidth->recordFrame(emission.bytes.size(), std::chrono::steady_clock::now());
      if (!decision.send) {
        debug_stats.recordDroppedFrame();
        if (decision.warn) {
          CONTOURTTY_LOG_WARN(logger, "graphics bandwidth cap hit; dropping frames");
        }
        if (!debug_stats.maybeReport(terminal)) {
          quit = true;
          break;
        }
        continue;
      }
    } else {
      emission = emitter.emit(cells, centeredEmissionOptions(emission_options, render_terminal, cells));
    }
    debug_stats.recordPresentedFrame(cells, emission);
    if (!emission.bytes.empty() && !writeAll(STDOUT_FILENO, emission.bytes)) {
      quit = true;
      break;
    }
    if (!debug_stats.maybeReport(terminal)) {
      quit = true;
      break;
    }
  }

  if (!quit && !shouldQuit()) {
    pacer.finish();
  }
  if (logger.enabled()) {
    const int64_t shape_match_us = render_stats.shape_match_ns / 1000;
    const double avg_shape_match_ns = render_stats.shape_match_cells > 0
                                        ? static_cast<double>(render_stats.shape_match_ns) / static_cast<double>(render_stats.shape_match_cells)
                                        : 0.0;
    CONTOURTTY_LOG_INFO(logger, "render stats frames=" + std::to_string(render_stats.frames) +
                                  " cells=" + std::to_string(render_stats.cells) +
                                  " render_us=" + std::to_string(render_stats.render_ns / 1000) +
                                  " shape_match_cells=" + std::to_string(render_stats.shape_match_cells) +
                                  " shape_match_us=" + std::to_string(shape_match_us) +
                                  " avg_shape_match_ns=" + std::to_string(avg_shape_match_ns) +
                                  " optical_flow_blocks=" + std::to_string(render_stats.optical_flow_blocks) +
                                  " optical_flow_us=" + std::to_string(render_stats.optical_flow_ns / 1000) +
                                  " warp_history_cells=" + std::to_string(render_stats.warp_history_cells) +
                                  " warp_history_us=" + std::to_string(render_stats.warp_history_ns / 1000));
  }
  return quit ? 130 : 0;
}

int playMedia(const CliOptions& options, Logger& logger) {
  if (!options.input.has_value()) {
    throw std::runtime_error("missing input");
  }
  if (isAsciinemaCastInput(*options.input)) {
    return playAsciinemaCast(options, logger);
  }
  logGpuRequest(options, logger);

  std::optional<DecodedAudio> decoded_audio;
  const bool camera_input = isCameraInput(*options.input);
  const bool remote_input = isUrlInput(*options.input);
  const bool mirror_camera = camera_input && options.mirror;
  if (camera_input) {
    CONTOURTTY_LOG_INFO(logger, "no audio stream; using wall-clock pacing");
    CONTOURTTY_LOG_INFO(logger, mirror_camera ? "camera mirror enabled" : "camera mirror disabled");
  } else if (remote_input) {
    CONTOURTTY_LOG_INFO(logger, "remote audio predecode skipped; using wall-clock pacing");
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

  std::optional<GlyphFont> glyph_font = glyphFontFromOptions(options, logger);
  const GlyphFont* glyph_font_ptr = glyph_font.has_value() ? &*glyph_font : nullptr;
  const std::u32string ramp = rampFromOptions(options, glyph_font_ptr);
  std::optional<GlyphShapeTable> shape_vectors = shapeTableFromOptions(options, glyph_font_ptr);
  if (shape_vectors.has_value()) {
    CONTOURTTY_LOG_INFO(logger, "shape vectors entries=" + std::to_string(shape_vectors->entries.size()) +
                                  " features=" + std::to_string(kShapeRegionCount));
  }

  TerminalSize terminal = queryTerminalSize();
  VideoDecoder video_decoder(*options.input);
  CellBuffer cells;
  DiffEmitter emitter;
  RenderTemporalState temporal_state;
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
  const DitherMode dither_mode = ditherModeFromString(options.dither);
  const EmissionOptions emission_options{.color_mode = color_mode, .dither_mode = dither_mode, .diff_oklab_eps = options.diff_oklab_eps.value_or(0.0)};
  std::optional<GraphicsFrameOptions> graphics_options;
  if (options.render_mode != "text") {
    graphics_options = graphicsOptionsFromResolution(options, detectGraphicsCaps(options), color_mode, dither_mode, glyph_font_ptr, logger);
  }
  std::optional<BandwidthGuard> graphics_bandwidth;
  if (graphics_options.has_value()) {
    graphics_bandwidth.emplace(options.bandwidth_cap_mb_s);
  }
  SceneOverlaySource overlay_source(options);
  if (overlay_source.enabled()) {
    CONTOURTTY_LOG_INFO(logger, "overlay scene=" + overlay_source.pathString());
  }
  DriftStats drift_stats;
  RenderStats render_stats;
  RenderStats* render_stats_ptr = logger.enabled() ? &render_stats : nullptr;
  RuntimeDebugStats debug_stats(options, &logger);
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
    if (graphics_bandwidth.has_value()) {
      graphics_bandwidth->reset();
    }
    temporal_state.reset();
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
      if (!debug_stats.maybeReport(terminal)) {
        quit = true;
        break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }
    if (audio_player == nullptr && paused_without_audio) {
      if (!debug_stats.maybeReport(terminal)) {
        quit = true;
        break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }

    auto frame = video_decoder.nextFrame();
    if (!frame.has_value()) {
      if (video_decoder.isAnimatedImage()) {
        video_decoder.restart();
        pacer.reset();
        emitter.reset();
        if (graphics_bandwidth.has_value()) {
          graphics_bandwidth->reset();
        }
        temporal_state.reset();
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
        if (graphics_bandwidth.has_value()) {
          graphics_bandwidth->reset();
        }
        temporal_state.reset();
        std::string clear_loop = "\x1b[2J";
        writeAll(STDOUT_FILENO, clear_loop);
        CONTOURTTY_LOG_INFO(logger, "input loop restarted");
        continue;
      }
      if (video_decoder.isStillImage() && still_frame.has_value()) {
        quit = holdStillFrame(*still_frame, ramp, options, &terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, &emitter, emission_options, render_stats_ptr, &debug_stats);
      }
      break;
    }
    debug_stats.recordInputFrame();
    if (mirror_camera) {
      mirrorFrameHorizontally(*frame);
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
        debug_stats.recordDroppedFrame();
        if (!debug_stats.maybeReport(terminal)) {
          quit = true;
          break;
        }
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
      if (graphics_bandwidth.has_value()) {
        graphics_bandwidth->reset();
      }
      temporal_state.reset();
      std::string clear_resize = "\x1b[2J";
      writeAll(STDOUT_FILENO, clear_resize);
    }

    const TerminalSize render_terminal = debugRenderTerminal(terminal, options);
    const CliOptions render_options = debugRenderOptions(options, terminal);
    if (audio_sync.first_video_pts_us >= 0) {
      current_video_us = frameMediaUs(*frame, audio_sync.first_video_pts_us);
    } else {
      current_video_us = frame->pts_us;
    }
    std::optional<Frame> overlay_frame;
    const Frame& render_input = frameWithOverlay(*frame, overlay_source, static_cast<double>(current_video_us) / 1000000.0, &overlay_frame);
    renderFrame(render_input, ramp, render_options, render_terminal, shape_vectors.has_value() ? &*shape_vectors : nullptr, &cells, render_stats_ptr, &temporal_state);
    if (video_decoder.isStillImage()) {
      still_frame = *frame;
    }
    EmissionResult emission;
    if (graphics_options.has_value()) {
      emission = EmissionResult{
        .bytes = graphicsFrameBytes(cells, *graphics_options, render_terminal),
        .changed_cells = cells.size(),
      };
      const BandwidthDecision decision = graphics_bandwidth->recordFrame(emission.bytes.size(), std::chrono::steady_clock::now());
      if (!decision.send) {
        debug_stats.recordDroppedFrame();
        if (decision.warn) {
          CONTOURTTY_LOG_WARN(logger, "graphics bandwidth cap hit; dropping frames");
        }
        if (!debug_stats.maybeReport(terminal)) {
          quit = true;
          break;
        }
        continue;
      }
    } else {
      emission = emitter.emit(cells, centeredEmissionOptions(emission_options, render_terminal, cells));
    }
    debug_stats.recordPresentedFrame(cells, emission);
    if (!emission.bytes.empty() && !writeAll(STDOUT_FILENO, emission.bytes)) {
      quit = true;
      break;
    }
    if (!debug_stats.maybeReport(terminal)) {
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
                                  " avg_shape_match_ns=" + std::to_string(avg_shape_match_ns) +
                                  " optical_flow_blocks=" + std::to_string(render_stats.optical_flow_blocks) +
                                  " optical_flow_us=" + std::to_string(render_stats.optical_flow_ns / 1000) +
                                  " warp_history_cells=" + std::to_string(render_stats.warp_history_cells) +
                                  " warp_history_us=" + std::to_string(render_stats.warp_history_ns / 1000));
  }
  (void)debug_stats.maybeReport(terminal, true);
  if (quit || shouldQuit()) {
    CONTOURTTY_LOG_INFO(logger, "playback quit before eof");
  } else {
    CONTOURTTY_LOG_INFO(logger, "playback reached eof");
  }
  if (graphics_options.has_value() && graphics_options->protocol == GraphicsProtocol::Kitty) {
    (void)writeAll(STDOUT_FILENO, deleteKittyImage(graphics_options->image_id, graphics_options->placement_id));
  }
  return 0;
}

}  // namespace contourtty
