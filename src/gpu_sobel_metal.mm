#include "gpu_sobel.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace strok {
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
  uint32_t has_rgb = 0;
};

struct DogParams {
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t radius1 = 0;
  uint32_t radius2 = 0;
  float threshold = 0.0F;
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
  uint has_rgb;
};

struct DogParams {
  uint width;
  uint height;
  uint radius1;
  uint radius2;
  float threshold;
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

kernel void dog_kernel(device const float* luminance [[buffer(0)]],
                       device const float* kernel1 [[buffer(1)]],
                       device const float* kernel2 [[buffer(2)]],
                       device float* output [[buffer(3)]],
                       constant DogParams& params [[buffer(4)]],
                       uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= params.width || gid.y >= params.height) {
    return;
  }
  const auto sample = [&](int x, int y) {
    const int cx = clamp(x, 0, int(params.width) - 1);
    const int cy = clamp(y, 0, int(params.height) - 1);
    return luminance[uint(cy) * params.width + uint(cx)];
  };
  const int x = int(gid.x);
  const int y = int(gid.y);
  float narrow = 0.0F;
  float wide = 0.0F;
  for (int ky = -int(params.radius1); ky <= int(params.radius1); ++ky) {
    const float wy = kernel1[uint(ky + int(params.radius1))];
    for (int kx = -int(params.radius1); kx <= int(params.radius1); ++kx) {
      const float wx = kernel1[uint(kx + int(params.radius1))];
      narrow += sample(x + kx, y + ky) * wx * wy;
    }
  }
  for (int ky = -int(params.radius2); ky <= int(params.radius2); ++ky) {
    const float wy = kernel2[uint(ky + int(params.radius2))];
    for (int kx = -int(params.radius2); kx <= int(params.radius2); ++kx) {
      const float wx = kernel2[uint(kx + int(params.radius2))];
      wide += sample(x + kx, y + ky) * wx * wy;
    }
  }
  const float value = abs(narrow - wide);
  output[gid.y * params.width + gid.x] = value >= params.threshold ? value : 0.0F;
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
                                    device uint* output_colors [[buffer(4)]],
                                    device const uchar* rgb [[buffer(5)]],
                                    constant StructureParams& params [[buffer(6)]],
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
  uint r_sum = 0;
  uint g_sum = 0;
  uint b_sum = 0;
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
      if (params.has_rgb != 0) {
        const uint rgb_index = (y * params.width + x) * 3;
        r_sum += uint(rgb[rgb_index]);
        g_sum += uint(rgb[rgb_index + 1]);
        b_sum += uint(rgb[rgb_index + 2]);
      }
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
    output_colors[out_index] = 0;
    return;
  }
  if (params.has_rgb != 0) {
    const uint r = r_sum / count;
    const uint g = g_sum / count;
    const uint b = b_sum / count;
    output_colors[out_index] = r | (g << 8) | (b << 16);
  } else {
    output_colors[out_index] = 0;
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
      id<MTLFunction> dog_function = [library_ newFunctionWithName:@"dog_kernel"];
      if (dog_function != nil) {
        dog_pipeline_ = [device_ newComputePipelineStateWithFunction:dog_function error:&error];
      }
      queue_ = [device_ newCommandQueue];
    }
  }

  bool ready() const {
    return device_ != nil && pipeline_ != nil && structure_pipeline_ != nil && dog_pipeline_ != nil && queue_ != nil;
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

  id<MTLComputePipelineState> dogPipeline() const {
    return dog_pipeline_;
  }

  id<MTLCommandQueue> queue() const {
    return queue_;
  }

 private:
  id<MTLDevice> device_ = nil;
  id<MTLLibrary> library_ = nil;
  id<MTLComputePipelineState> pipeline_ = nil;
  id<MTLComputePipelineState> structure_pipeline_ = nil;
  id<MTLComputePipelineState> dog_pipeline_ = nil;
  id<MTLCommandQueue> queue_ = nil;
};

MetalSobelContext& metalSobelContext() {
  static MetalSobelContext context;
  return context;
}

std::vector<float> gaussianKernel(float sigma) {
  const int radius = std::max(1, static_cast<int>(std::ceil(sigma * 3.0F)));
  std::vector<float> kernel;
  kernel.reserve(static_cast<std::size_t>(radius * 2 + 1));
  float sum = 0.0F;
  for (int i = -radius; i <= radius; ++i) {
    const float value = std::exp(-(static_cast<float>(i * i)) / (2.0F * sigma * sigma));
    kernel.push_back(value);
    sum += value;
  }
  for (float& value : kernel) {
    value /= sum;
  }
  return kernel;
}

}  // namespace

