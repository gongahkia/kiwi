#pragma once

#include <cstdint>
#include <vector>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
struct Frame {
  int w = 0;
  int h = 0;
  std::vector<uint8_t> rgb;
  int64_t pts_us = 0;
};

}  // namespace strok
