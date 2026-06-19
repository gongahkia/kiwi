#pragma once

#include "cell_buffer.hpp"
#include "color_mode.hpp"

#include <cstddef>
#include <string>

namespace contourtty {

struct EmissionResult {
  std::string bytes;
  std::size_t changed_cells = 0;
};

struct EmissionOptions {
  ColorMode color_mode = ColorMode::Truecolor;
};

class DiffEmitter {
 public:
  EmissionResult emit(const CellBuffer& current, EmissionOptions options = {});
  void reset();

 private:
  CellBuffer previous_;
  bool has_previous_ = false;
};

}  // namespace contourtty
