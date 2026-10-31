#pragma once

#include <algorithm>
#include <cstdlib>
#include <optional>

namespace strok {

inline std::optional<int> configuredWorkerLimit() {
  const char* value = std::getenv("STROK_WORKERS");
  if (value == nullptr || *value == '\0') {
    return std::nullopt;
  }
  char* end = nullptr;
  const long parsed = std::strtol(value, &end, 10);
  if (end == value || *end != '\0' || parsed < 1) {
    return std::nullopt;
  }
  return static_cast<int>(std::min<long>(parsed, 1024));
}

inline int boundedWorkerCount(int fallback) {
#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
  // The browser frontend already runs in a dedicated Web Worker. A serial core
  // needs no SharedArrayBuffer or cross-origin isolation headers on static hosts.
  (void)fallback;
  return 1;
#else
  const std::optional<int> configured = configuredWorkerLimit();
  if (!configured.has_value()) {
    return fallback;
  }
  return std::max(1, std::min(fallback, *configured));
#endif
}

}  // namespace strok
