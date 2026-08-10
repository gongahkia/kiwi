#define _POSIX_C_SOURCE 200809L
#define GLFW_EXPOSE_NATIVE_WAYLAND
#define GLFW_EXPOSE_NATIVE_X11
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <webgpu/webgpu.h>

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>

static char kiwi_surface_error[2048];

static void kiwi_copy_message(WGPUStringView message) {
  size_t length = message.length;
  if (message.data == NULL) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "no native error message supplied");
    return;
  }
  if (length >= sizeof(kiwi_surface_error)) {
    length = sizeof(kiwi_surface_error) - 1;
  }
  snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "%.*s", (int)length, message.data);
}

typedef struct KiwiRequestResult {
  WGPUAdapter adapter;
  WGPUDevice device;
  uint32_t status;
} KiwiRequestResult;

static int kiwi_wait_for_request(WGPUInstance instance, KiwiRequestResult *result) {
  const struct timespec delay = {.tv_sec = 0, .tv_nsec = 1000000};
  for (int attempt = 0; attempt < 10000; ++attempt) {
    wgpuInstanceProcessEvents(instance);
    if (result->status != 0) {
      return 1;
    }
    nanosleep(&delay, NULL);
  }
  return 0;
}

static void kiwi_adapter_callback(WGPURequestAdapterStatus status, WGPUAdapter adapter,
                                  WGPUStringView message, void *userdata1, void *userdata2) {
  (void)userdata2;
  KiwiRequestResult *result = userdata1;
  result->status = status;
  result->adapter = adapter;
  if (status != WGPURequestAdapterStatus_Success) {
    kiwi_copy_message(message);
  }
}

static void kiwi_device_callback(WGPURequestDeviceStatus status, WGPUDevice device,
                                 WGPUStringView message, void *userdata1, void *userdata2) {
  (void)userdata2;
  KiwiRequestResult *result = userdata1;
  result->status = status;
  result->device = device;
  if (status != WGPURequestDeviceStatus_Success) {
    kiwi_copy_message(message);
  }
}

typedef struct KiwiMapResult {
  WGPUMapAsyncStatus status;
} KiwiMapResult;

static void kiwi_buffer_map_callback(WGPUMapAsyncStatus status, WGPUStringView message,
                                     void *userdata1, void *userdata2) {
  (void)userdata2;
  KiwiMapResult *result = userdata1;
  result->status = status;
  if (status != WGPUMapAsyncStatus_Success) {
    kiwi_copy_message(message);
  }
}

static void kiwi_uncaptured_error(const WGPUDevice *device, WGPUErrorType type,
                                  WGPUStringView message, void *userdata1, void *userdata2) {
  (void)device;
  (void)userdata1;
  (void)userdata2;
  snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "wgpu error %d: ", type);
  size_t prefix = strlen(kiwi_surface_error);
  if (message.data != NULL && prefix < sizeof(kiwi_surface_error) - 1) {
    size_t length = message.length;
    size_t available = sizeof(kiwi_surface_error) - prefix - 1;
    if (length > available) {
      length = available;
    }
    memcpy(kiwi_surface_error + prefix, message.data, length);
    kiwi_surface_error[prefix + length] = '\0';
  }
}

static void kiwi_device_lost(const WGPUDevice *device, WGPUDeviceLostReason reason,
                             WGPUStringView message, void *userdata1, void *userdata2) {
  (void)device;
  (void)userdata1;
  (void)userdata2;
  snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "wgpu device lost %d: ", reason);
  size_t prefix = strlen(kiwi_surface_error);
  if (message.data != NULL && prefix < sizeof(kiwi_surface_error) - 1) {
    size_t length = message.length;
    size_t available = sizeof(kiwi_surface_error) - prefix - 1;
    if (length > available) {
      length = available;
    }
    memcpy(kiwi_surface_error + prefix, message.data, length);
    kiwi_surface_error[prefix + length] = '\0';
  }
}

const char *kiwi_surface_last_error(void) {
  return kiwi_surface_error;
}

void kiwi_surface_clear_error(void) {
  kiwi_surface_error[0] = '\0';
}

