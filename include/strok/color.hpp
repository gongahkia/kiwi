#pragma once

#include <cstdint>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
struct Rgb {
  uint8_t r = 0;
  uint8_t g = 0;
  uint8_t b = 0;

  bool operator==(const Rgb&) const = default;
};

}  // namespace strok
