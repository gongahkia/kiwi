#include "asciinema_in.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  {
    const strok::AsciinemaHeader header = strok::parseAsciinemaHeader(R"({"version":2,"width":80,"height":24,"timestamp":1})");
    expect(header.version == 2, "header version");
    expect(header.width == 80, "header width");
    expect(header.height == 24, "header height");
  }

  {
    const strok::AsciinemaEvent event = strok::parseAsciinemaEvent(R"([1.250000,"o","hello\n\u001b?"])");
    expect(event.time == 1.25, "event time");
    expect(event.type == "o", "event type");
    expect(event.data == "hello\n\x1b?", "event data escapes");
  }

  {
    bool threw = false;
    try {
      (void)strok::parseAsciinemaHeader(R"({"version":1,"width":80,"height":24})");
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "unsupported version rejected");
  }

  {
    bool threw = false;
    try {
      (void)strok::parseAsciinemaEvent(R"([0,"o","unterminated])");
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "bad event rejected");
  }
}