WGPUSurface kiwi_surface_from_glfw(WGPUInstance instance, GLFWwindow *window) {
  WGPUSurfaceDescriptor descriptor = WGPU_SURFACE_DESCRIPTOR_INIT;
  int platform = glfwGetPlatform();

  kiwi_surface_error[0] = '\0';
  if (platform == GLFW_PLATFORM_WAYLAND) {
    WGPUSurfaceSourceWaylandSurface source = WGPU_SURFACE_SOURCE_WAYLAND_SURFACE_INIT;
    source.display = glfwGetWaylandDisplay();
    source.surface = glfwGetWaylandWindow(window);
    descriptor.nextInChain = (WGPUChainedStruct *)&source;
    return wgpuInstanceCreateSurface(instance, &descriptor);
  }
  if (platform == GLFW_PLATFORM_X11) {
    WGPUSurfaceSourceXlibWindow source = WGPU_SURFACE_SOURCE_XLIB_WINDOW_INIT;
    source.display = glfwGetX11Display();
    source.window = glfwGetX11Window(window);
    descriptor.nextInChain = (WGPUChainedStruct *)&source;
    return wgpuInstanceCreateSurface(instance, &descriptor);
  }

  snprintf(kiwi_surface_error, sizeof(kiwi_surface_error),
           "GLFW platform %d has no Kiwi M0 wgpu-native surface binding", platform);
  return NULL;
}

WGPUAdapter kiwi_request_adapter_sync(WGPUInstance instance, WGPUSurface surface) {
  KiwiRequestResult result = {0};
  WGPURequestAdapterOptions options = WGPU_REQUEST_ADAPTER_OPTIONS_INIT;
  WGPURequestAdapterCallbackInfo callback = WGPU_REQUEST_ADAPTER_CALLBACK_INFO_INIT;

  kiwi_surface_error[0] = '\0';
  options.featureLevel = WGPUFeatureLevel_Core;
  options.backendType = WGPUBackendType_Vulkan;
  options.compatibleSurface = surface;
  callback.mode = WGPUCallbackMode_AllowProcessEvents;
  callback.callback = kiwi_adapter_callback;
  callback.userdata1 = &result;
  (void)wgpuInstanceRequestAdapter(instance, &options, callback);
  if (!kiwi_wait_for_request(instance, &result)) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timed out waiting for wgpu adapter request");
    return NULL;
  }
  if (result.status != WGPURequestAdapterStatus_Success || result.adapter == NULL) {
    if (kiwi_surface_error[0] == '\0') {
      snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "wgpu adapter request failed with status %d", result.status);
    }
    return NULL;
  }
  return result.adapter;
}

static WGPUDevice kiwi_request_device_sync_with_features(WGPUInstance instance, WGPUAdapter adapter,
                                                         const WGPUFeatureName *features, size_t feature_count) {
  KiwiRequestResult result = {0};
  WGPUDeviceDescriptor descriptor = WGPU_DEVICE_DESCRIPTOR_INIT;
  WGPURequestDeviceCallbackInfo callback = WGPU_REQUEST_DEVICE_CALLBACK_INFO_INIT;

  kiwi_surface_error[0] = '\0';
  descriptor.label = (WGPUStringView){.data = "kiwi-m0-device", .length = WGPU_STRLEN};
  descriptor.requiredFeatures = features;
  descriptor.requiredFeatureCount = feature_count;
  descriptor.deviceLostCallbackInfo.callback = kiwi_device_lost;
  descriptor.uncapturedErrorCallbackInfo.callback = kiwi_uncaptured_error;
  callback.mode = WGPUCallbackMode_AllowProcessEvents;
  callback.callback = kiwi_device_callback;
  callback.userdata1 = &result;
  (void)wgpuAdapterRequestDevice(adapter, &descriptor, callback);
  if (!kiwi_wait_for_request(instance, &result)) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timed out waiting for wgpu device request");
    return NULL;
  }
  if (result.status != WGPURequestDeviceStatus_Success || result.device == NULL) {
    if (kiwi_surface_error[0] == '\0') {
      snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "wgpu device request failed with status %d", result.status);
    }
    return NULL;
  }
  return result.device;
}

WGPUDevice kiwi_request_device_sync(WGPUInstance instance, WGPUAdapter adapter) {
  return kiwi_request_device_sync_with_features(instance, adapter, NULL, 0);
}

