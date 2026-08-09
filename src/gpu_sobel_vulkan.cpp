#include "gpu_sobel.hpp"

#include "shader_compiler.hpp"

#include <vulkan/vulkan.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
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

constexpr uint32_t kLocalSize = 16;

constexpr char kShaderProbeSource[] = R"GLSL(
#version 450
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() {}
)GLSL";

constexpr char kSobelShaderSource[] = R"GLSL(
#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
layout(std430, binding = 0) readonly buffer LuminanceBuffer { float luminance[]; };
layout(std430, binding = 1) buffer GradientBuffer { vec2 gradients[]; };
layout(std430, binding = 2) readonly buffer SizeBuffer { uint width; uint height; } dims;

float sampleClamped(int x, int y) {
  int cx = clamp(x, 0, int(dims.width) - 1);
  int cy = clamp(y, 0, int(dims.height) - 1);
  return luminance[uint(cy) * dims.width + uint(cx)];
}

void main() {
  uvec2 gid = gl_GlobalInvocationID.xy;
  if (gid.x >= dims.width || gid.y >= dims.height) {
    return;
  }
  int x = int(gid.x);
  int y = int(gid.y);
  float gx =
    -sampleClamped(x - 1, y - 1) + sampleClamped(x + 1, y - 1) -
    2.0 * sampleClamped(x - 1, y) + 2.0 * sampleClamped(x + 1, y) -
    sampleClamped(x - 1, y + 1) + sampleClamped(x + 1, y + 1);
  float gy =
    -sampleClamped(x - 1, y - 1) - 2.0 * sampleClamped(x, y - 1) - sampleClamped(x + 1, y - 1) +
    sampleClamped(x - 1, y + 1) + 2.0 * sampleClamped(x, y + 1) + sampleClamped(x + 1, y + 1);
  gradients[gid.y * dims.width + gid.x] = vec2(gx, gy);
}
)GLSL";

constexpr char kDogShaderSource[] = R"GLSL(
#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
layout(std430, binding = 0) readonly buffer LuminanceBuffer { float luminance[]; };
layout(std430, binding = 1) readonly buffer KernelOneBuffer { float kernel1[]; };
layout(std430, binding = 2) readonly buffer KernelTwoBuffer { float kernel2[]; };
layout(std430, binding = 3) buffer OutputBuffer { float output_values[]; };
layout(std430, binding = 4) readonly buffer ParamsBuffer { uint width; uint height; uint radius1; uint radius2; float threshold; } params;

float sampleClamped(int x, int y) {
  int cx = clamp(x, 0, int(params.width) - 1);
  int cy = clamp(y, 0, int(params.height) - 1);
  return luminance[uint(cy) * params.width + uint(cx)];
}

void main() {
  uvec2 gid = gl_GlobalInvocationID.xy;
  if (gid.x >= params.width || gid.y >= params.height) {
    return;
  }
  int x = int(gid.x);
  int y = int(gid.y);
  float narrow = 0.0;
  float wide = 0.0;
  for (int ky = -int(params.radius1); ky <= int(params.radius1); ++ky) {
    float wy = kernel1[uint(ky + int(params.radius1))];
    for (int kx = -int(params.radius1); kx <= int(params.radius1); ++kx) {
      float wx = kernel1[uint(kx + int(params.radius1))];
      narrow += sampleClamped(x + kx, y + ky) * wx * wy;
    }
  }
  for (int ky = -int(params.radius2); ky <= int(params.radius2); ++ky) {
    float wy = kernel2[uint(ky + int(params.radius2))];
    for (int kx = -int(params.radius2); kx <= int(params.radius2); ++kx) {
      float wx = kernel2[uint(kx + int(params.radius2))];
      wide += sampleClamped(x + kx, y + ky) * wx * wy;
    }
  }
  float value = abs(narrow - wide);
  output_values[gid.y * params.width + gid.x] = value >= params.threshold ? value : 0.0;
}
)GLSL";

constexpr char kStructureShaderSource[] = R"GLSL(
#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
layout(std430, binding = 0) readonly buffer LuminanceBuffer { float luminance[]; };
layout(std430, binding = 1) readonly buffer GlyphFeatureBuffer { float glyph_features[]; };
layout(std430, binding = 2) readonly buffer GlyphCodeBuffer { uint glyph_codes[]; };
layout(std430, binding = 3) buffer OutputGlyphBuffer { uint output_glyphs[]; };
layout(std430, binding = 4) buffer OutputColorBuffer { uint output_colors[]; };
layout(std430, binding = 5) readonly buffer RgbBuffer { uint rgb[]; };
layout(std430, binding = 6) readonly buffer ParamsBuffer { uint width; uint height; uint cols; uint rows; float threshold; uint table_count; uint has_rgb; } params;

const uint kShapeRegionCount = 9u;
const float kShapeRadius = 0.29;
const float kPi = 3.14159265358979323846;

float sampleClamped(int x, int y) {
  int cx = clamp(x, 0, int(params.width) - 1);
  int cy = clamp(y, 0, int(params.height) - 1);
  return luminance[uint(cy) * params.width + uint(cx)];
}

float angularDistance(float a, float b) {
  float delta = mod(abs(a - b), 2.0 * kPi);
  if (delta > kPi) {
    delta = 2.0 * kPi - delta;
  }
  return delta;
}

