#include "shader_runtime.hpp"

#include "shader_compiler.hpp"
#include "shader_source.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <simd/simd.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace strok {
namespace {

struct PackedFloat3 {
  float x = 0.0F;
  float y = 0.0F;
  float z = 0.0F;
};

struct ShaderUniforms {
  PackedFloat3 iResolution;
  float iTime = 0.0F;
  float iTimeDelta = 0.0F;
  int32_t iFrame = 0;
  float padding0[2] {};
  vector_float4 iMouse {};
  vector_float4 iDate {};
  float iSampleRate = 44100.0F;
  float padding1[3] {};
  vector_float4 iChannelResolution[4] {};
  vector_float4 iChannelTime[4] {};
};

struct VertexParams {
  vector_float2 resolution {};
};

constexpr char kVertexMetalSource[] = R"METAL(
#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

struct StrokVertexParams {
  float2 resolution;
};

struct StrokVertexOut {
  float4 position [[position]];
  float2 strokFragCoord [[user(locn0)]];
};

vertex StrokVertexOut strok_vertex(uint vertex_id [[vertex_id]],
                                             constant StrokVertexParams& params [[buffer(0)]]) {
  const float2 positions[3] = {
    float2(-1.0, -1.0),
    float2(3.0, -1.0),
    float2(-1.0, 3.0),
  };
  const float2 position = positions[vertex_id];
  const float2 uv = (position + float2(1.0)) * 0.5;
  StrokVertexOut out;
  out.position = float4(position, 0.0, 1.0);
  out.strokFragCoord = uv * params.resolution;
  return out;
}
)METAL";

std::string nsErrorMessage(NSError* error) {
  if (error == nil) {
    return "unknown Metal error";
  }
  const char* text = [[error localizedDescription] UTF8String];
  return text == nullptr ? "unknown Metal error" : std::string(text);
}

std::filesystem::file_time_type shaderWriteTime(const std::filesystem::path& path) {
  std::error_code ec;
  const auto time = std::filesystem::last_write_time(path, ec);
  if (ec) {
    throw std::runtime_error("failed to stat shader source: " + path.string());
  }
  return time;
}

ShaderUniforms makeUniforms(int width, int height, int64_t pts_us, int64_t frame_index, int64_t frame_delta_us) {
  ShaderUniforms uniforms;
  uniforms.iResolution = PackedFloat3{static_cast<float>(width), static_cast<float>(height), 1.0F};
  uniforms.iTime = static_cast<float>(static_cast<double>(pts_us) / 1000000.0);
  uniforms.iTimeDelta = static_cast<float>(static_cast<double>(frame_delta_us) / 1000000.0);
  uniforms.iFrame = static_cast<int32_t>(std::clamp<int64_t>(frame_index, 0, std::numeric_limits<int32_t>::max()));
  uniforms.iSampleRate = 44100.0F;
  return uniforms;
}

}  // namespace

bool shaderRuntimeAvailable() {
  @autoreleasepool {
    return MTLCreateSystemDefaultDevice() != nil;
  }
}

struct ShaderFrameSource::Impl {
  explicit Impl(std::filesystem::path source_path) : path(std::move(source_path)) {
    @autoreleasepool {
      device = MTLCreateSystemDefaultDevice();
      if (device == nil) {
        throw std::runtime_error("Metal shader runtime unavailable");
      }
      queue = [device newCommandQueue];
      if (queue == nil) {
        throw std::runtime_error("Metal command queue unavailable");
      }
      compile();
    }
  }

  void compile() {
    const std::string source = loadShaderSource(path);
    ShaderCompileOptions options;
    options.entry_point = "main";
    const ShaderCompileResult compiled = compileShadertoyFragmentToSpirvAndMsl(source, options);
    const std::string metal_source = std::string(kVertexMetalSource) + "\n" + compiled.msl;

    @autoreleasepool {
      NSError* error = nil;
      NSString* source_string = [[NSString alloc] initWithUTF8String:metal_source.c_str()];
      id<MTLLibrary> next_library = [device newLibraryWithSource:source_string options:nil error:&error];
      if (next_library == nil) {
        throw std::runtime_error("failed to compile Metal shader: " + nsErrorMessage(error));
      }
      id<MTLFunction> vertex = [next_library newFunctionWithName:@"strok_vertex"];
      id<MTLFunction> fragment = [next_library newFunctionWithName:@"main0"];
      if (vertex == nil || fragment == nil) {
        throw std::runtime_error("compiled shader is missing Metal entry points");
      }
      MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
      descriptor.vertexFunction = vertex;
      descriptor.fragmentFunction = fragment;
      descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
      id<MTLRenderPipelineState> next_pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
      if (next_pipeline == nil) {
        throw std::runtime_error("failed to create Metal shader pipeline: " + nsErrorMessage(error));
      }
      library = next_library;
      pipeline = next_pipeline;
      write_time = shaderWriteTime(path);
    }
  }

