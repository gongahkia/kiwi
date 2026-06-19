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

struct StructureParams {
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t cols = 0;
  uint32_t rows = 0;
  float threshold = 0.0F;
  uint32_t table_count = 0;
};

constexpr char kSobelMetalSource[] = R"METAL(
#include <metal_stdlib>
using namespace metal;

struct StructureParams {
  uint width;
  uint height;
  uint cols;
  uint rows;
  float threshold;
  uint table_count;
};

constant uint kShapeRegionCount = 9;
constant float kShapeRadius = 0.29F;
constant float kPi = 3.14159265358979323846F;

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

static float angular_distance(float a, float b) {
  float delta = fmod(abs(a - b), 2.0F * kPi);
  if (delta > kPi) {
    delta = 2.0F * kPi - delta;
  }
  return delta;
}

static uint directional_glyph(float gx, float gy, float magnitude, float orientation, float horizontal_energy, float vertical_energy, float threshold) {
  if (magnitude <= threshold) {
    return 0;
  }
  const float min_energy = min(horizontal_energy, vertical_energy);
  const float max_energy = max(horizontal_energy, vertical_energy);
  if (min_energy > threshold && max_energy > 0.0F && min_energy / max_energy >= 0.55F && magnitude < max_energy * 1.15F) {
    return uint('+');
  }

  float best_distance = angular_distance(orientation, 0.0F);
  uint best_glyph = uint('|');
  const float angles[9] = {0.0F, kPi, -kPi, kPi / 2.0F, -kPi / 2.0F, kPi / 4.0F, -3.0F * kPi / 4.0F, -kPi / 4.0F, 3.0F * kPi / 4.0F};
  const uint glyphs[9] = {uint('|'), uint('|'), uint('|'), gy >= 0.0F ? uint('_') : uint('-'), uint('-'), uint('/'), uint('/'), uint('\\'), uint('\\')};
  for (uint i = 0; i < 9; ++i) {
    const float distance = angular_distance(orientation, angles[i]);
    if (distance < best_distance) {
      best_distance = distance;
      best_glyph = glyphs[i];
    }
  }
  return best_glyph;
}