int kiwi_timestamp_query_probe(WGPUInstance instance, WGPUAdapter adapter) {
  if (!wgpuAdapterHasFeature(adapter, WGPUFeatureName_TimestampQuery)) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "adapter does not expose timestamp-query");
    return 0;
  }

  const WGPUFeatureName features[] = {WGPUFeatureName_TimestampQuery};
  WGPUDevice device = kiwi_request_device_sync_with_features(instance, adapter, features, 1);
  if (device == NULL) {
    return 0;
  }

  WGPUQuerySetDescriptor query_descriptor = WGPU_QUERY_SET_DESCRIPTOR_INIT;
  query_descriptor.label = (WGPUStringView){.data = "kiwi-timestamp-probe", .length = WGPU_STRLEN};
  query_descriptor.type = WGPUQueryType_Timestamp;
  query_descriptor.count = 2;
  WGPUQuerySet queries = wgpuDeviceCreateQuerySet(device, &query_descriptor);
  if (queries == NULL) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp query set creation returned null");
    wgpuDeviceDestroy(device);
    wgpuDeviceRelease(device);
    return 0;
  }

  WGPUBufferDescriptor resolve_descriptor = WGPU_BUFFER_DESCRIPTOR_INIT;
  resolve_descriptor.label = (WGPUStringView){.data = "kiwi-timestamp-probe-resolve", .length = WGPU_STRLEN};
  resolve_descriptor.size = 2 * sizeof(uint64_t);
  resolve_descriptor.usage = WGPUBufferUsage_QueryResolve | WGPUBufferUsage_CopySrc;
  WGPUBuffer resolve_buffer = wgpuDeviceCreateBuffer(device, &resolve_descriptor);
  WGPUBufferDescriptor read_descriptor = WGPU_BUFFER_DESCRIPTOR_INIT;
  read_descriptor.label = (WGPUStringView){.data = "kiwi-timestamp-probe-read", .length = WGPU_STRLEN};
  read_descriptor.size = resolve_descriptor.size;
  read_descriptor.usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst;
  WGPUBuffer read_buffer = wgpuDeviceCreateBuffer(device, &read_descriptor);
  WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(device, NULL);
  WGPUTextureDescriptor texture_descriptor = WGPU_TEXTURE_DESCRIPTOR_INIT;
  texture_descriptor.label = (WGPUStringView){.data = "kiwi-timestamp-probe-target", .length = WGPU_STRLEN};
  texture_descriptor.usage = WGPUTextureUsage_RenderAttachment;
  texture_descriptor.dimension = WGPUTextureDimension_2D;
  texture_descriptor.size = (WGPUExtent3D){.width = 1, .height = 1, .depthOrArrayLayers = 1};
  texture_descriptor.format = WGPUTextureFormat_R8Unorm;
  texture_descriptor.mipLevelCount = 1;
  texture_descriptor.sampleCount = 1;
  WGPUTexture target_texture = wgpuDeviceCreateTexture(device, &texture_descriptor);
  WGPUTextureView target_view = target_texture == NULL ? NULL : wgpuTextureCreateView(target_texture, NULL);
  if (resolve_buffer == NULL || read_buffer == NULL || encoder == NULL || target_texture == NULL || target_view == NULL) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp probe resource creation returned null");
    if (target_view != NULL) wgpuTextureViewRelease(target_view);
    if (target_texture != NULL) wgpuTextureRelease(target_texture);
    if (encoder != NULL) wgpuCommandEncoderRelease(encoder);
    if (read_buffer != NULL) wgpuBufferRelease(read_buffer);
    if (resolve_buffer != NULL) wgpuBufferRelease(resolve_buffer);
    wgpuQuerySetRelease(queries);
    wgpuDeviceDestroy(device);
    wgpuDeviceRelease(device);
    return 0;
  }

  WGPUPassTimestampWrites timestamp_writes = WGPU_PASS_TIMESTAMP_WRITES_INIT;
  timestamp_writes.querySet = queries;
  timestamp_writes.beginningOfPassWriteIndex = 0;
  timestamp_writes.endOfPassWriteIndex = 1;
  WGPURenderPassColorAttachment attachment = WGPU_RENDER_PASS_COLOR_ATTACHMENT_INIT;
  attachment.view = target_view;
  attachment.loadOp = WGPULoadOp_Clear;
  attachment.storeOp = WGPUStoreOp_Store;
  WGPURenderPassDescriptor pass_descriptor = WGPU_RENDER_PASS_DESCRIPTOR_INIT;
  pass_descriptor.colorAttachmentCount = 1;
  pass_descriptor.colorAttachments = &attachment;
  pass_descriptor.timestampWrites = &timestamp_writes;
  WGPURenderPassEncoder pass = wgpuCommandEncoderBeginRenderPass(encoder, &pass_descriptor);
  if (pass == NULL) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp probe render pass creation returned null");
    wgpuTextureViewRelease(target_view);
    wgpuTextureRelease(target_texture);
    wgpuCommandEncoderRelease(encoder);
    wgpuBufferRelease(read_buffer);
    wgpuBufferRelease(resolve_buffer);
    wgpuQuerySetRelease(queries);
    wgpuDeviceDestroy(device);
    wgpuDeviceRelease(device);
    return 0;
  }
  wgpuRenderPassEncoderEnd(pass);
  wgpuRenderPassEncoderRelease(pass);
  wgpuCommandEncoderResolveQuerySet(encoder, queries, 0, 2, resolve_buffer, 0);
  wgpuCommandEncoderCopyBufferToBuffer(encoder, resolve_buffer, 0, read_buffer, 0, resolve_descriptor.size);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  if (commands == NULL) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp probe command encoding returned null");
    wgpuTextureViewRelease(target_view);
    wgpuTextureRelease(target_texture);
    wgpuCommandEncoderRelease(encoder);
    wgpuBufferRelease(read_buffer);
    wgpuBufferRelease(resolve_buffer);
    wgpuQuerySetRelease(queries);
    wgpuDeviceDestroy(device);
    wgpuDeviceRelease(device);
    return 0;
  }
  WGPUQueue queue = wgpuDeviceGetQueue(device);
  wgpuQueueSubmit(queue, 1, &commands);

  KiwiMapResult map = {0};
  WGPUBufferMapCallbackInfo callback = WGPU_BUFFER_MAP_CALLBACK_INFO_INIT;
  callback.mode = WGPUCallbackMode_AllowProcessEvents;
  callback.callback = kiwi_buffer_map_callback;
  callback.userdata1 = &map;
  struct timespec map_start;
  clock_gettime(CLOCK_MONOTONIC, &map_start);
  (void)wgpuBufferMapAsync(read_buffer, WGPUMapMode_Read, 0, resolve_descriptor.size, callback);
  const struct timespec delay = {.tv_sec = 0, .tv_nsec = 1000000};
  for (int attempt = 0; attempt < 10000 && map.status == 0; ++attempt) {
    wgpuInstanceProcessEvents(instance);
    nanosleep(&delay, NULL);
  }

  int result = 0;
  if (map.status == WGPUMapAsyncStatus_Success) {
    const uint64_t *timestamps = wgpuBufferGetConstMappedRange(read_buffer, 0, resolve_descriptor.size);
    if (timestamps != NULL) {
      struct timespec map_end;
      clock_gettime(CLOCK_MONOTONIC, &map_end);
      const double map_latency_ms = (map_end.tv_sec - map_start.tv_sec) * 1000.0 + (map_end.tv_nsec - map_start.tv_nsec) / 1000000.0;
      snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp query probe succeeded: delta=%llu ticks map-latency=%.3fms", (unsigned long long)(timestamps[1] - timestamps[0]), map_latency_ms);
      result = 1;
    } else {
      snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp query probe mapped range was null");
    }
    wgpuBufferUnmap(read_buffer);
  } else if (map.status == 0) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp query probe timed out waiting for asynchronous map callback");
  }

  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
  wgpuTextureViewRelease(target_view);
  wgpuTextureRelease(target_texture);
  wgpuBufferRelease(read_buffer);
  wgpuBufferRelease(resolve_buffer);
  wgpuQuerySetRelease(queries);
  wgpuQueueRelease(queue);
  wgpuDeviceDestroy(device);
  wgpuDeviceRelease(device);
  return result;
}

WGPUShaderModule kiwi_shader_from_wgsl(WGPUDevice device, const char *source_code) {
  WGPUShaderSourceWGSL source = WGPU_SHADER_SOURCE_WGSL_INIT;
  WGPUShaderModuleDescriptor descriptor = WGPU_SHADER_MODULE_DESCRIPTOR_INIT;
  kiwi_surface_error[0] = '\0';
  source.code = (WGPUStringView){.data = source_code, .length = WGPU_STRLEN};
  descriptor.nextInChain = (WGPUChainedStruct *)&source;
  return wgpuDeviceCreateShaderModule(device, &descriptor);
}

int kiwi_pty_resize(int fd, unsigned short columns, unsigned short rows) {
  const struct winsize size = {
      .ws_row = rows,
      .ws_col = columns,
      .ws_xpixel = 0,
      .ws_ypixel = 0,
  };
  return ioctl(fd, TIOCSWINSZ, &size);
}

int kiwi_pty_set_nonblocking(int fd) {
  const int flags = fcntl(fd, F_GETFL);
  if (flags < 0) {
    return -1;
  }
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}
