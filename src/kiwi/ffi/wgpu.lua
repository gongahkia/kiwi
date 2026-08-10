local ffi = require("ffi")

-- This intentionally narrow declaration set is transcribed from the pinned
-- wgpu-native v29.0.1.1 release header: include/webgpu/webgpu.h.
ffi.cdef[[
typedef uint32_t WGPUBool;
typedef uint64_t WGPUFlags;
typedef uint64_t WGPUBufferUsage;
typedef uint64_t WGPUTextureUsage;
typedef uint64_t WGPUColorWriteMask;
typedef uint64_t WGPUShaderStage;
typedef struct WGPUAdapterImpl* WGPUAdapter;
typedef struct WGPUBindGroupImpl* WGPUBindGroup;
typedef struct WGPUBindGroupLayoutImpl* WGPUBindGroupLayout;
typedef struct WGPUBufferImpl* WGPUBuffer;
typedef struct WGPUCommandBufferImpl* WGPUCommandBuffer;
typedef struct WGPUCommandEncoderImpl* WGPUCommandEncoder;
typedef struct WGPUDeviceImpl* WGPUDevice;
typedef struct WGPUInstanceImpl* WGPUInstance;
typedef struct WGPUPipelineLayoutImpl* WGPUPipelineLayout;
typedef struct WGPUQueueImpl* WGPUQueue;
typedef struct WGPURenderPassEncoderImpl* WGPURenderPassEncoder;
typedef struct WGPURenderPipelineImpl* WGPURenderPipeline;
typedef struct WGPUSamplerImpl* WGPUSampler;
typedef struct WGPUShaderModuleImpl* WGPUShaderModule;
typedef struct WGPUSurfaceImpl* WGPUSurface;
typedef struct WGPUTextureImpl* WGPUTexture;
typedef struct WGPUTextureViewImpl* WGPUTextureView;
typedef struct GLFWwindow GLFWwindow;

typedef struct { const char* data; size_t length; } WGPUStringView;
typedef struct WGPUChainedStruct { struct WGPUChainedStruct* next; uint32_t sType; } WGPUChainedStruct;
typedef struct { uint64_t id; } WGPUFuture;
typedef struct { WGPUFuture future; WGPUBool completed; } WGPUFutureWaitInfo;
typedef struct { WGPUChainedStruct* nextInChain; size_t requiredFeatureCount; const uint32_t* requiredFeatures; const void* requiredLimits; } WGPUInstanceDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t featureLevel; uint32_t powerPreference; WGPUBool forceFallbackAdapter; uint32_t backendType; WGPUSurface compatibleSurface; } WGPURequestAdapterOptions;
typedef void (*WGPURequestAdapterCallback)(uint32_t status, WGPUAdapter adapter, WGPUStringView message, void* userdata1, void* userdata2);
typedef void (*WGPURequestDeviceCallback)(uint32_t status, WGPUDevice device, WGPUStringView message, void* userdata1, void* userdata2);
typedef void (*WGPUDeviceLostCallback)(const WGPUDevice* device, uint32_t reason, WGPUStringView message, void* userdata1, void* userdata2);
typedef void (*WGPUUncapturedErrorCallback)(const WGPUDevice* device, uint32_t type, WGPUStringView message, void* userdata1, void* userdata2);
typedef struct { WGPUChainedStruct* nextInChain; uint32_t mode; WGPURequestAdapterCallback callback; void* userdata1; void* userdata2; } WGPURequestAdapterCallbackInfo;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t mode; WGPURequestDeviceCallback callback; void* userdata1; void* userdata2; } WGPURequestDeviceCallbackInfo;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t mode; WGPUDeviceLostCallback callback; void* userdata1; void* userdata2; } WGPUDeviceLostCallbackInfo;
typedef struct { WGPUChainedStruct* nextInChain; WGPUUncapturedErrorCallback callback; void* userdata1; void* userdata2; } WGPUUncapturedErrorCallbackInfo;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; } WGPUQueueDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; size_t requiredFeatureCount; const uint32_t* requiredFeatures; const void* requiredLimits; WGPUQueueDescriptor defaultQueue; WGPUDeviceLostCallbackInfo deviceLostCallbackInfo; WGPUUncapturedErrorCallbackInfo uncapturedErrorCallbackInfo; } WGPUDeviceDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView vendor; WGPUStringView architecture; WGPUStringView device; WGPUStringView description; uint32_t backendType; uint32_t adapterType; uint32_t vendorID; uint32_t deviceID; uint32_t subgroupMinSize; uint32_t subgroupMaxSize; } WGPUAdapterInfo;
typedef struct { WGPUChainedStruct* nextInChain; WGPUTextureUsage usages; size_t formatCount; const uint32_t* formats; size_t presentModeCount; const uint32_t* presentModes; size_t alphaModeCount; const uint32_t* alphaModes; } WGPUSurfaceCapabilities;
typedef struct { WGPUChainedStruct* nextInChain; WGPUDevice device; uint32_t format; WGPUTextureUsage usage; uint32_t width; uint32_t height; size_t viewFormatCount; const uint32_t* viewFormats; uint32_t alphaMode; uint32_t presentMode; } WGPUSurfaceConfiguration;
typedef struct { WGPUChainedStruct* nextInChain; WGPUTexture texture; uint32_t status; } WGPUSurfaceTexture;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; WGPUBufferUsage usage; uint64_t size; WGPUBool mappedAtCreation; } WGPUBufferDescriptor;
typedef struct { uint32_t width; uint32_t height; uint32_t depthOrArrayLayers; } WGPUExtent3D;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; WGPUTextureUsage usage; uint32_t dimension; WGPUExtent3D size; uint32_t format; uint32_t mipLevelCount; uint32_t sampleCount; size_t viewFormatCount; const uint32_t* viewFormats; } WGPUTextureDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; uint32_t format; uint32_t dimension; uint32_t baseMipLevel; uint32_t mipLevelCount; uint32_t baseArrayLayer; uint32_t arrayLayerCount; uint32_t aspect; WGPUTextureUsage usage; } WGPUTextureViewDescriptor;
typedef struct { WGPUTexture texture; uint32_t mipLevel; struct { uint32_t x; uint32_t y; uint32_t z; } origin; uint32_t aspect; } WGPUTexelCopyTextureInfo;
typedef struct { uint64_t offset; uint32_t bytesPerRow; uint32_t rowsPerImage; } WGPUTexelCopyBufferLayout;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; uint32_t addressModeU; uint32_t addressModeV; uint32_t addressModeW; uint32_t magFilter; uint32_t minFilter; uint32_t mipmapFilter; float lodMinClamp; float lodMaxClamp; uint32_t compare; uint16_t maxAnisotropy; } WGPUSamplerDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t type; WGPUBool hasDynamicOffset; uint64_t minBindingSize; } WGPUBufferBindingLayout;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t type; } WGPUSamplerBindingLayout;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t sampleType; uint32_t viewDimension; WGPUBool multisampled; } WGPUTextureBindingLayout;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t access; uint32_t format; uint32_t viewDimension; } WGPUStorageTextureBindingLayout;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t binding; WGPUShaderStage visibility; uint32_t bindingArraySize; WGPUBufferBindingLayout buffer; WGPUSamplerBindingLayout sampler; WGPUTextureBindingLayout texture; WGPUStorageTextureBindingLayout storageTexture; } WGPUBindGroupLayoutEntry;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; size_t entryCount; const WGPUBindGroupLayoutEntry* entries; } WGPUBindGroupLayoutDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t binding; WGPUBuffer buffer; uint64_t offset; uint64_t size; WGPUSampler sampler; WGPUTextureView textureView; } WGPUBindGroupEntry;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; WGPUBindGroupLayout layout; size_t entryCount; const WGPUBindGroupEntry* entries; } WGPUBindGroupDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; size_t bindGroupLayoutCount; const WGPUBindGroupLayout* bindGroupLayouts; uint32_t immediateSize; } WGPUPipelineLayoutDescriptor;
typedef struct { WGPUChainedStruct chain; WGPUStringView code; } WGPUShaderSourceWGSL;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; } WGPUShaderModuleDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; WGPUShaderModule module; WGPUStringView entryPoint; size_t constantCount; const void* constants; size_t bufferCount; const void* buffers; } WGPUVertexState;
typedef struct { WGPUChainedStruct* nextInChain; WGPUShaderModule module; WGPUStringView entryPoint; size_t constantCount; const void* constants; size_t targetCount; const struct WGPUColorTargetState* targets; } WGPUFragmentState;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t topology; uint32_t stripIndexFormat; uint32_t frontFace; uint32_t cullMode; WGPUBool unclippedDepth; } WGPUPrimitiveState;
typedef struct { WGPUChainedStruct* nextInChain; uint32_t count; uint32_t mask; WGPUBool alphaToCoverageEnabled; } WGPUMultisampleState;
typedef struct WGPUColorTargetState { WGPUChainedStruct* nextInChain; uint32_t format; const void* blend; WGPUColorWriteMask writeMask; } WGPUColorTargetState;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; WGPUPipelineLayout layout; WGPUVertexState vertex; WGPUPrimitiveState primitive; const void* depthStencil; WGPUMultisampleState multisample; const WGPUFragmentState* fragment; } WGPURenderPipelineDescriptor;
typedef struct { double r; double g; double b; double a; } WGPUColor;
typedef struct { WGPUChainedStruct* nextInChain; WGPUTextureView view; uint32_t depthSlice; WGPUTextureView resolveTarget; uint32_t loadOp; uint32_t storeOp; WGPUColor clearValue; } WGPURenderPassColorAttachment;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; size_t colorAttachmentCount; const WGPURenderPassColorAttachment* colorAttachments; const void* depthStencilAttachment; void* occlusionQuerySet; const void* timestampWrites; } WGPURenderPassDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; } WGPUCommandEncoderDescriptor;
typedef struct { WGPUChainedStruct* nextInChain; WGPUStringView label; } WGPUCommandBufferDescriptor;