  void ensureTexture(int width, int height) {
    if (texture != nil && texture_width == width && texture_height == height) {
      return;
    }
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:static_cast<NSUInteger>(width)
                                                                                         height:static_cast<NSUInteger>(height)
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;
    texture = [device newTextureWithDescriptor:descriptor];
    if (texture == nil) {
      throw std::runtime_error("failed to allocate Metal shader texture");
    }
    texture_width = width;
    texture_height = height;
  }

  void reloadIfChanged() {
    const auto current = shaderWriteTime(path);
    if (current != write_time) {
      compile();
    }
  }

  Frame renderFrame(int width, int height, int64_t pts_us, int64_t frame_index, int64_t frame_delta_us) {
    if (width <= 0 || height <= 0) {
      throw std::runtime_error("shader render dimensions must be positive");
    }
    ensureTexture(width, height);
    const VertexParams vertex_params{.resolution = vector_float2{static_cast<float>(width), static_cast<float>(height)}};
    const ShaderUniforms uniforms = makeUniforms(width, height, pts_us, frame_index, frame_delta_us);

    @autoreleasepool {
      MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
      pass.colorAttachments[0].texture = texture;
      pass.colorAttachments[0].loadAction = MTLLoadActionClear;
      pass.colorAttachments[0].storeAction = MTLStoreActionStore;
      pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

      id<MTLCommandBuffer> command = [queue commandBuffer];
      id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
      [encoder setRenderPipelineState:pipeline];
      [encoder setVertexBytes:&vertex_params length:sizeof(vertex_params) atIndex:0];
      [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
      [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      [encoder endEncoding];
      [command commit];
      [command waitUntilCompleted];
      if ([command error] != nil) {
        throw std::runtime_error("Metal shader command failed: " + nsErrorMessage([command error]));
      }
    }

    std::vector<uint8_t> rgba(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U);
    const NSUInteger bytes_per_row = static_cast<NSUInteger>(width * 4);
    [texture getBytes:rgba.data()
          bytesPerRow:bytes_per_row
           fromRegion:MTLRegionMake2D(0, 0, static_cast<NSUInteger>(width), static_cast<NSUInteger>(height))
          mipmapLevel:0];

    Frame frame;
    frame.w = width;
    frame.h = height;
    frame.pts_us = pts_us;
    frame.rgb.resize(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 3U);
    for (std::size_t src = 0, dst = 0; src < rgba.size(); src += 4, dst += 3) {
      frame.rgb[dst] = rgba[src];
      frame.rgb[dst + 1] = rgba[src + 1];
      frame.rgb[dst + 2] = rgba[src + 2];
    }
    return frame;
  }

  std::filesystem::path path;
  std::filesystem::file_time_type write_time {};
  id<MTLDevice> device = nil;
  id<MTLCommandQueue> queue = nil;
  id<MTLLibrary> library = nil;
  id<MTLRenderPipelineState> pipeline = nil;
  id<MTLTexture> texture = nil;
  int texture_width = 0;
  int texture_height = 0;
};

ShaderFrameSource::ShaderFrameSource(std::filesystem::path path) : impl_(std::make_unique<Impl>(std::move(path))) {}
ShaderFrameSource::ShaderFrameSource(ShaderFrameSource&&) noexcept = default;
ShaderFrameSource& ShaderFrameSource::operator=(ShaderFrameSource&&) noexcept = default;
ShaderFrameSource::~ShaderFrameSource() = default;

void ShaderFrameSource::reloadIfChanged() {
  impl_->reloadIfChanged();
}

Frame ShaderFrameSource::renderFrame(int width, int height, int64_t pts_us, int64_t frame_index, int64_t frame_delta_us) {
  return impl_->renderFrame(width, height, pts_us, frame_index, frame_delta_us);
}

}  // namespace strok