uint directionalGlyph(float gy, float magnitude, float orientation, float horizontal_energy, float vertical_energy) {
  if (magnitude <= params.threshold) {
    return 0u;
  }
  float min_energy = min(horizontal_energy, vertical_energy);
  float max_energy = max(horizontal_energy, vertical_energy);
  if (min_energy > params.threshold && max_energy > 0.0 && min_energy / max_energy >= 0.55 && magnitude < max_energy * 1.15) {
    return 43u;
  }
  float best_distance = angularDistance(orientation, 0.0);
  uint best_glyph = 124u;
  float angles[9] = float[](0.0, kPi, -kPi, kPi / 2.0, -kPi / 2.0, kPi / 4.0, -3.0 * kPi / 4.0, -kPi / 4.0, 3.0 * kPi / 4.0);
  uint glyphs[9] = uint[](124u, 124u, 124u, gy >= 0.0 ? 95u : 45u, 45u, 47u, 47u, 92u, 92u);
  for (uint i = 0u; i < 9u; ++i) {
    float distance = angularDistance(orientation, angles[i]);
    if (distance < best_distance) {
      best_distance = distance;
      best_glyph = glyphs[i];
    }
  }
  return best_glyph;
}

void main() {
  uvec2 gid = gl_GlobalInvocationID.xy;
  if (gid.x >= params.cols || gid.y >= params.rows) {
    return;
  }
  uint col = gid.x;
  uint row = gid.y;
  uint x0 = (col * params.width) / params.cols;
  uint x1 = ((col + 1u) * params.width) / params.cols;
  uint y0 = (row * params.height) / params.rows;
  uint y1 = ((row + 1u) * params.height) / params.rows;
  uint cell_width = x1 - x0;
  uint cell_height = y1 - y0;
  uint out_index = row * params.cols + col;
  output_glyphs[out_index] = 0u;
  output_colors[out_index] = 0u;
  if (cell_width == 0u || cell_height == 0u) {
    return;
  }

  float gx_sum = 0.0;
  float gy_sum = 0.0;
  float horizontal_energy = 0.0;
  float vertical_energy = 0.0;
  float features[9] = float[](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
  uint samples[9] = uint[](0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u);
  float region_cx[9] = float[](0.50, 0.50, 0.50, 0.20, 0.80, 0.25, 0.75, 0.25, 0.75);
  float region_cy[9] = float[](0.50, 0.20, 0.80, 0.50, 0.50, 0.25, 0.25, 0.75, 0.75);
  uint r_sum = 0u;
  uint g_sum = 0u;
  uint b_sum = 0u;
  uint count = 0u;

  for (uint y = y0; y < y1; ++y) {
    for (uint x = x0; x < x1; ++x) {
      int ix = int(x);
      int iy = int(y);
      float gx =
        -sampleClamped(ix - 1, iy - 1) + sampleClamped(ix + 1, iy - 1) -
        2.0 * sampleClamped(ix - 1, iy) + 2.0 * sampleClamped(ix + 1, iy) -
        sampleClamped(ix - 1, iy + 1) + sampleClamped(ix + 1, iy + 1);
      float gy =
        -sampleClamped(ix - 1, iy - 1) - 2.0 * sampleClamped(ix, iy - 1) - sampleClamped(ix + 1, iy - 1) +
        sampleClamped(ix - 1, iy + 1) + 2.0 * sampleClamped(ix, iy + 1) + sampleClamped(ix + 1, iy + 1);
      gx_sum += gx;
      gy_sum += gy;
      horizontal_energy += abs(gx);
      vertical_energy += abs(gy);
      if (params.has_rgb != 0u) {
        uint rgb_index = (y * params.width + x) * 3u;
        r_sum += rgb[rgb_index];
        g_sum += rgb[rgb_index + 1u];
        b_sum += rgb[rgb_index + 2u];
      }
      ++count;

      float ink_magnitude = length(vec2(gx, gy));
      float ink = ink_magnitude > params.threshold ? ink_magnitude : 0.0;
      float nx = (float(x - x0) + 0.5) / float(cell_width);
      float ny = (float(y - y0) + 0.5) / float(cell_height);
      for (uint i = 0u; i < kShapeRegionCount; ++i) {
        float dx = nx - region_cx[i];
        float dy = ny - region_cy[i];
        if (length(vec2(dx, dy)) <= kShapeRadius) {
          features[i] += ink;
          ++samples[i];
        }
      }
    }
  }

  if (count == 0u) {
    return;
  }
  if (params.has_rgb != 0u) {
    uint r = r_sum / count;
    uint g = g_sum / count;
    uint b = b_sum / count;
    output_colors[out_index] = r | (g << 8u) | (b << 16u);
  }
  float scale = 1.0 / float(count);
  float avg_gx = gx_sum * scale;
  float avg_gy = gy_sum * scale;
  horizontal_energy *= scale;
  vertical_energy *= scale;
  float magnitude = length(vec2(avg_gx, avg_gy));
  float orientation = atan(avg_gy, avg_gx);
  uint edge_glyph = directionalGlyph(avg_gy, magnitude, orientation, horizontal_energy, vertical_energy);
  if (edge_glyph == 0u) {
    return;
  }
  if (params.table_count == 0u) {
    output_glyphs[out_index] = edge_glyph;
    return;
  }

  float feature_norm = 0.0;
  for (uint i = 0u; i < kShapeRegionCount; ++i) {
    if (samples[i] > 0u) {
      features[i] /= float(samples[i]);
    }
    feature_norm += features[i] * features[i];
  }
  if (feature_norm == 0.0) {
    output_glyphs[out_index] = glyph_codes[0];
    return;
  }

  float best_score = -3.402823466e+38;
  uint best_glyph = glyph_codes[0];
  for (uint entry = 0u; entry < params.table_count; ++entry) {
    float dot_value = 0.0;
    float entry_norm = 0.0;
    for (uint i = 0u; i < kShapeRegionCount; ++i) {
      float value = glyph_features[entry * kShapeRegionCount + i];
      dot_value += features[i] * value;
      entry_norm += value * value;
    }
    if (entry_norm == 0.0) {
      continue;
    }
    float score = dot_value / sqrt(feature_norm * entry_norm);
    if (score > best_score) {
      best_score = score;
      best_glyph = glyph_codes[entry];
    }
  }
  output_glyphs[out_index] = best_glyph;
}
)GLSL";

