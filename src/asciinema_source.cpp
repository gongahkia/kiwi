#include "asciinema_source.hpp"

#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>

namespace strok {
namespace {

bool sameRgb(Rgb lhs, Rgb rhs) noexcept {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

Rgb visibleCellColor(const Cell& cell) noexcept {
  if (cell.glyph == U' ') {
    return cell.bg;
  }
  if (sameRgb(cell.fg, Rgb{}) && sameRgb(cell.bg, Rgb{})) {
    return Rgb{.r = 255, .g = 255, .b = 255};
  }
  return cell.fg;
}

std::string readFileToString(const std::filesystem::path& path) {
  std::ifstream input(path);
  if (!input) {
    throw std::runtime_error("failed to open asciinema cast: " + path.string());
  }
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

std::string_view stripTrailingCr(std::string_view line) noexcept {
  if (!line.empty() && line.back() == '\r') {
    line.remove_suffix(1);
  }
  return line;
}

}  // namespace

AsciinemaFrameSource::AsciinemaFrameSource(AsciinemaHeader header, std::vector<AsciinemaEvent> events)
  : header_(header), events_(std::move(events)), screen_(header_.width, header_.height) {}

AsciinemaFrameSource AsciinemaFrameSource::fromString(std::string_view text) {
  const std::size_t first_newline = text.find('\n');
  if (first_newline == std::string_view::npos) {
    throw std::invalid_argument("asciinema cast missing event stream");
  }
  const AsciinemaHeader header = parseAsciinemaHeader(stripTrailingCr(text.substr(0, first_newline)));
  std::vector<AsciinemaEvent> events;
  std::size_t line_start = first_newline + 1;
  while (line_start <= text.size()) {
    const std::size_t line_end = text.find('\n', line_start);
    const std::size_t end = line_end == std::string_view::npos ? text.size() : line_end;
    const std::string_view line = stripTrailingCr(text.substr(line_start, end - line_start));
    if (!line.empty()) {
      AsciinemaEvent event = parseAsciinemaEvent(line);
      if (event.type == "o") {
        events.push_back(std::move(event));
      }
    }
    if (line_end == std::string_view::npos) {
      break;
    }
    line_start = line_end + 1;
  }
  return AsciinemaFrameSource(header, std::move(events));
}

AsciinemaFrameSource AsciinemaFrameSource::fromFile(const std::filesystem::path& path) {
  return fromString(readFileToString(path));
}

const AsciinemaHeader& AsciinemaFrameSource::header() const noexcept {
  return header_;
}

std::optional<Frame> AsciinemaFrameSource::nextFrame() {
  if (next_event_ >= events_.size()) {
    return std::nullopt;
  }
  const AsciinemaEvent& event = events_[next_event_++];
  screen_.applyOutput(event.data);
  const int64_t pts_us = static_cast<int64_t>(std::llround(event.time * 1000000.0));
  return asciinemaCellsToFrame(screen_.cells(), pts_us);
}

void AsciinemaFrameSource::restart() {
  next_event_ = 0;
  screen_ = AsciinemaVteScreen(header_.width, header_.height);
}

Frame asciinemaCellsToFrame(const CellBuffer& cells, int64_t pts_us) {
  Frame frame;
  frame.w = cells.cols();
  frame.h = cells.rows() * 2;
  frame.pts_us = pts_us;
  frame.rgb.resize(static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h) * 3U);
  for (int row = 0; row < cells.rows(); ++row) {
    for (int col = 0; col < cells.cols(); ++col) {
      const Rgb color = visibleCellColor(cells.at(col, row));
      for (int y_repeat = 0; y_repeat < 2; ++y_repeat) {
        const std::size_t offset = (static_cast<std::size_t>(row * 2 + y_repeat) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(col)) * 3U;
        frame.rgb[offset] = color.r;
        frame.rgb[offset + 1] = color.g;
        frame.rgb[offset + 2] = color.b;
      }
    }
  }
  return frame;
}

}  // namespace strok
