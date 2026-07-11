#pragma once

#include "asciinema_in.hpp"
#include "asciinema_vte.hpp"
#include "frame.hpp"

#include <filesystem>
#include <optional>
#include <string_view>
#include <vector>

namespace strok {

class AsciinemaFrameSource {
 public:
  static AsciinemaFrameSource fromString(std::string_view text);
  static AsciinemaFrameSource fromFile(const std::filesystem::path& path);

  const AsciinemaHeader& header() const noexcept;
  std::optional<Frame> nextFrame();
  void restart();

 private:
  AsciinemaFrameSource(AsciinemaHeader header, std::vector<AsciinemaEvent> events);

  AsciinemaHeader header_;
  std::vector<AsciinemaEvent> events_;
  AsciinemaVteScreen screen_;
  std::size_t next_event_ = 0;
};

Frame asciinemaCellsToFrame(const CellBuffer& cells, int64_t pts_us);

}  // namespace strok
