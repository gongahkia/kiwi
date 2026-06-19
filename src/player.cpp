#include "player.hpp"

#include "audio_backend.hpp"
#include "audio_decode.hpp"
#include "cell_buffer.hpp"
#include "diff_emitter.hpp"
#include "glyph_ramp.hpp"
#include "glyph_shape.hpp"
#include "luminance.hpp"
#include "structure_edges.hpp"
#include "structure_sampling.hpp"
#include "terminal.hpp"
#include "video_decoder.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <sys/select.h>
#include <thread>
#include <unistd.h>

namespace contourtty {
namespace {

struct RenderSize {
  int cols = 0;
  int rows = 0;
};

constexpr double kDefaultDogThreshold = 0.02;
constexpr double kDefaultEdgeThreshold = 0.35;
constexpr double kDefaultEdgeStrength = 1.0;

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

struct RenderStats {
  int64_t frames = 0;
  int64_t cells = 0;
  int64_t render_ns = 0;
  int64_t shape_match_cells = 0;
  int64_t shape_match_ns = 0;
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

RenderSize fitRenderSize(const Frame& frame, const CliOptions& options, TerminalSize terminal) {
  const int max_cols = std::max(1, options.width.value_or(terminal.cols));
  const int max_rows = std::max(1, options.height.value_or(terminal.rows));
  const double img_aspect = static_cast<double>(frame.w) / static_cast<double>(frame.h);
  const auto rows_for_cols = [&](int cols) {
    return std::max(1, static_cast<int>(std::llround(static_cast<double>(cols) * (1.0 / img_aspect) * options.cell_aspect)));
  };
  const auto cols_for_rows = [&](int rows) {
    return std::max(1, static_cast<int>(std::llround(static_cast<double>(rows) * img_aspect / options.cell_aspect)));
  };

  const int rows = rows_for_cols(max_cols);
  if (rows <= max_rows) {
    return RenderSize{.cols = max_cols, .rows = rows};
  }
  return RenderSize{.cols = cols_for_rows(max_rows), .rows = max_rows};
}

Rgb averageRegion(const Frame& frame, int cols, int rows, int col, int row) {
  const int x0 = (col * frame.w) / cols;
  const int x1 = std::max(x0 + 1, ((col + 1) * frame.w) / cols);
  const int y0 = (row * frame.h) / rows;
  const int y1 = std::max(y0 + 1, ((row + 1) * frame.h) / rows);

  uint64_t r = 0;
  uint64_t g = 0;
  uint64_t b = 0;
  uint64_t count = 0;
  for (int y = y0; y < y1; ++y) {
    for (int x = x0; x < x1; ++x) {
      const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(x)) * 3;
      r += frame.rgb[index];
      g += frame.rgb[index + 1];
      b += frame.rgb[index + 2];
      ++count;
    }
  }

