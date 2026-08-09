#pragma once

#include "raster.hpp"

#include <cstddef>
#include <optional>
#include <string>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
struct EmissionResult {
  std::string bytes;
  std::size_t changed_cells = 0;
};

struct EmissionOptions {
  ColorMode color_mode = ColorMode::Truecolor;
  DitherMode dither_mode = DitherMode::None;
  double diff_oklab_eps = 0.0;
  int origin_row = 1;
  int origin_col = 1;
};

// Owns prior CellBuffer and terminal style state for one output stream. emit()
// returns an owning byte string and does not retain the caller's CellBuffer.
// reset() drops all remembered state; the next emit() repaints its full input.
class DiffEmitter {
 public:
  EmissionResult emit(const CellBuffer& current, EmissionOptions options = {});
  void reset();

 private:
  CellBuffer previous_;
  std::optional<EmissionOptions> previous_options_;
  bool has_previous_ = false;
};

}  // namespace strok