class MetalAnalysisContext final : public GpuSobelContext {
 public:
  std::optional<LuminanceField> differenceOfGaussians(const LuminanceField& field, DogOptions options) override {
    return differenceOfGaussiansGpu(field, options);
  }

  std::optional<GradientField> sobelGradients(const LuminanceField& field) override {
    return computeSobelGradientsGpu(field);
  }

  std::optional<GpuStructureGlyphs> structureGlyphs(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) override {
    return computeStructureGlyphsGpu(field, cols, rows, edge_threshold, shape_table);
  }
};

std::unique_ptr<GpuSobelContext> createGpuSobelContext() {
  return gpuSobelAvailable() ? std::make_unique<MetalAnalysisContext>() : nullptr;
}

bool gpuSobelAvailable() {
  return metalSobelContext().ready();
}

const char* gpuSobelBackendName() {
  return "Metal";
}

std::optional<LuminanceField> differenceOfGaussiansGpu(const LuminanceField& field, DogOptions options) {
  if (!options.enabled()) {
    return field;
  }
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }
  if (options.threshold < 0.0) {
    throw std::invalid_argument("DoG threshold must be non-negative");
  }

  MetalSobelContext& context = metalSobelContext();
  if (!context.ready() || context.dogPipeline() == nil) {
    return std::nullopt;
  }

  @autoreleasepool {
    std::vector<float> luminance(field.values.size());
    for (std::size_t index = 0; index < field.values.size(); ++index) {
      luminance[index] = static_cast<float>(field.values[index]);
    }
    std::vector<float> output(field.values.size(), 0.0F);
    const std::vector<float> kernel1 = gaussianKernel(static_cast<float>(options.sigma1));
    const std::vector<float> kernel2 = gaussianKernel(static_cast<float>(options.sigma2));
    const DogParams params{
      .width = static_cast<uint32_t>(field.width),
      .height = static_cast<uint32_t>(field.height),
      .radius1 = static_cast<uint32_t>(kernel1.size() / 2U),
      .radius2 = static_cast<uint32_t>(kernel2.size() / 2U),
      .threshold = static_cast<float>(options.threshold),
    };

    id<MTLBuffer> luminance_buffer = [context.device() newBufferWithBytes:luminance.data()
                                                                   length:luminance.size() * sizeof(float)
                                                                  options:MTLResourceStorageModeShared];
    id<MTLBuffer> kernel1_buffer = [context.device() newBufferWithBytes:kernel1.data()
                                                                 length:kernel1.size() * sizeof(float)
                                                                options:MTLResourceStorageModeShared];
    id<MTLBuffer> kernel2_buffer = [context.device() newBufferWithBytes:kernel2.data()
                                                                 length:kernel2.size() * sizeof(float)
                                                                options:MTLResourceStorageModeShared];
    id<MTLBuffer> output_buffer = [context.device() newBufferWithLength:output.size() * sizeof(float)
                                                                 options:MTLResourceStorageModeShared];
    id<MTLBuffer> params_buffer = [context.device() newBufferWithBytes:&params
                                                                length:sizeof(params)
                                                               options:MTLResourceStorageModeShared];
    if (luminance_buffer == nil || kernel1_buffer == nil || kernel2_buffer == nil || output_buffer == nil || params_buffer == nil) {
      return std::nullopt;
    }

    id<MTLCommandBuffer> command_buffer = [context.queue() commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
    if (command_buffer == nil || encoder == nil) {
      return std::nullopt;
    }
    [encoder setComputePipelineState:context.dogPipeline()];
    [encoder setBuffer:luminance_buffer offset:0 atIndex:0];
    [encoder setBuffer:kernel1_buffer offset:0 atIndex:1];
    [encoder setBuffer:kernel2_buffer offset:0 atIndex:2];
    [encoder setBuffer:output_buffer offset:0 atIndex:3];
    [encoder setBuffer:params_buffer offset:0 atIndex:4];

    const NSUInteger thread_width = std::min<NSUInteger>(16, context.dogPipeline().threadExecutionWidth);
    const NSUInteger thread_height = std::max<NSUInteger>(1, std::min<NSUInteger>(16, context.dogPipeline().maxTotalThreadsPerThreadgroup / thread_width));
    [encoder dispatchThreads:MTLSizeMake(static_cast<NSUInteger>(field.width), static_cast<NSUInteger>(field.height), 1)
       threadsPerThreadgroup:MTLSizeMake(thread_width, thread_height, 1)];
    [encoder endEncoding];
    [command_buffer commit];
    [command_buffer waitUntilCompleted];
    if (command_buffer.status == MTLCommandBufferStatusError) {
      return std::nullopt;
    }

    std::memcpy(output.data(), output_buffer.contents, output.size() * sizeof(float));
    LuminanceField result;
    result.width = field.width;
    result.height = field.height;
    result.values.reserve(output.size());
    for (const float value : output) {
      result.values.push_back(static_cast<double>(value));
    }
    return result;
  }
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

std::optional<GpuStructureGlyphs> computeStructureGlyphsGpuImpl(const Frame* frame, const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }
  if (frame != nullptr) {
    const std::size_t expected_rgb = static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height) * 3U;
    if (frame->w != field.width || frame->h != field.height || frame->rgb.size() != expected_rgb) {
      throw std::invalid_argument("frame RGB data does not match luminance field");
    }
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
    std::vector<uint32_t> output_colors(output.size(), 0);
    const StructureParams params{
      .width = static_cast<uint32_t>(field.width),
      .height = static_cast<uint32_t>(field.height),
      .cols = static_cast<uint32_t>(cols),
      .rows = static_cast<uint32_t>(rows),
      .threshold = static_cast<float>(edge_threshold),
      .table_count = static_cast<uint32_t>(glyph_codes.size()),
      .has_rgb = frame != nullptr ? 1U : 0U,
    };
    const std::size_t luminance_bytes = luminance.size() * sizeof(float);
    const std::size_t glyph_feature_bytes = std::max<std::size_t>(glyph_features.size() * sizeof(float), sizeof(float));
    const std::size_t glyph_code_bytes = std::max<std::size_t>(glyph_codes.size() * sizeof(uint32_t), sizeof(uint32_t));
    const std::size_t output_bytes = output.size() * sizeof(uint32_t);
    const std::size_t rgb_bytes = frame != nullptr ? frame->rgb.size() * sizeof(uint8_t) : sizeof(uint8_t);

    float dummy_feature = 0.0F;
    uint32_t dummy_glyph = 0;
    uint8_t dummy_rgb = 0;
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
    id<MTLBuffer> output_color_buffer = [context.device() newBufferWithLength:output_bytes
                                                                       options:MTLResourceStorageModeShared];
    id<MTLBuffer> rgb_buffer = [context.device() newBufferWithBytes:frame != nullptr ? frame->rgb.data() : &dummy_rgb
                                                            length:rgb_bytes
                                                           options:MTLResourceStorageModeShared];
    id<MTLBuffer> params_buffer = [context.device() newBufferWithBytes:&params
                                                                length:sizeof(params)
                                                               options:MTLResourceStorageModeShared];
    if (luminance_buffer == nil || glyph_feature_buffer == nil || glyph_code_buffer == nil ||
        output_buffer == nil || output_color_buffer == nil || rgb_buffer == nil || params_buffer == nil) {
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
    [encoder setBuffer:output_color_buffer offset:0 atIndex:4];
    [encoder setBuffer:rgb_buffer offset:0 atIndex:5];
    [encoder setBuffer:params_buffer offset:0 atIndex:6];

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
    std::memcpy(output_colors.data(), output_color_buffer.contents, output_bytes);
    GpuStructureGlyphs result;
    result.glyphs.reserve(output.size());
    if (frame != nullptr) {
      result.average_colors.reserve(output_colors.size());
    }
    for (std::size_t index = 0; index < output.size(); ++index) {
      const uint32_t glyph = output[index];
      result.glyphs.push_back(static_cast<char32_t>(glyph));
      if (frame != nullptr) {
        const uint32_t color = output_colors[index];
        result.average_colors.push_back(Rgb{
          .r = static_cast<uint8_t>(color & 0xffU),
          .g = static_cast<uint8_t>((color >> 8U) & 0xffU),
          .b = static_cast<uint8_t>((color >> 16U) & 0xffU),
        });
      }
      if (shape_table != nullptr && glyph != 0) {
        ++result.shape_match_cells;
      }
    }
    return result;
  }
}

std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) {
  return computeStructureGlyphsGpuImpl(nullptr, field, cols, rows, edge_threshold, shape_table);
}

std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const Frame& frame, const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) {
  return computeStructureGlyphsGpuImpl(&frame, field, cols, rows, edge_threshold, shape_table);
}

}  // namespace strok
