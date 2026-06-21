#include "base64.hpp"
#include "iterm_inline.hpp"
#include "png_writer.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

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
    const std::vector<uint8_t> png = contourtty::encodePngRgb24(1, 1, std::vector<uint8_t>{255, 0, 0});
    const std::string escape = contourtty::encodeITermInlinePng(png, contourtty::ITermInlineOptions{
      .name = "red.png",
      .width = "1px",
      .height = "1px",
    });
    const std::string expected_prefix = "\x1b]1337;File=inline=1;name=cmVkLnBuZw==;size=" + std::to_string(png.size()) +
                                        ";width=1px;height=1px;preserveAspectRatio=0:";
    expect(escape.rfind(expected_prefix, 0) == 0, "iTerm inline prefix");
    expect(escape.ends_with("\a"), "iTerm inline BEL terminator");
    expect(escape.substr(expected_prefix.size(), escape.size() - expected_prefix.size() - 1U) == contourtty::base64Encode(png), "iTerm inline PNG payload");
  }

  {
    const contourtty::RasterImage image{
      .width = 1,
      .height = 1,
      .rgb = {0, 255, 0},
    };
    const std::string escape = contourtty::encodeITermInlineRgb24(image, contourtty::ITermInlineOptions{
      .height = "auto",
      .preserve_aspect_ratio = true,
      .use_st_terminator = true,
    });
    expect(escape.find("height=auto") != std::string::npos, "iTerm inline auto height");
    expect(escape.find("preserveAspectRatio=0") == std::string::npos, "iTerm inline preserve aspect");
    expect(escape.ends_with("\x1b\\"), "iTerm inline ST terminator");
  }

  {
    bool threw = false;
    try {
      (void)contourtty::encodeITermInlinePng({}, {});
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "empty iTerm payload rejected");
  }

  {
    bool threw = false;
    try {
      (void)contourtty::encodeITermInlinePng(std::vector<uint8_t>{1}, contourtty::ITermInlineOptions{.width = "1;bad"});
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "invalid iTerm dimension rejected");
  }
}
