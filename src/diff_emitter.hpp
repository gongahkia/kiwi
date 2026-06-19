#pragma once

#include "cell_buffer.hpp"

#include <cstddef>
#include <string>

namespace contourtty {

struct EmissionResult {
  std::string bytes;
  std::size_t changed_cells = 0;
};

class DiffEmitter {
 public:
  EmissionResult emit(const CellBuffer& current);
  void reset();

 private:
  CellBuffer previous_;
  bool has_previous_ = false;
};

}  // namespace contourtty
