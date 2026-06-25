#include "sixel.hpp"

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
    const std::vector<uint8_t> rgb {
      255, 0, 0,
      0, 0, 255,
      255, 0, 0,
      0, 0, 255,
      255, 0, 0,
      0, 0, 255,
      255, 0, 0,
      0, 0, 255,
      255, 0, 0,
      0, 0, 255,
      255, 0, 0,
      0, 0, 255,
    };
    const contourtty::SixelImage image = contourtty::quantizeSixelOklab(rgb, 2, 6);
    expect(image.width == 2 && image.height == 6, "sixel quantized dimensions");
    expect(image.palette_indices[0] == 9, "red maps to xterm bright red by OKLab nearest");
    expect(image.palette_indices[1] == 12, "blue maps to xterm bright blue by OKLab nearest");

    const std::string encoded = contourtty::encodeSixelRgb24(rgb, 2, 6);
    expect(encoded.starts_with("\x1bPq"), "sixel DCS prefix");
    expect(encoded.find("#9;2;100;0;0") != std::string::npos, "sixel red palette");
    expect(encoded.find("#12;2;0;0;100") != std::string::npos, "sixel blue palette");
    expect(encoded.find("#9~?") != std::string::npos, "sixel red alternating column");
    expect(encoded.find("#12?~") != std::string::npos, "sixel blue alternating column");
    expect(encoded.ends_with("\x1b\\"), "sixel ST suffix");
  }

  {
    bool threw = false;
    try {
      (void)contourtty::encodeSixelRgb24(std::vector<uint8_t>{255, 0, 0}, 2, 1);
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "sixel rejects size mismatch");
  }
}