  return Rgb{
    .r = static_cast<uint8_t>(r / count),
    .g = static_cast<uint8_t>(g / count),
    .b = static_cast<uint8_t>(b / count),
  };
}

DogOptions dogOptionsFromCli(const CliOptions& options) {
  const double sigma1 = options.dog_sigma.value_or(0.0);
  return DogOptions{
    .sigma1 = sigma1,
    .sigma2 = options.dog_sigma2.value_or(sigma1 > 0.0 ? sigma1 * 2.0 : 0.0),
    .threshold = options.dog_threshold.value_or(kDefaultDogThreshold),
  };
}

double contrastFromCli(const CliOptions& options) {
  return options.contrast.value_or(0.0);
}

double edgeThresholdFromCli(const CliOptions& options) {
  return options.edge_threshold.value_or(kDefaultEdgeThreshold);
}

double effectiveEdgeThresholdFromCli(const CliOptions& options) {
  const double strength = options.edge_strength.value_or(kDefaultEdgeStrength);
  if (strength <= 0.0) {
    return std::numeric_limits<double>::infinity();
  }
  return edgeThresholdFromCli(options) / strength;
}

void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats) {
  const auto render_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
  const RenderSize size = fitRenderSize(frame, options, terminal);
  cells->resize(size.cols, size.rows);
  if (stats != nullptr) {
    ++stats->frames;
    stats->cells += static_cast<int64_t>(size.cols) * static_cast<int64_t>(size.rows);
  }
  std::optional<GradientField> structure_gradients;
  std::optional<LuminanceField> structure_ink;
  const double edge_threshold = effectiveEdgeThresholdFromCli(options);
  if (options.mode == "structure") {
    LuminanceField analysis_luminance = makeLuminanceField(frame);
    analysis_luminance = applyStructureContrast(analysis_luminance, contrastFromCli(options));
    const DogOptions dog_options = dogOptionsFromCli(options);
    if (dog_options.enabled()) {
      analysis_luminance = differenceOfGaussians(analysis_luminance, dog_options);
    }
    structure_gradients = computeSobelGradients(analysis_luminance);
    structure_ink = gradientMagnitudeField(*structure_gradients, edge_threshold);
  }
  for (int row = 0; row < size.rows; ++row) {
    for (int col = 0; col < size.cols; ++col) {
      const Rgb avg = averageRegion(frame, size.cols, size.rows, col, row);
      Cell& cell = cells->at(col, row);
      cell.glyph = glyphForLuminance(relativeLuminance(avg), ramp);
      if (structure_gradients.has_value()) {
        const CellGradient gradient = cellGradient(*structure_gradients, size.cols, size.rows, col, row);
        const std::optional<char32_t> edge_glyph = directionalGlyphForGradient(gradient, edge_threshold);
        if (edge_glyph.has_value()) {
          if (shape_table != nullptr && structure_ink.has_value()) {
            const auto match_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
            const CellLuminanceRegion region = sampleCellRegion(*structure_ink, size.cols, size.rows, col, row);
            cell.glyph = matchGlyphShape(shapeVectorForCell(region), *shape_table);
            if (stats != nullptr) {
              ++stats->shape_match_cells;
              stats->shape_match_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - match_started).count();
            }
          } else {
            cell.glyph = *edge_glyph;
          }
        }
      }
      cell.fg = avg;
      cell.bg = Rgb{};
    }
  }
  if (stats != nullptr) {
    stats->render_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - render_started).count();
  }
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

bool renderStillResize(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize* terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, DiffEmitter* emitter, const EmissionOptions& emission_options, RenderStats* render_stats) {
  *terminal = queryTerminalSize();
  emitter->reset();
  std::string clear = "\x1b[2J";
  if (!writeAll(STDOUT_FILENO, clear)) {
    return false;
  }
  renderFrame(frame, ramp, options, *terminal, shape_table, cells, render_stats);
  const EmissionResult emission = emitter->emit(*cells, emission_options);
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

}  // namespace

int playMedia(const CliOptions& options, Logger& logger) {
  if (!options.input.has_value()) {
    throw std::runtime_error("missing input");
  }

  std::optional<DecodedAudio> decoded_audio;
  try {
    decoded_audio = decodeAudioFile(*options.input);
    CONTOURTTY_LOG_INFO(logger, "audio decoded frames=" + std::to_string(decoded_audio->decoded_frames) +
                                  " duration_us=" + std::to_string(decoded_audio->duration_us));
  } catch (const NoAudioStreamError&) {
    CONTOURTTY_LOG_INFO(logger, "no audio stream; using wall-clock pacing");
  }

  resetQuitFlag();
  g_pending_commands.clear();
  installQuitSignalHandlers();
  installResizeSignalHandler();
  TerminalSession session;
  CONTOURTTY_LOG_INFO(logger, "playback started");

  std::u32string ramp = kDefaultGlyphRamp.data();
  if (options.charset.has_value()) {
    ramp = decodeCharset(*options.charset);
  }
  std::optional<GlyphShapeTable> shape_vectors;
  if (options.mode == "structure") {
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
  const EmissionOptions emission_options{.mono = options.color_mode == "mono"};
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
    const EmissionResult emission = emitter.emit(cells, emission_options);
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
