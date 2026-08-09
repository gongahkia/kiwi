#pragma once

#include <filesystem>
#include <memory>
#include <string_view>

namespace strok {

class MetricsJsonlWriter {
public:
  explicit MetricsJsonlWriter(const std::filesystem::path &path);

  bool write(std::string_view line) noexcept;

private:
  struct State;
  std::shared_ptr<State> state_;
};

} // namespace strok
