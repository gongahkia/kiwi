#pragma once

#include <string>
#include <string_view>

namespace contourtty {

struct AsciinemaHeader {
  int version = 0;
  int width = 0;
  int height = 0;
};

struct AsciinemaEvent {
  double time = 0.0;
  std::string type;
  std::string data;
};

AsciinemaHeader parseAsciinemaHeader(std::string_view line);
AsciinemaEvent parseAsciinemaEvent(std::string_view line);

}  // namespace contourtty