WGPUInstance wgpuCreateInstance(const WGPUInstanceDescriptor* descriptor);
WGPUFuture wgpuInstanceRequestAdapter(WGPUInstance instance, const WGPURequestAdapterOptions* options, WGPURequestAdapterCallbackInfo callbackInfo);
uint32_t wgpuInstanceWaitAny(WGPUInstance instance, size_t futureCount, WGPUFutureWaitInfo* futures, uint64_t timeoutNS);
void wgpuInstanceProcessEvents(WGPUInstance instance);
void wgpuInstanceRelease(WGPUInstance instance);
WGPUFuture wgpuAdapterRequestDevice(WGPUAdapter adapter, const WGPUDeviceDescriptor* descriptor, WGPURequestDeviceCallbackInfo callbackInfo);
uint32_t wgpuAdapterGetInfo(WGPUAdapter adapter, WGPUAdapterInfo* info);
WGPUBool wgpuAdapterHasFeature(WGPUAdapter adapter, uint32_t feature);
void wgpuAdapterInfoFreeMembers(WGPUAdapterInfo adapterInfo);
void wgpuAdapterRelease(WGPUAdapter adapter);
WGPUQueue wgpuDeviceGetQueue(WGPUDevice device);
WGPUBindGroupLayout wgpuDeviceCreateBindGroupLayout(WGPUDevice device, const WGPUBindGroupLayoutDescriptor* descriptor);
WGPUBindGroup wgpuDeviceCreateBindGroup(WGPUDevice device, const WGPUBindGroupDescriptor* descriptor);
WGPUPipelineLayout wgpuDeviceCreatePipelineLayout(WGPUDevice device, const WGPUPipelineLayoutDescriptor* descriptor);
WGPUShaderModule wgpuDeviceCreateShaderModule(WGPUDevice device, const WGPUShaderModuleDescriptor* descriptor);
WGPURenderPipeline wgpuDeviceCreateRenderPipeline(WGPUDevice device, const WGPURenderPipelineDescriptor* descriptor);
WGPUBuffer wgpuDeviceCreateBuffer(WGPUDevice device, const WGPUBufferDescriptor* descriptor);
WGPUTexture wgpuDeviceCreateTexture(WGPUDevice device, const WGPUTextureDescriptor* descriptor);
WGPUSampler wgpuDeviceCreateSampler(WGPUDevice device, const WGPUSamplerDescriptor* descriptor);
WGPUCommandEncoder wgpuDeviceCreateCommandEncoder(WGPUDevice device, const WGPUCommandEncoderDescriptor* descriptor);
void wgpuDeviceDestroy(WGPUDevice device);
void wgpuDeviceRelease(WGPUDevice device);
void wgpuQueueWriteBuffer(WGPUQueue queue, WGPUBuffer buffer, uint64_t offset, const void* data, size_t size);
void wgpuQueueWriteTexture(WGPUQueue queue, const WGPUTexelCopyTextureInfo* destination, const void* data, size_t dataSize, const WGPUTexelCopyBufferLayout* dataLayout, const WGPUExtent3D* writeSize);
void wgpuQueueSubmit(WGPUQueue queue, size_t commandCount, const WGPUCommandBuffer* commands);
void wgpuQueueRelease(WGPUQueue queue);
WGPUTextureView wgpuTextureCreateView(WGPUTexture texture, const WGPUTextureViewDescriptor* descriptor);
void wgpuTextureDestroy(WGPUTexture texture);
void wgpuTextureRelease(WGPUTexture texture);
void wgpuTextureViewRelease(WGPUTextureView textureView);
void wgpuBufferDestroy(WGPUBuffer buffer);
void wgpuBufferRelease(WGPUBuffer buffer);
void wgpuSamplerRelease(WGPUSampler sampler);
void wgpuBindGroupRelease(WGPUBindGroup bindGroup);
void wgpuBindGroupLayoutRelease(WGPUBindGroupLayout layout);
void wgpuPipelineLayoutRelease(WGPUPipelineLayout layout);
void wgpuShaderModuleRelease(WGPUShaderModule module);
void wgpuRenderPipelineRelease(WGPURenderPipeline pipeline);
WGPURenderPassEncoder wgpuCommandEncoderBeginRenderPass(WGPUCommandEncoder encoder, const WGPURenderPassDescriptor* descriptor);
WGPUCommandBuffer wgpuCommandEncoderFinish(WGPUCommandEncoder encoder, const WGPUCommandBufferDescriptor* descriptor);
void wgpuCommandEncoderRelease(WGPUCommandEncoder encoder);
void wgpuCommandBufferRelease(WGPUCommandBuffer buffer);
void wgpuRenderPassEncoderSetPipeline(WGPURenderPassEncoder pass, WGPURenderPipeline pipeline);
void wgpuRenderPassEncoderSetBindGroup(WGPURenderPassEncoder pass, uint32_t groupIndex, WGPUBindGroup group, size_t dynamicOffsetCount, const uint32_t* dynamicOffsets);
void wgpuRenderPassEncoderDraw(WGPURenderPassEncoder pass, uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance);
void wgpuRenderPassEncoderEnd(WGPURenderPassEncoder pass);
void wgpuRenderPassEncoderRelease(WGPURenderPassEncoder pass);
void wgpuSurfaceConfigure(WGPUSurface surface, const WGPUSurfaceConfiguration* config);
uint32_t wgpuSurfaceGetCapabilities(WGPUSurface surface, WGPUAdapter adapter, WGPUSurfaceCapabilities* capabilities);
void wgpuSurfaceCapabilitiesFreeMembers(WGPUSurfaceCapabilities capabilities);
void wgpuSurfaceGetCurrentTexture(WGPUSurface surface, WGPUSurfaceTexture* texture);
uint32_t wgpuSurfacePresent(WGPUSurface surface);
void wgpuSurfaceUnconfigure(WGPUSurface surface);
void wgpuSurfaceRelease(WGPUSurface surface);
WGPUSurface kiwi_surface_from_glfw(WGPUInstance instance, GLFWwindow* window);
WGPUAdapter kiwi_request_adapter_sync(WGPUInstance instance, WGPUSurface surface);
WGPUDevice kiwi_request_device_sync(WGPUInstance instance, WGPUAdapter adapter);
int kiwi_timestamp_query_probe(WGPUInstance instance, WGPUAdapter adapter);
WGPUShaderModule kiwi_shader_from_wgsl(WGPUDevice device, const char* source_code);
const char* kiwi_surface_last_error(void);
void kiwi_surface_clear_error(void);
]]

