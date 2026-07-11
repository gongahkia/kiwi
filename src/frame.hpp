#pragma once

#include <cstdint>
#include <vector>

namespace strok {

struct Frame {
  int w = 0;
  int h = 0;
  std::vector<uint8_t> rgb;
  int64_t pts_us = 0;
};

}  // namespace strok
