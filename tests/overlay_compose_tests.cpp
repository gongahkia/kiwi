#include "overlay_compose.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>
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
    contourtty::Frame base{
      .w = 2,
      .h = 1,
      .rgb = {0, 0, 0, 10, 20, 30},
      .pts_us = 123,
    };
    contourtty::SceneGBuffer overlay;
    overlay.albedo = contourtty::Frame{.w = 2, .h = 1, .rgb = {255, 0, 0, 0, 255, 0}};
    overlay.depth = {0.5, std::numeric_limits<double>::infinity()};

    const contourtty::Frame output = contourtty::composeDepthOverlay(base, overlay, contourtty::DepthOverlayOptions{.alpha = 0.5, .depth_threshold = 1.0});
    expect(output.pts_us == 123, "overlay preserves pts");
    expect(output.rgb[0] == 128 && output.rgb[1] == 0 && output.rgb[2] == 0, "finite depth blends");
    expect(output.rgb[3] == 10 && output.rgb[4] == 20 && output.rgb[5] == 30, "infinite depth skips");
  }

  {
    contourtty::Frame base{.w = 1, .h = 1, .rgb = {10, 10, 10}};
    contourtty::SceneGBuffer overlay;
    overlay.albedo = contourtty::Frame{.w = 1, .h = 1, .rgb = {250, 250, 250}};
    overlay.depth = {2.0};
    const contourtty::Frame output = contourtty::composeDepthOverlay(base, overlay, contourtty::DepthOverlayOptions{.alpha = 1.0, .depth_threshold = 1.0});
    expect(output.rgb[0] == 10, "depth threshold rejects far overlay");
  }

  {
    bool threw = false;
    try {
      contourtty::Frame base{.w = 1, .h = 1, .rgb = {0, 0, 0}};
      contourtty::SceneGBuffer overlay;
      overlay.albedo = contourtty::Frame{.w = 2, .h = 1, .rgb = {0, 0, 0, 0, 0, 0}};
      overlay.depth = {0.0, 0.0};
      (void)contourtty::composeDepthOverlay(base, overlay);
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "dimension mismatch rejected");
  }
}
