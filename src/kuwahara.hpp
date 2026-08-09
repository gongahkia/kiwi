#pragma once

#include "color_image_view.hpp"
#include "frame.hpp"

namespace strok {

Frame applyKuwaharaFilter(const Frame& frame, int radius);
Frame applyKuwaharaFilter(const ColorImageView& image, int radius);

}  // namespace strok
