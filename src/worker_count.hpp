#pragma once

#include <algorithm>
#include <cstdlib>
#include <optional>

namespace contourtty {

inline std::optional<int> configuredWorkerLimit() {
  const char* value = std::getenv("CONTOURTTY_WORKERS");
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
  const std::optional<int> configured = configuredWorkerLimit();
  if (!configured.has_value()) {
    return fallback;
  }
  return std::max(1, std::min(fallback, *configured));
}

}  // namespace contourtty
