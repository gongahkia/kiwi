#pragma once

#include <span>
#include <string_view>

namespace strok {

struct CliOptionSpec {
  std::string_view syntax;
  std::string_view description;
};

std::span<const CliOptionSpec> cliOptionSpecs() noexcept;

}  // namespace strok