kernel void structure_glyphs_kernel(device const float* luminance [[buffer(0)]],
                                    device const float* glyph_features [[buffer(1)]],
                                    device const uint* glyph_codes [[buffer(2)]],
                                    device uint* output_glyphs [[buffer(3)]],
                                    constant StructureParams& params [[buffer(4)]],
                                    uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= params.cols || gid.y >= params.rows) {
    return;
  }
  const uint col = gid.x;
  const uint row = gid.y;
  const uint x0 = (col * params.width) / params.cols;
  const uint x1 = ((col + 1) * params.width) / params.cols;
  const uint y0 = (row * params.height) / params.rows;
  const uint y1 = ((row + 1) * params.height) / params.rows;
  const uint cell_width = x1 - x0;
  const uint cell_height = y1 - y0;
  const uint out_index = row * params.cols + col;
  if (cell_width == 0 || cell_height == 0) {
    output_glyphs[out_index] = 0;
    return;
  }

  const auto sample = [&](int x, int y) {
    const int cx = clamp(x, 0, int(params.width) - 1);
    const int cy = clamp(y, 0, int(params.height) - 1);
    return luminance[uint(cy) * params.width + uint(cx)];
  };

  float gx_sum = 0.0F;
  float gy_sum = 0.0F;
  float horizontal_energy = 0.0F;
  float vertical_energy = 0.0F;
  float features[9] = {0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F};
  uint samples[9] = {0, 0, 0, 0, 0, 0, 0, 0, 0};
  const float region_cx[9] = {0.50F, 0.50F, 0.50F, 0.20F, 0.80F, 0.25F, 0.75F, 0.25F, 0.75F};
  const float region_cy[9] = {0.50F, 0.20F, 0.80F, 0.50F, 0.50F, 0.25F, 0.25F, 0.75F, 0.75F};
  uint count = 0;

  for (uint y = y0; y < y1; ++y) {
    for (uint x = x0; x < x1; ++x) {
      const int ix = int(x);
      const int iy = int(y);
      const float gx =
        -sample(ix - 1, iy - 1) + sample(ix + 1, iy - 1) -
        2.0F * sample(ix - 1, iy) + 2.0F * sample(ix + 1, iy) -
        sample(ix - 1, iy + 1) + sample(ix + 1, iy + 1);
      const float gy =
        -sample(ix - 1, iy - 1) - 2.0F * sample(ix, iy - 1) - sample(ix + 1, iy - 1) +
        sample(ix - 1, iy + 1) + 2.0F * sample(ix, iy + 1) + sample(ix + 1, iy + 1);
      gx_sum += gx;
      gy_sum += gy;
      horizontal_energy += abs(gx);
      vertical_energy += abs(gy);
      ++count;

      const float ink_magnitude = length(float2(gx, gy));
      const float ink = ink_magnitude > params.threshold ? ink_magnitude : 0.0F;
      const float nx = (float(x - x0) + 0.5F) / float(cell_width);
      const float ny = (float(y - y0) + 0.5F) / float(cell_height);
      for (uint i = 0; i < kShapeRegionCount; ++i) {
        const float dx = nx - region_cx[i];
        const float dy = ny - region_cy[i];
        if (length(float2(dx, dy)) <= kShapeRadius) {
          features[i] += ink;
          ++samples[i];
        }
      }
    }
  }

  if (count == 0) {
    output_glyphs[out_index] = 0;
    return;
  }
  const float scale = 1.0F / float(count);
  const float avg_gx = gx_sum * scale;
  const float avg_gy = gy_sum * scale;
  horizontal_energy *= scale;
  vertical_energy *= scale;
  const float magnitude = length(float2(avg_gx, avg_gy));
  const float orientation = atan2(avg_gy, avg_gx);
  const uint edge_glyph = directional_glyph(avg_gx, avg_gy, magnitude, orientation, horizontal_energy, vertical_energy, params.threshold);
  if (edge_glyph == 0) {
    output_glyphs[out_index] = 0;
    return;
  }
  if (params.table_count == 0) {
    output_glyphs[out_index] = edge_glyph;
    return;
  }

  float feature_norm = 0.0F;
  for (uint i = 0; i < kShapeRegionCount; ++i) {
    if (samples[i] > 0) {
      features[i] /= float(samples[i]);
    }
    feature_norm += features[i] * features[i];
  }
  if (feature_norm == 0.0F) {
    output_glyphs[out_index] = glyph_codes[0];
    return;
  }

  float best_score = -INFINITY;
  uint best_glyph = glyph_codes[0];
  for (uint entry = 0; entry < params.table_count; ++entry) {
    float dot = 0.0F;
    float entry_norm = 0.0F;
    for (uint i = 0; i < kShapeRegionCount; ++i) {
      const float value = glyph_features[entry * kShapeRegionCount + i];
      dot += features[i] * value;
      entry_norm += value * value;
    }
    if (entry_norm == 0.0F) {
      continue;
    }
    const float score = dot / sqrt(feature_norm * entry_norm);
    if (score > best_score) {
      best_score = score;
      best_glyph = glyph_codes[entry];
    }
  }
  output_glyphs[out_index] = best_glyph;
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
      id<MTLFunction> structure_function = [library_ newFunctionWithName:@"structure_glyphs_kernel"];
      if (structure_function != nil) {
        structure_pipeline_ = [device_ newComputePipelineStateWithFunction:structure_function error:&error];
      }
      queue_ = [device_ newCommandQueue];
    }
  }

  bool ready() const {
    return device_ != nil && pipeline_ != nil && structure_pipeline_ != nil && queue_ != nil;
  }

  id<MTLDevice> device() const {
    return device_;
  }

  id<MTLComputePipelineState> pipeline() const {
    return pipeline_;
  }

  id<MTLComputePipelineState> structurePipeline() const {
    return structure_pipeline_;
  }

  id<MTLCommandQueue> queue() const {
    return queue_;
  }

 private:
  id<MTLDevice> device_ = nil;
  id<MTLLibrary> library_ = nil;
  id<MTLComputePipelineState> pipeline_ = nil;
  id<MTLComputePipelineState> structure_pipeline_ = nil;
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

