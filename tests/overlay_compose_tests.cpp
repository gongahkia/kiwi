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
    strok::Frame base{
      .w = 2,
      .h = 1,
      .rgb = {0, 0, 0, 10, 20, 30},
      .pts_us = 123,
    };
    strok::SceneGBuffer overlay;
    overlay.albedo = strok::Frame{.w = 2, .h = 1, .rgb = {255, 0, 0, 0, 255, 0}};
    overlay.depth = {0.5, std::numeric_limits<double>::infinity()};

    const strok::Frame output = strok::composeDepthOverlay(base, overlay, strok::DepthOverlayOptions{.alpha = 0.5, .depth_threshold = 1.0});
    expect(output.pts_us == 123, "overlay preserves pts");
    expect(output.rgb[0] == 128 && output.rgb[1] == 0 && output.rgb[2] == 0, "finite depth blends");
    expect(output.rgb[3] == 10 && output.rgb[4] == 20 && output.rgb[5] == 30, "infinite depth skips");
  }

  {
    strok::Frame base{.w = 1, .h = 1, .rgb = {10, 10, 10}};
    strok::SceneGBuffer overlay;
    overlay.albedo = strok::Frame{.w = 1, .h = 1, .rgb = {250, 250, 250}};
    overlay.depth = {2.0};
    const strok::Frame output = strok::composeDepthOverlay(base, overlay, strok::DepthOverlayOptions{.alpha = 1.0, .depth_threshold = 1.0});
    expect(output.rgb[0] == 10, "depth threshold rejects far overlay");
  }

  {
    bool threw = false;
    try {
      strok::Frame base{.w = 1, .h = 1, .rgb = {0, 0, 0}};
      strok::SceneGBuffer overlay;
      overlay.albedo = strok::Frame{.w = 2, .h = 1, .rgb = {0, 0, 0, 0, 0, 0}};
      overlay.depth = {0.0, 0.0};
      (void)strok::composeDepthOverlay(base, overlay);
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "dimension mismatch rejected");
  }
}
