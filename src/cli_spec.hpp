#pragma once

#include <span>
#include <string_view>

namespace contourtty {

struct CliOptionSpec {
  std::string_view syntax;
  std::string_view description;
};

std::span<const CliOptionSpec> cliOptionSpecs() noexcept;

}  // namespace contourtty
