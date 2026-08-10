#include "asciinema_in.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

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
    const strok::AsciinemaHeader header = strok::parseAsciinemaHeader(
      R"({"version":2,"width":80,"height":24,"metadata":{"env":{"TERM":"xterm"}},"duration":1.5})");
    expect(header.width == 80 && header.height == 24, "unknown JSON header fields parse");
    const strok::AsciinemaEvent event = strok::parseAsciinemaEvent(R"([0,"o","\u00e9\ud83d\ude00"])");
    expect(event.data == "\xc3\xa9\xf0\x9f\x98\x80", "unicode escapes decode to UTF-8 scalars");
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

  {
    const char* invalid_headers[] = {
      R"({"version":2,"version":2,"width":80,"height":24})",
      R"({"version":2,"width":80})",
      R"({"version":2,"width":1e100,"height":24})",
      R"({"version":2,"width":80.5,"height":24})",
    };
    for (const char* header : invalid_headers) {
      bool threw = false;
      try {
        (void)strok::parseAsciinemaHeader(header);
      } catch (const std::invalid_argument&) {
        threw = true;
      }
      expect(threw, "invalid asciinema header rejected");
    }
  }

  {
    const char* invalid_events[] = {
      R"([nan,"o","x"])",
      R"([inf,"o","x"])",
      R"([-1,"o","x"])",
      R"([1e100,"o","x"])",
      R"([9223372036855,"o","x"])",
      R"([0,"o","\ud83d"])",
      R"([0,"o","\ude00"])",
      R"([0,"o","\ud83d\u0041"])",
      "[0,\"o\",\"" "\xc0\x80" "\"]",
      "[0,\"o\",\"line\nbreak\"]",
    };
    for (const char* event : invalid_events) {
      bool threw = false;
      try {
        (void)strok::parseAsciinemaEvent(event);
      } catch (const std::invalid_argument&) {
        threw = true;
      }
      expect(threw, "invalid asciinema event rejected");
    }
  }
}
