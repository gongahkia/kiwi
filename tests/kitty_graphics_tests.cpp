#include "kitty_graphics.hpp"

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
    const std::vector<uint8_t> rgb{255, 0, 0};
    const std::string escape = contourtty::encodeKittyRgb24(rgb, 1, 1, contourtty::KittyImageOptions{
      .image_id = 7,
      .placement_id = 9,
      .columns = 2,
      .rows = 3,
    });
    expect(escape == "\x1b_Ga=T,t=d,f=24,s=1,v=1,i=7,p=9,q=2,c=2,r=3,C=1,m=0;/wAA\x1b\\", "single chunk RGB24 escape");
  }

  {
    const contourtty::RasterImage image{
      .width = 1,
      .height = 2,
      .rgb = {255, 0, 0, 0, 255, 0},
    };
    const std::string escape = contourtty::encodeKittyRgb24(image, contourtty::KittyImageOptions{
      .image_id = 3,
      .placement_id = 4,
      .chunk_size = 4,
    });
    expect(escape == "\x1b_Ga=T,t=d,f=24,s=1,v=2,i=3,p=4,q=2,C=1,m=1;/wAA\x1b\\"
                     "\x1b_Gq=2,m=0;AP8A\x1b\\", "chunked RGB24 escape");
  }

  {
    const std::string escape = contourtty::deleteKittyImage(12, 5);
    expect(escape == "\x1b_Ga=d,d=i,i=12,p=5,q=2;\x1b\\", "delete image placement escape");
  }

  {
    const std::string escape = contourtty::encodeKittyAnimationFrameRgb24(std::vector<uint8_t>{1, 2, 3}, contourtty::KittyAnimationFrameOptions{
                                                                                                      .image_id = 7,
                                                                                                      .frame_number = 1,
                                                                                                      .x = 2,
                                                                                                      .y = 3,
                                                                                                      .width = 1,
                                                                                                      .height = 1,
                                                                                                    });
    expect(escape == "\x1b_Ga=f,t=d,f=24,i=7,r=1,x=2,y=3,s=1,v=1,X=1,q=2,m=0;AQID\x1b\\", "animation delta frame escape");
    expect(contourtty::controlKittyAnimationFrame(7, 1) == "\x1b_Ga=a,i=7,c=1,q=2;\x1b\\", "animation current-frame control escape");
  }

  {
    bool threw = false;
    try {
      (void)contourtty::encodeKittyRgb24(std::vector<uint8_t>{255, 0}, 1, 1);
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "invalid RGB24 size rejected");
  }

  {
    bool threw = false;
    try {
      (void)contourtty::encodeKittyRgb24(std::vector<uint8_t>{255, 0, 0}, 1, 1, contourtty::KittyImageOptions{.chunk_size = 5});
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "invalid chunk size rejected");
  }
}