void checkVk(VkResult result, const char* label) {
  if (result != VK_SUCCESS) {
    throw std::runtime_error(std::string(label) + " failed");
  }
}

std::vector<VkExtensionProperties> instanceExtensions() {
  uint32_t count = 0;
  checkVk(vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr), "vkEnumerateInstanceExtensionProperties");
  std::vector<VkExtensionProperties> extensions(count);
  if (count > 0) {
    checkVk(vkEnumerateInstanceExtensionProperties(nullptr, &count, extensions.data()), "vkEnumerateInstanceExtensionProperties");
  }
  return extensions;
}

[[maybe_unused]] std::vector<VkExtensionProperties> deviceExtensions(VkPhysicalDevice device) {
  uint32_t count = 0;
  checkVk(vkEnumerateDeviceExtensionProperties(device, nullptr, &count, nullptr), "vkEnumerateDeviceExtensionProperties");
  std::vector<VkExtensionProperties> extensions(count);
  if (count > 0) {
    checkVk(vkEnumerateDeviceExtensionProperties(device, nullptr, &count, extensions.data()), "vkEnumerateDeviceExtensionProperties");
  }
  return extensions;
}

bool hasExtension(const std::vector<VkExtensionProperties>& extensions, std::string_view name) {
  return std::any_of(extensions.begin(), extensions.end(), [&](const VkExtensionProperties& extension) {
    return name == extension.extensionName;
  });
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

std::vector<uint32_t> compileComputeShader(std::string_view source) {
  ShaderCompileOptions options;
  options.stage = ShaderStage::Compute;
  options.entry_point = "main";
  const std::vector<std::uint8_t> bytes = compileGlslSourceToSpirv(source, options);
  if (bytes.empty() || bytes.size() % sizeof(uint32_t) != 0U) {
    throw std::runtime_error("invalid SPIR-V bytecode");
  }
  std::vector<uint32_t> words(bytes.size() / sizeof(uint32_t));
  std::memcpy(words.data(), bytes.data(), bytes.size());
  return words;
}

bool shaderToolchainReady() {
  static const bool ready = [] {
    try {
      (void)compileComputeShader(kShaderProbeSource);
      return true;
    } catch (...) {
      return false;
    }
  }();
  return ready;
}

class VulkanContext {
 public:
  VulkanContext(const VulkanContext&) = delete;
  VulkanContext& operator=(const VulkanContext&) = delete;

  ~VulkanContext() {
    if (device_ != VK_NULL_HANDLE) {
      (void)vkDeviceWaitIdle(device_);
      reusable_buffers_.clear();
      for (auto& [_, pipeline] : pipelines_) {
        destroyPipeline(device_, command_pool_, &pipeline);
      }
      if (command_pool_ != VK_NULL_HANDLE) {
        vkDestroyCommandPool(device_, command_pool_, nullptr);
      }
      vkDestroyDevice(device_, nullptr);
    }
    if (instance_ != VK_NULL_HANDLE) {
      vkDestroyInstance(instance_, nullptr);
    }
  }

  static std::unique_ptr<VulkanContext> create() {
    try {
      std::unique_ptr<VulkanContext> context(new VulkanContext());
      return context->ready() ? std::move(context) : nullptr;
    } catch (...) {
      return nullptr;
    }
  }

  bool ready() const noexcept {
    return instance_ != VK_NULL_HANDLE && physical_device_ != VK_NULL_HANDLE && device_ != VK_NULL_HANDLE &&
           queue_ != VK_NULL_HANDLE && command_pool_ != VK_NULL_HANDLE;
  }

  VkDevice device() const noexcept {
    return device_;
  }

  class ReusableBuffer {
   public:
    ReusableBuffer(const ReusableBuffer&) = delete;
    ReusableBuffer& operator=(const ReusableBuffer&) = delete;

    ReusableBuffer(const VulkanContext& context, std::size_t size, const void* initial_data)
        : context_(context), size_(std::max<std::size_t>(size, 4U)) {
      VkBufferCreateInfo buffer_info{
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = static_cast<VkDeviceSize>(size_),
        .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
      };
      checkVk(vkCreateBuffer(context_.device(), &buffer_info, nullptr, &buffer_), "vkCreateBuffer");

      VkMemoryRequirements requirements {};
      vkGetBufferMemoryRequirements(context_.device(), buffer_, &requirements);
      VkMemoryAllocateInfo allocate_info{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
        .memoryTypeIndex = context_.memoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
      };
      checkVk(vkAllocateMemory(context_.device(), &allocate_info, nullptr, &memory_), "vkAllocateMemory");
      checkVk(vkBindBufferMemory(context_.device(), buffer_, memory_, 0), "vkBindBufferMemory");
      if (initial_data != nullptr && size > 0) {
        upload(initial_data, size);
      }
    }

    ~ReusableBuffer() {
      if (buffer_ != VK_NULL_HANDLE) {
        vkDestroyBuffer(context_.device(), buffer_, nullptr);
      }
      if (memory_ != VK_NULL_HANDLE) {
        vkFreeMemory(context_.device(), memory_, nullptr);
      }
    }

    [[nodiscard]] std::size_t capacity() const noexcept {
      return size_;
    }

    [[nodiscard]] VkDescriptorBufferInfo descriptor() const noexcept {
      return VkDescriptorBufferInfo{.buffer = buffer_, .offset = 0, .range = static_cast<VkDeviceSize>(size_)};
    }

    void upload(const void* data, std::size_t size) {
      void* mapped = nullptr;
      checkVk(vkMapMemory(context_.device(), memory_, 0, static_cast<VkDeviceSize>(size), 0, &mapped), "vkMapMemory");
      std::memcpy(mapped, data, size);
      vkUnmapMemory(context_.device(), memory_);
    }

    void download(void* data, std::size_t size) const {
      void* mapped = nullptr;
      checkVk(vkMapMemory(context_.device(), memory_, 0, static_cast<VkDeviceSize>(size), 0, &mapped), "vkMapMemory");
      std::memcpy(data, mapped, size);
      vkUnmapMemory(context_.device(), memory_);
    }

   private:
    const VulkanContext& context_;
    VkBuffer buffer_ = VK_NULL_HANDLE;
    VkDeviceMemory memory_ = VK_NULL_HANDLE;
    std::size_t size_ = 0;
  };

  ReusableBuffer& reusableBuffer(std::string_view key, std::size_t size, const void* initial_data) {
    const std::size_t required_size = std::max<std::size_t>(size, 4U);
    std::unique_ptr<ReusableBuffer>& buffer = reusable_buffers_[std::string(key)];
    if (!buffer || buffer->capacity() < required_size) {
      buffer = std::make_unique<ReusableBuffer>(*this, size, initial_data);
    } else if (initial_data != nullptr && size > 0) {
      buffer->upload(initial_data, size);
    }
    return *buffer;
  }

  uint32_t memoryType(uint32_t type_bits, VkMemoryPropertyFlags flags) const {
    VkPhysicalDeviceMemoryProperties properties {};
    vkGetPhysicalDeviceMemoryProperties(physical_device_, &properties);
    for (uint32_t index = 0; index < properties.memoryTypeCount; ++index) {
      if ((type_bits & (1U << index)) != 0U && (properties.memoryTypes[index].propertyFlags & flags) == flags) {
        return index;
      }
    }
    throw std::runtime_error("no compatible Vulkan memory type");
  }

  void runCompute(std::string_view source, const std::vector<VkDescriptorBufferInfo>& descriptors, uint32_t groups_x, uint32_t groups_y) const {
    try {
      runComputeCached(source, descriptors, groups_x, groups_y);
      return;
    } catch (...) {
      // Retry the established transient setup if this driver rejects cached
      // state. A second failure propagates to the caller's CPU fallback.
    }

    const std::vector<uint32_t> spirv = compileComputeShader(source);

    VkShaderModule shader = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptor_layout = VK_NULL_HANDLE;
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkDescriptorPool descriptor_pool = VK_NULL_HANDLE;
    VkCommandBuffer command_buffer = VK_NULL_HANDLE;

    const auto cleanup = [&] {
      if (command_buffer != VK_NULL_HANDLE) {
        vkFreeCommandBuffers(device_, command_pool_, 1, &command_buffer);
      }
      if (descriptor_pool != VK_NULL_HANDLE) {
        vkDestroyDescriptorPool(device_, descriptor_pool, nullptr);
      }
      if (pipeline != VK_NULL_HANDLE) {
        vkDestroyPipeline(device_, pipeline, nullptr);
      }
      if (pipeline_layout != VK_NULL_HANDLE) {
        vkDestroyPipelineLayout(device_, pipeline_layout, nullptr);
      }
      if (descriptor_layout != VK_NULL_HANDLE) {
        vkDestroyDescriptorSetLayout(device_, descriptor_layout, nullptr);
      }
      if (shader != VK_NULL_HANDLE) {
        vkDestroyShaderModule(device_, shader, nullptr);
      }
    };

    try {
      VkShaderModuleCreateInfo shader_info{
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = spirv.size() * sizeof(uint32_t),
        .pCode = spirv.data(),
      };
      checkVk(vkCreateShaderModule(device_, &shader_info, nullptr, &shader), "vkCreateShaderModule");

      std::vector<VkDescriptorSetLayoutBinding> bindings;
      bindings.reserve(descriptors.size());
      for (uint32_t index = 0; index < descriptors.size(); ++index) {
        bindings.push_back(VkDescriptorSetLayoutBinding{
          .binding = index,
          .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
          .descriptorCount = 1,
          .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
        });
      }
      VkDescriptorSetLayoutCreateInfo layout_info{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = static_cast<uint32_t>(bindings.size()),
        .pBindings = bindings.data(),
      };
      checkVk(vkCreateDescriptorSetLayout(device_, &layout_info, nullptr, &descriptor_layout), "vkCreateDescriptorSetLayout");

      VkPipelineLayoutCreateInfo pipeline_layout_info{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &descriptor_layout,
      };
      checkVk(vkCreatePipelineLayout(device_, &pipeline_layout_info, nullptr, &pipeline_layout), "vkCreatePipelineLayout");

      VkComputePipelineCreateInfo pipeline_info{
        .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = VkPipelineShaderStageCreateInfo{
          .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
          .stage = VK_SHADER_STAGE_COMPUTE_BIT,
          .module = shader,
          .pName = "main",
        },
        .layout = pipeline_layout,
      };
      checkVk(vkCreateComputePipelines(device_, VK_NULL_HANDLE, 1, &pipeline_info, nullptr, &pipeline), "vkCreateComputePipelines");

      VkDescriptorPoolSize pool_size{
        .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = static_cast<uint32_t>(descriptors.size()),
      };
      VkDescriptorPoolCreateInfo pool_info{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
      };
      checkVk(vkCreateDescriptorPool(device_, &pool_info, nullptr, &descriptor_pool), "vkCreateDescriptorPool");

      VkDescriptorSet descriptor_set = VK_NULL_HANDLE;
      VkDescriptorSetAllocateInfo descriptor_allocate_info{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &descriptor_layout,
      };
      checkVk(vkAllocateDescriptorSets(device_, &descriptor_allocate_info, &descriptor_set), "vkAllocateDescriptorSets");

      std::vector<VkWriteDescriptorSet> writes;
      writes.reserve(descriptors.size());
      for (uint32_t index = 0; index < descriptors.size(); ++index) {
        writes.push_back(VkWriteDescriptorSet{
          .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          .dstSet = descriptor_set,
          .dstBinding = index,
          .descriptorCount = 1,
          .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
          .pBufferInfo = &descriptors[index],
        });
      }
      vkUpdateDescriptorSets(device_, static_cast<uint32_t>(writes.size()), writes.data(), 0, nullptr);

      VkCommandBufferAllocateInfo command_buffer_info{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool_,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
      };
      checkVk(vkAllocateCommandBuffers(device_, &command_buffer_info, &command_buffer), "vkAllocateCommandBuffers");

      VkCommandBufferBeginInfo begin_info{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
      };
      checkVk(vkBeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer");
      vkCmdBindPipeline(command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
      vkCmdBindDescriptorSets(command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout, 0, 1, &descriptor_set, 0, nullptr);
      vkCmdDispatch(command_buffer, groups_x, groups_y, 1);
      checkVk(vkEndCommandBuffer(command_buffer), "vkEndCommandBuffer");

      VkSubmitInfo submit_info{
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
      };
      checkVk(vkQueueSubmit(queue_, 1, &submit_info, VK_NULL_HANDLE), "vkQueueSubmit");
      checkVk(vkQueueWaitIdle(queue_), "vkQueueWaitIdle");
      cleanup();
    } catch (...) {
      cleanup();
      throw;
    }
  }

 private:
  struct ComputePipeline {
    uint32_t descriptor_count = 0;
    VkShaderModule shader = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptor_layout = VK_NULL_HANDLE;
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkDescriptorPool descriptor_pool = VK_NULL_HANDLE;
    VkCommandBuffer command_buffer = VK_NULL_HANDLE;
  };

  static void destroyPipeline(VkDevice device, VkCommandPool command_pool, ComputePipeline* pipeline) {
    if (pipeline->command_buffer != VK_NULL_HANDLE) {
      vkFreeCommandBuffers(device, command_pool, 1, &pipeline->command_buffer);
    }
    if (pipeline->descriptor_pool != VK_NULL_HANDLE) {
      vkDestroyDescriptorPool(device, pipeline->descriptor_pool, nullptr);
    }
    if (pipeline->pipeline != VK_NULL_HANDLE) {
      vkDestroyPipeline(device, pipeline->pipeline, nullptr);
    }
    if (pipeline->pipeline_layout != VK_NULL_HANDLE) {
      vkDestroyPipelineLayout(device, pipeline->pipeline_layout, nullptr);
    }
    if (pipeline->descriptor_layout != VK_NULL_HANDLE) {
      vkDestroyDescriptorSetLayout(device, pipeline->descriptor_layout, nullptr);
    }
    if (pipeline->shader != VK_NULL_HANDLE) {
      vkDestroyShaderModule(device, pipeline->shader, nullptr);
    }
    *pipeline = ComputePipeline{};
  }

  ComputePipeline& computePipeline(std::string_view source, uint32_t descriptor_count) const {
    const auto [iterator, inserted] = pipelines_.try_emplace(std::string(source));
    ComputePipeline& cached = iterator->second;
    if (!inserted) {
      if (cached.descriptor_count != descriptor_count) {
        throw std::runtime_error("Vulkan compute shader descriptor count changed");
      }
      return cached;
    }

    cached.descriptor_count = descriptor_count;
    try {
      const std::vector<uint32_t> spirv = compileComputeShader(source);
      VkShaderModuleCreateInfo shader_info{
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = spirv.size() * sizeof(uint32_t),
        .pCode = spirv.data(),
      };
      checkVk(vkCreateShaderModule(device_, &shader_info, nullptr, &cached.shader), "vkCreateShaderModule");

      std::vector<VkDescriptorSetLayoutBinding> bindings;
      bindings.reserve(descriptor_count);
      for (uint32_t index = 0; index < descriptor_count; ++index) {
        bindings.push_back(VkDescriptorSetLayoutBinding{
          .binding = index,
          .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
          .descriptorCount = 1,
          .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
        });
      }
      VkDescriptorSetLayoutCreateInfo layout_info{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = descriptor_count,
        .pBindings = bindings.data(),
      };
      checkVk(vkCreateDescriptorSetLayout(device_, &layout_info, nullptr, &cached.descriptor_layout), "vkCreateDescriptorSetLayout");

      VkPipelineLayoutCreateInfo pipeline_layout_info{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &cached.descriptor_layout,
      };
      checkVk(vkCreatePipelineLayout(device_, &pipeline_layout_info, nullptr, &cached.pipeline_layout), "vkCreatePipelineLayout");

      VkComputePipelineCreateInfo pipeline_info{
        .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = VkPipelineShaderStageCreateInfo{
          .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
          .stage = VK_SHADER_STAGE_COMPUTE_BIT,
          .module = cached.shader,
          .pName = "main",
        },
        .layout = cached.pipeline_layout,
      };
      checkVk(vkCreateComputePipelines(device_, VK_NULL_HANDLE, 1, &pipeline_info, nullptr, &cached.pipeline), "vkCreateComputePipelines");

      VkDescriptorPoolSize pool_size{
        .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = descriptor_count,
      };
      VkDescriptorPoolCreateInfo pool_info{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
      };
      checkVk(vkCreateDescriptorPool(device_, &pool_info, nullptr, &cached.descriptor_pool), "vkCreateDescriptorPool");

      VkCommandBufferAllocateInfo command_buffer_info{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool_,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
      };
      checkVk(vkAllocateCommandBuffers(device_, &command_buffer_info, &cached.command_buffer), "vkAllocateCommandBuffers");
      return cached;
    } catch (...) {
      destroyPipeline(device_, command_pool_, &cached);
      pipelines_.erase(iterator);
      throw;
    }
  }

  void runComputeCached(std::string_view source, const std::vector<VkDescriptorBufferInfo>& descriptors, uint32_t groups_x, uint32_t groups_y) const {
    ComputePipeline& cached = computePipeline(source, static_cast<uint32_t>(descriptors.size()));
    checkVk(vkResetDescriptorPool(device_, cached.descriptor_pool, 0), "vkResetDescriptorPool");

    VkDescriptorSet descriptor_set = VK_NULL_HANDLE;
    VkDescriptorSetAllocateInfo descriptor_allocate_info{
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool = cached.descriptor_pool,
      .descriptorSetCount = 1,
      .pSetLayouts = &cached.descriptor_layout,
    };
    checkVk(vkAllocateDescriptorSets(device_, &descriptor_allocate_info, &descriptor_set), "vkAllocateDescriptorSets");

    std::vector<VkWriteDescriptorSet> writes;
    writes.reserve(descriptors.size());
    for (uint32_t index = 0; index < descriptors.size(); ++index) {
      writes.push_back(VkWriteDescriptorSet{
        .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = index,
        .descriptorCount = 1,
        .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .pBufferInfo = &descriptors[index],
      });
    }
    vkUpdateDescriptorSets(device_, static_cast<uint32_t>(writes.size()), writes.data(), 0, nullptr);

    checkVk(vkResetCommandBuffer(cached.command_buffer, 0), "vkResetCommandBuffer");
    VkCommandBufferBeginInfo begin_info{
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    checkVk(vkBeginCommandBuffer(cached.command_buffer, &begin_info), "vkBeginCommandBuffer");
    vkCmdBindPipeline(cached.command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE, cached.pipeline);
    vkCmdBindDescriptorSets(cached.command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE, cached.pipeline_layout, 0, 1, &descriptor_set, 0, nullptr);
    vkCmdDispatch(cached.command_buffer, groups_x, groups_y, 1);
    checkVk(vkEndCommandBuffer(cached.command_buffer), "vkEndCommandBuffer");

    VkSubmitInfo submit_info{
      .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
      .commandBufferCount = 1,
      .pCommandBuffers = &cached.command_buffer,
    };
    checkVk(vkQueueSubmit(queue_, 1, &submit_info, VK_NULL_HANDLE), "vkQueueSubmit");
    checkVk(vkQueueWaitIdle(queue_), "vkQueueWaitIdle");
  }

  VulkanContext() {
    const std::vector<VkExtensionProperties> extensions = instanceExtensions();
    std::vector<const char*> enabled_extensions;
    VkInstanceCreateFlags flags = 0;
    if (hasExtension(extensions, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)) {
      enabled_extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
      flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }

    VkApplicationInfo app_info{
      .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
      .pApplicationName = "strok",
      .applicationVersion = VK_MAKE_VERSION(0, 0, 0),
      .pEngineName = "strok",
      .engineVersion = VK_MAKE_VERSION(0, 0, 0),
      .apiVersion = VK_API_VERSION_1_3,
    };
    VkInstanceCreateInfo instance_info{
      .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
      .flags = flags,
      .pApplicationInfo = &app_info,
      .enabledExtensionCount = static_cast<uint32_t>(enabled_extensions.size()),
      .ppEnabledExtensionNames = enabled_extensions.data(),
    };
    checkVk(vkCreateInstance(&instance_info, nullptr, &instance_), "vkCreateInstance");

    uint32_t physical_count = 0;
    checkVk(vkEnumeratePhysicalDevices(instance_, &physical_count, nullptr), "vkEnumeratePhysicalDevices");
    if (physical_count == 0) {
      throw std::runtime_error("no Vulkan physical devices");
    }
    std::vector<VkPhysicalDevice> physical_devices(physical_count);
    checkVk(vkEnumeratePhysicalDevices(instance_, &physical_count, physical_devices.data()), "vkEnumeratePhysicalDevices");
    for (VkPhysicalDevice candidate : physical_devices) {
      uint32_t queue_count = 0;
      vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queue_count, nullptr);
      std::vector<VkQueueFamilyProperties> queues(queue_count);
      vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queue_count, queues.data());
      for (uint32_t index = 0; index < queues.size(); ++index) {
        if ((queues[index].queueFlags & VK_QUEUE_COMPUTE_BIT) != 0U) {
          physical_device_ = candidate;
          queue_family_ = index;
          break;
        }
      }
      if (physical_device_ != VK_NULL_HANDLE) {
        break;
      }
    }
    if (physical_device_ == VK_NULL_HANDLE) {
      throw std::runtime_error("no Vulkan compute queue");
    }

    std::vector<const char*> device_extensions;
#ifdef VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME
    const std::vector<VkExtensionProperties> physical_extensions = deviceExtensions(physical_device_);
    if (hasExtension(physical_extensions, VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME)) {
      device_extensions.push_back(VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME);
    }
#endif
    const float priority = 1.0F;
    VkDeviceQueueCreateInfo queue_info{
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = queue_family_,
      .queueCount = 1,
      .pQueuePriorities = &priority,
    };
    VkDeviceCreateInfo device_info{
      .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount = 1,
      .pQueueCreateInfos = &queue_info,
      .enabledExtensionCount = static_cast<uint32_t>(device_extensions.size()),
      .ppEnabledExtensionNames = device_extensions.data(),
    };
    checkVk(vkCreateDevice(physical_device_, &device_info, nullptr, &device_), "vkCreateDevice");
    vkGetDeviceQueue(device_, queue_family_, 0, &queue_);

    VkCommandPoolCreateInfo command_pool_info{
      .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
      .queueFamilyIndex = queue_family_,
    };
    checkVk(vkCreateCommandPool(device_, &command_pool_info, nullptr, &command_pool_), "vkCreateCommandPool");
  }

  VkInstance instance_ = VK_NULL_HANDLE;
  VkPhysicalDevice physical_device_ = VK_NULL_HANDLE;
  VkDevice device_ = VK_NULL_HANDLE;
  VkQueue queue_ = VK_NULL_HANDLE;
  VkCommandPool command_pool_ = VK_NULL_HANDLE;
  uint32_t queue_family_ = 0;
  std::unordered_map<std::string, std::unique_ptr<ReusableBuffer>> reusable_buffers_;
  mutable std::unordered_map<std::string, ComputePipeline> pipelines_;
};

thread_local VulkanContext* active_vulkan_context = nullptr;

VulkanContext* vulkanContext() {
  if (active_vulkan_context != nullptr) {
    return active_vulkan_context;
  }
  static std::unique_ptr<VulkanContext> context = VulkanContext::create();
  return context.get();
}

std::vector<float> luminanceAsFloat(const LuminanceField& field) {
  std::vector<float> luminance(field.values.size());
  for (std::size_t index = 0; index < field.values.size(); ++index) {
    luminance[index] = static_cast<float>(field.values[index]);
  }
  return luminance;
}

bool validField(const LuminanceField& field) {
  return field.width > 0 && field.height > 0 &&
         field.values.size() == static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height);
}

std::optional<GpuStructureGlyphs> computeStructureGlyphsGpuImpl(const Frame* frame, const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) {
  if (!validField(field)) {
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
  if (cols > field.width || rows > field.height || !gpuSobelAvailable()) {
    return std::nullopt;
  }

  try {
    VulkanContext* context = vulkanContext();
    if (context == nullptr) {
      return std::nullopt;
    }
    const std::vector<float> luminance = luminanceAsFloat(field);
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

    std::vector<uint32_t> rgb_words;
    if (frame != nullptr) {
      rgb_words.reserve(frame->rgb.size());
      for (const uint8_t value : frame->rgb) {
        rgb_words.push_back(static_cast<uint32_t>(value));
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
    const float dummy_feature = 0.0F;
    const uint32_t dummy_word = 0;
    auto& luminance_buffer = context->reusableBuffer("structure:luminance", luminance.size() * sizeof(float), luminance.data());
    auto& feature_buffer = context->reusableBuffer("structure:features", glyph_features.empty() ? sizeof(dummy_feature) : glyph_features.size() * sizeof(float),
                                                    glyph_features.empty() ? static_cast<const void*>(&dummy_feature) : static_cast<const void*>(glyph_features.data()));
    auto& code_buffer = context->reusableBuffer("structure:codes", glyph_codes.empty() ? sizeof(dummy_word) : glyph_codes.size() * sizeof(uint32_t),
                                                 glyph_codes.empty() ? static_cast<const void*>(&dummy_word) : static_cast<const void*>(glyph_codes.data()));
    auto& output_buffer = context->reusableBuffer("structure:output", output.size() * sizeof(uint32_t), output.data());
    auto& output_color_buffer = context->reusableBuffer("structure:colors", output_colors.size() * sizeof(uint32_t), output_colors.data());
    auto& rgb_buffer = context->reusableBuffer("structure:rgb", rgb_words.empty() ? sizeof(dummy_word) : rgb_words.size() * sizeof(uint32_t),
                                                rgb_words.empty() ? static_cast<const void*>(&dummy_word) : static_cast<const void*>(rgb_words.data()));
    auto& params_buffer = context->reusableBuffer("structure:params", sizeof(params), &params);
    std::vector<VkDescriptorBufferInfo> descriptors{
      luminance_buffer.descriptor(),
      feature_buffer.descriptor(),
      code_buffer.descriptor(),
      output_buffer.descriptor(),
      output_color_buffer.descriptor(),
      rgb_buffer.descriptor(),
      params_buffer.descriptor(),
    };
    context->runCompute(kStructureShaderSource, descriptors,
                        (static_cast<uint32_t>(cols) + kLocalSize - 1U) / kLocalSize,
                        (static_cast<uint32_t>(rows) + kLocalSize - 1U) / kLocalSize);
    output_buffer.download(output.data(), output.size() * sizeof(uint32_t));
    output_color_buffer.download(output_colors.data(), output_colors.size() * sizeof(uint32_t));

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
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace

class VulkanAnalysisContext final : public GpuSobelContext {
 public:
  explicit VulkanAnalysisContext(std::unique_ptr<VulkanContext> context)
      : context_(std::move(context)) {}

  std::optional<LuminanceField> differenceOfGaussians(const LuminanceField& field, DogOptions options) override {
    const ScopedActivation activation(*context_);
    return differenceOfGaussiansGpu(field, options);
  }

  std::optional<GradientField> sobelGradients(const LuminanceField& field) override {
    const ScopedActivation activation(*context_);
    return computeSobelGradientsGpu(field);
  }

  std::optional<GpuStructureGlyphs> structureGlyphs(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) override {
    const ScopedActivation activation(*context_);
    return computeStructureGlyphsGpu(field, cols, rows, edge_threshold, shape_table);
  }

 private:
  class ScopedActivation {
   public:
    explicit ScopedActivation(VulkanContext& context)
        : previous_(active_vulkan_context) {
      active_vulkan_context = &context;
    }

    ~ScopedActivation() {
      active_vulkan_context = previous_;
    }

    ScopedActivation(const ScopedActivation&) = delete;
    ScopedActivation& operator=(const ScopedActivation&) = delete;

   private:
    VulkanContext* previous_ = nullptr;
  };

  std::unique_ptr<VulkanContext> context_;
};

std::unique_ptr<GpuSobelContext> createGpuSobelContext() {
  if (!shaderToolchainReady()) {
    return nullptr;
  }
  std::unique_ptr<VulkanContext> context = VulkanContext::create();
  if (!context) {
    return nullptr;
  }
  return std::make_unique<VulkanAnalysisContext>(std::move(context));
}

bool gpuSobelAvailable() {
  return vulkanContext() != nullptr && shaderToolchainReady();
}

const char* gpuSobelBackendName() {
  return "Vulkan";
}

std::optional<LuminanceField> differenceOfGaussiansGpu(const LuminanceField& field, DogOptions options) {
  if (!options.enabled()) {
    return field;
  }
  if (!validField(field)) {
    throw std::invalid_argument("invalid luminance field");
  }
  if (options.threshold < 0.0) {
    throw std::invalid_argument("DoG threshold must be non-negative");
  }
  if (!gpuSobelAvailable()) {
    return std::nullopt;
  }

  try {
    VulkanContext* context = vulkanContext();
    if (context == nullptr) {
      return std::nullopt;
    }
    const std::vector<float> luminance = luminanceAsFloat(field);
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
    auto& luminance_buffer = context->reusableBuffer("dog:luminance", luminance.size() * sizeof(float), luminance.data());
    auto& kernel1_buffer = context->reusableBuffer("dog:kernel-one", kernel1.size() * sizeof(float), kernel1.data());
    auto& kernel2_buffer = context->reusableBuffer("dog:kernel-two", kernel2.size() * sizeof(float), kernel2.data());
    auto& output_buffer = context->reusableBuffer("dog:output", output.size() * sizeof(float), output.data());
    auto& params_buffer = context->reusableBuffer("dog:params", sizeof(params), &params);
    std::vector<VkDescriptorBufferInfo> descriptors{
      luminance_buffer.descriptor(),
      kernel1_buffer.descriptor(),
      kernel2_buffer.descriptor(),
      output_buffer.descriptor(),
      params_buffer.descriptor(),
    };
    context->runCompute(kDogShaderSource, descriptors,
                        (static_cast<uint32_t>(field.width) + kLocalSize - 1U) / kLocalSize,
                        (static_cast<uint32_t>(field.height) + kLocalSize - 1U) / kLocalSize);
    output_buffer.download(output.data(), output.size() * sizeof(float));
    LuminanceField result;
    result.width = field.width;
    result.height = field.height;
    result.values.reserve(output.size());
    for (const float value : output) {
      result.values.push_back(static_cast<double>(value));
    }
    return result;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<GradientField> computeSobelGradientsGpu(const LuminanceField& field) {
  if (!validField(field)) {
    throw std::invalid_argument("invalid luminance field");
  }
  if (!gpuSobelAvailable()) {
    return std::nullopt;
  }

  try {
    VulkanContext* context = vulkanContext();
    if (context == nullptr) {
      return std::nullopt;
    }
    const std::vector<float> luminance = luminanceAsFloat(field);
    std::vector<PackedGradient> packed(field.values.size());
    const uint32_t dimensions[2] {
      static_cast<uint32_t>(field.width),
      static_cast<uint32_t>(field.height),
    };
    auto& luminance_buffer = context->reusableBuffer("sobel:luminance", luminance.size() * sizeof(float), luminance.data());
    auto& gradient_buffer = context->reusableBuffer("sobel:gradient", packed.size() * sizeof(PackedGradient), packed.data());
    auto& dimensions_buffer = context->reusableBuffer("sobel:dimensions", sizeof(dimensions), dimensions);
    std::vector<VkDescriptorBufferInfo> descriptors{
      luminance_buffer.descriptor(),
      gradient_buffer.descriptor(),
      dimensions_buffer.descriptor(),
    };
    context->runCompute(kSobelShaderSource, descriptors,
                        (static_cast<uint32_t>(field.width) + kLocalSize - 1U) / kLocalSize,
                        (static_cast<uint32_t>(field.height) + kLocalSize - 1U) / kLocalSize);
    gradient_buffer.download(packed.data(), packed.size() * sizeof(PackedGradient));
    GradientField gradients;
    gradients.width = field.width;
    gradients.height = field.height;
    gradients.values.reserve(packed.size());
    for (const PackedGradient gradient : packed) {
      gradients.values.push_back(Gradient{.gx = static_cast<double>(gradient.gx), .gy = static_cast<double>(gradient.gy)});
    }
    return gradients;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) {
  return computeStructureGlyphsGpuImpl(nullptr, field, cols, rows, edge_threshold, shape_table);
}

std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const Frame& frame, const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table) {
  return computeStructureGlyphsGpuImpl(&frame, field, cols, rows, edge_threshold, shape_table);
}

}  // namespace strok