local root = os.getenv("KIWI_ROOT") or "."
local library_path = os.getenv("KIWI_WGPU_LIB") or root .. "/.deps/wgpu-native-v29.0.1.1/lib/libwgpu_native.so"
local ok, library = pcall(ffi.load, library_path, true)
if not ok then
  error("Unable to load pinned wgpu-native v29.0.1.1 at " .. library_path .. "; run make bootstrap: " .. tostring(library))
end

local surface_path = root .. "/.build/native/libkiwi_surface.so"
local surface_ok, surface = pcall(ffi.load, surface_path)
if not surface_ok then
  error("Unable to load Kiwi's GLFW surface bridge at " .. surface_path .. "; run make native: " .. tostring(surface))
end

return {
  ffi = ffi,
  lib = library,
  surface = surface,
  constants = {
    surface_success_optimal = 1,
    surface_success_suboptimal = 2,
    texture_format_r8_unorm = 1,
    texture_usage_copy_dst = 0x02,
    texture_usage_texture_binding = 0x04,
    texture_usage_render_attachment = 0x10,
    buffer_usage_copy_dst = 0x08,
    buffer_usage_uniform = 0x40,
    buffer_usage_storage = 0x80,
    texture_dimension_2d = 2,
    texture_aspect_all = 1,
    texture_sample_type_float = 2,
    texture_view_dimension_2d = 2,
    sampler_binding_filtering = 2,
    buffer_binding_readonly_storage = 4,
    buffer_binding_uniform = 2,
    shader_stage_vertex = 0x01,
    shader_stage_fragment = 0x02,
    sampler_address_clamp_to_edge = 1,
    filter_nearest = 1,
    mipmap_filter_nearest = 1,
    primitive_triangle_list = 4,
    front_face_ccw = 1,
    cull_none = 1,
    color_write_all = 0x0f,
    load_clear = 2,
    load_load = 1,
    store_store = 1,
    present_fifo = 1,
    alpha_opaque = 1,
  },
}
