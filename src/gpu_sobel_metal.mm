#include "gpu_sobel.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace contourtty {
namespace {

struct PackedGradient {
  float gx = 0.0F;
  float gy = 0.0F;
};

constexpr char kSobelMetalSource[] = R"METAL(
#include <metal_stdlib>
using namespace metal;

kernel void sobel_kernel(device const float* luminance [[buffer(0)]],
                         device float2* gradients [[buffer(1)]],
                         constant uint2& size [[buffer(2)]],
                         uint2 gid [[thread_position_in_grid]]) {
  const uint width = size.x;
  const uint height = size.y;
  if (gid.x >= width || gid.y >= height) {
    return;
  }
  const auto sample = [&](int x, int y) {
    const int cx = clamp(x, 0, int(width) - 1);
    const int cy = clamp(y, 0, int(height) - 1);
    return luminance[uint(cy) * width + uint(cx)];
  };
  const int x = int(gid.x);
  const int y = int(gid.y);
  const float gx =
    -sample(x - 1, y - 1) + sample(x + 1, y - 1) -
    2.0F * sample(x - 1, y) + 2.0F * sample(x + 1, y) -
    sample(x - 1, y + 1) + sample(x + 1, y + 1);
  const float gy =
    -sample(x - 1, y - 1) - 2.0F * sample(x, y - 1) - sample(x + 1, y - 1) +
    sample(x - 1, y + 1) + 2.0F * sample(x, y + 1) + sample(x + 1, y + 1);
  gradients[gid.y * width + gid.x] = float2(gx, gy);
}
)METAL";

class MetalSobelContext {
 public:
  MetalSobelContext() {
    @autoreleasepool {
      device_ = MTLCreateSystemDefaultDevice();
      if (device_ == nil) {
        return;
      }
      NSError* error = nil;
      NSString* source = [[NSString alloc] initWithUTF8String:kSobelMetalSource];
      library_ = [device_ newLibraryWithSource:source options:nil error:&error];
      if (library_ == nil) {
        return;
      }
      id<MTLFunction> function = [library_ newFunctionWithName:@"sobel_kernel"];
      if (function == nil) {
        return;
      }
      pipeline_ = [device_ newComputePipelineStateWithFunction:function error:&error];
      queue_ = [device_ newCommandQueue];
    }
  }

  bool ready() const {
    return device_ != nil && pipeline_ != nil && queue_ != nil;
  }

  id<MTLDevice> device() const {
    return device_;
  }

  id<MTLComputePipelineState> pipeline() const {
    return pipeline_;
  }

  id<MTLCommandQueue> queue() const {
    return queue_;
  }

 private:
  id<MTLDevice> device_ = nil;
  id<MTLLibrary> library_ = nil;
  id<MTLComputePipelineState> pipeline_ = nil;
  id<MTLCommandQueue> queue_ = nil;
};

MetalSobelContext& metalSobelContext() {
  static MetalSobelContext context;
  return context;
}

}  // namespace

bool gpuSobelAvailable() {
  return metalSobelContext().ready();
}

std::optional<GradientField> computeSobelGradientsGpu(const LuminanceField& field) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }

  MetalSobelContext& context = metalSobelContext();
  if (!context.ready()) {
    return std::nullopt;
  }

  @autoreleasepool {
    std::vector<float> luminance(field.values.size());
    for (std::size_t index = 0; index < field.values.size(); ++index) {
      luminance[index] = static_cast<float>(field.values[index]);
    }
    std::vector<PackedGradient> packed(field.values.size());
    const std::size_t luminance_bytes = luminance.size() * sizeof(float);
    const std::size_t gradient_bytes = packed.size() * sizeof(PackedGradient);
    const uint32_t dimensions[2] {
      static_cast<uint32_t>(field.width),
      static_cast<uint32_t>(field.height),
    };

    id<MTLBuffer> luminance_buffer = [context.device() newBufferWithBytes:luminance.data()
                                                                   length:luminance_bytes
                                                                  options:MTLResourceStorageModeShared];
    id<MTLBuffer> gradient_buffer = [context.device() newBufferWithLength:gradient_bytes
                                                                   options:MTLResourceStorageModeShared];
    id<MTLBuffer> dimensions_buffer = [context.device() newBufferWithBytes:dimensions
                                                                    length:sizeof(dimensions)
                                                                   options:MTLResourceStorageModeShared];
    if (luminance_buffer == nil || gradient_buffer == nil || dimensions_buffer == nil) {
      return std::nullopt;
    }

    id<MTLCommandBuffer> command_buffer = [context.queue() commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
    if (command_buffer == nil || encoder == nil) {
      return std::nullopt;
    }
    [encoder setComputePipelineState:context.pipeline()];
    [encoder setBuffer:luminance_buffer offset:0 atIndex:0];
    [encoder setBuffer:gradient_buffer offset:0 atIndex:1];
    [encoder setBuffer:dimensions_buffer offset:0 atIndex:2];

    const NSUInteger thread_width = std::min<NSUInteger>(16, context.pipeline().threadExecutionWidth);
    const NSUInteger thread_height = std::max<NSUInteger>(1, std::min<NSUInteger>(16, context.pipeline().maxTotalThreadsPerThreadgroup / thread_width));
    [encoder dispatchThreads:MTLSizeMake(static_cast<NSUInteger>(field.width), static_cast<NSUInteger>(field.height), 1)
       threadsPerThreadgroup:MTLSizeMake(thread_width, thread_height, 1)];
    [encoder endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];
    if (command_buffer.status == MTLCommandBufferStatusError) {
      return std::nullopt;
    }

    std::memcpy(packed.data(), gradient_buffer.contents, gradient_bytes);
    GradientField gradients;
    gradients.width = field.width;
    gradients.height = field.height;
    gradients.values.reserve(packed.size());
    for (const PackedGradient gradient : packed) {
      gradients.values.push_back(Gradient{.gx = static_cast<double>(gradient.gx), .gy = static_cast<double>(gradient.gy)});
    }
    return gradients;
  }
}

}  // namespace contourtty