std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }
  if (cols <= 0 || rows <= 0) {
    throw std::invalid_argument("cell grid dimensions must be positive");
  }
  if (edge_threshold < 0.0) {
    throw std::invalid_argument("edge threshold must be non-negative");
  }
  if (cols > field.width || rows > field.height) {
    return std::nullopt;
  }

  MetalSobelContext& context = metalSobelContext();
  if (!context.ready() || context.structurePipeline() == nil) {
    return std::nullopt;
  }

  @autoreleasepool {
    std::vector<float> luminance(field.values.size());
    for (std::size_t index = 0; index < field.values.size(); ++index) {
      luminance[index] = static_cast<float>(field.values[index]);
    }

    std::vector<float> glyph_features;
    std::vector<uint32_t> glyph_codes;
    if (shape_table != nullptr) {
      glyph_features.reserve(shape_table->entries.size() * kShapeRegionCount);
      glyph_codes.reserve(shape_table->entries.size());
      for (const GlyphShapeVector& entry : shape_table->entries) {
        if (entry.features.size() != kShapeRegionCount) {
          throw std::invalid_argument("glyph shape table feature length mismatch");
        }
        glyph_codes.push_back(static_cast<uint32_t>(entry.glyph));
        for (const double feature : entry.features) {
          glyph_features.push_back(static_cast<float>(feature));
        }
      }
    }

    std::vector<uint32_t> output(static_cast<std::size_t>(cols) * static_cast<std::size_t>(rows), 0);
    const StructureParams params{
      .width = static_cast<uint32_t>(field.width),
      .height = static_cast<uint32_t>(field.height),
      .cols = static_cast<uint32_t>(cols),
      .rows = static_cast<uint32_t>(rows),
      .threshold = static_cast<float>(edge_threshold),
      .table_count = static_cast<uint32_t>(glyph_codes.size()),
    };
    const std::size_t luminance_bytes = luminance.size() * sizeof(float);
    const std::size_t glyph_feature_bytes = std::max<std::size_t>(glyph_features.size() * sizeof(float), sizeof(float));
    const std::size_t glyph_code_bytes = std::max<std::size_t>(glyph_codes.size() * sizeof(uint32_t), sizeof(uint32_t));
    const std::size_t output_bytes = output.size() * sizeof(uint32_t);

    float dummy_feature = 0.0F;
    uint32_t dummy_glyph = 0;
    id<MTLBuffer> luminance_buffer = [context.device() newBufferWithBytes:luminance.data()
                                                                   length:luminance_bytes
                                                                  options:MTLResourceStorageModeShared];
    id<MTLBuffer> glyph_feature_buffer = [context.device() newBufferWithBytes:glyph_features.empty() ? &dummy_feature : glyph_features.data()
                                                                       length:glyph_feature_bytes
                                                                      options:MTLResourceStorageModeShared];
    id<MTLBuffer> glyph_code_buffer = [context.device() newBufferWithBytes:glyph_codes.empty() ? &dummy_glyph : glyph_codes.data()
                                                                    length:glyph_code_bytes
                                                                   options:MTLResourceStorageModeShared];
    id<MTLBuffer> output_buffer = [context.device() newBufferWithLength:output_bytes
                                                                 options:MTLResourceStorageModeShared];
    id<MTLBuffer> params_buffer = [context.device() newBufferWithBytes:&params
                                                                length:sizeof(params)
                                                               options:MTLResourceStorageModeShared];
    if (luminance_buffer == nil || glyph_feature_buffer == nil || glyph_code_buffer == nil || output_buffer == nil || params_buffer == nil) {
      return std::nullopt;
    }

    id<MTLCommandBuffer> command_buffer = [context.queue() commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
    if (command_buffer == nil || encoder == nil) {
      return std::nullopt;
    }
    [encoder setComputePipelineState:context.structurePipeline()];
    [encoder setBuffer:luminance_buffer offset:0 atIndex:0];
    [encoder setBuffer:glyph_feature_buffer offset:0 atIndex:1];
    [encoder setBuffer:glyph_code_buffer offset:0 atIndex:2];
    [encoder setBuffer:output_buffer offset:0 atIndex:3];
    [encoder setBuffer:params_buffer offset:0 atIndex:4];

    const NSUInteger thread_width = std::min<NSUInteger>(16, context.structurePipeline().threadExecutionWidth);
    const NSUInteger thread_height = std::max<NSUInteger>(1, std::min<NSUInteger>(16, context.structurePipeline().maxTotalThreadsPerThreadgroup / thread_width));
    [encoder dispatchThreads:MTLSizeMake(static_cast<NSUInteger>(cols), static_cast<NSUInteger>(rows), 1)
       threadsPerThreadgroup:MTLSizeMake(thread_width, thread_height, 1)];
    [encoder endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];
    if (command_buffer.status == MTLCommandBufferStatusError) {
      return std::nullopt;
    }

    std::memcpy(output.data(), output_buffer.contents, output_bytes);
    GpuStructureGlyphs result;
    result.glyphs.reserve(output.size());
    for (const uint32_t glyph : output) {
      result.glyphs.push_back(static_cast<char32_t>(glyph));
      if (shape_table != nullptr && glyph != 0) {
        ++result.shape_match_cells;
      }
    }
    return result;
  }
}

}  // namespace contourtty
