#include "player.hpp"

#include "cell_buffer.hpp"
#include "diff_emitter.hpp"
#include "glyph_ramp.hpp"
#include "luminance.hpp"
#include "media_probe.hpp"
#include "terminal.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdint>
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

void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, CellBuffer* cells) {
  const RenderSize size = fitRenderSize(frame, options, terminal);
  cells->resize(size.cols, size.rows);
  for (int row = 0; row < size.rows; ++row) {
    for (int col = 0; col < size.cols; ++col) {
      const Rgb avg = averageRegion(frame, size.cols, size.rows, col, row);
      Cell& cell = cells->at(col, row);
      cell.glyph = glyphForLuminance(relativeLuminance(avg), ramp);
      cell.fg = avg;
      cell.bg = Rgb{};
    }
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

bool keyboardQuitRequested() {
  fd_set read_set;
  FD_ZERO(&read_set);
  FD_SET(STDIN_FILENO, &read_set);
  timeval timeout {};
  const int ready = select(STDIN_FILENO + 1, &read_set, nullptr, nullptr, &timeout);
  if (ready <= 0 || !FD_ISSET(STDIN_FILENO, &read_set)) {
    return false;
  }

  char buffer[16] {};
  const ssize_t n = ::read(STDIN_FILENO, buffer, sizeof(buffer));
  if (n <= 0) {
    return false;
  }
  for (ssize_t i = 0; i < n; ++i) {
    if (buffer[i] == 'q' || buffer[i] == 'Q') {
      return true;
    }
  }
  return false;
}

}  // namespace

int playMedia(const CliOptions& options, Logger& logger) {
  if (!options.input.has_value()) {
    throw std::runtime_error("missing input");
  }

  resetQuitFlag();
  installQuitSignalHandlers();
  installResizeSignalHandler();
  TerminalSession session;
  CONTOURTTY_LOG_INFO(logger, "playback started");

  std::u32string ramp = kDefaultGlyphRamp.data();
  if (options.charset.has_value()) {
    ramp = decodeCharset(*options.charset);
  }

  TerminalSize terminal = queryTerminalSize();
  CellBuffer cells;
  DiffEmitter emitter;
  FramePacer pacer(options);
  const EmissionOptions emission_options{.mono = options.color_mode == "mono"};
  bool quit = false;

  std::string clear = "\x1b[2J";
  writeAll(STDOUT_FILENO, clear);
  consumeResizeFlag();

  MediaProbeOptions decode_options;
  decode_options.cell_aspect = options.cell_aspect;
  decode_options.on_frame = [&](const Frame& frame, int64_t) {
    if (shouldQuit() || keyboardQuitRequested()) {
      quit = true;
      return false;
    }
    pacer.waitForFrame(frame);
    if (shouldQuit() || keyboardQuitRequested()) {
      quit = true;
      return false;
    }
    if (consumeResizeFlag()) {
      terminal = queryTerminalSize();
      emitter.reset();
      std::string clear_resize = "\x1b[2J";
      writeAll(STDOUT_FILENO, clear_resize);
    }

    renderFrame(frame, ramp, options, terminal, &cells);
    const EmissionResult emission = emitter.emit(cells, emission_options);
    if (!emission.bytes.empty() && !writeAll(STDOUT_FILENO, emission.bytes)) {
      quit = true;
      return false;
    }
    return !shouldQuit();
  };

  (void)probeMedia(*options.input, decode_options);
  if (!quit && !shouldQuit()) {
    pacer.finish();
  }
  if (quit || shouldQuit()) {
    CONTOURTTY_LOG_INFO(logger, "playback quit before eof");
  } else {
    CONTOURTTY_LOG_INFO(logger, "playback reached eof");
  }
  return 0;
}

}  // namespace contourtty
