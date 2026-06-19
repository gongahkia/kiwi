#pragma once

#include <string>
#include <string_view>

namespace contourtty {

bool isUrlInput(std::string_view input) noexcept;
bool requiresYtDlp(std::string_view input) noexcept;
std::string resolveMediaInput(std::string_view input);

}  // namespace contourtty
