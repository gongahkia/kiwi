#pragma once

#include "cell_buffer.hpp"
#include "color_mode.hpp"
#include "color_quantization.hpp"

#include <cstddef>
#include <optional>
#include <string>

namespace strok {

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
