#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#if !defined(__APPLE__)
#define GLFW_EXPOSE_NATIVE_WAYLAND
#define GLFW_EXPOSE_NATIVE_X11
#endif
#include <GLFW/glfw3.h>
#if !defined(__APPLE__)
#include <GLFW/glfw3native.h>
#endif
#include <webgpu/webgpu.h>

#include <stdbool.h>
#include <stdint.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static char kiwi_surface_error[2048];

void kiwi_surface_set_error(const char *message) {
  if (message == NULL) {
    kiwi_surface_error[0] = '\0';
    return;
  }
  snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "%s", message);
}

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

enum { KIWI_TIMESTAMP_SLOT_COUNT = 3, KIWI_TIMESTAMP_MAX_PASSES = 64 };

typedef struct KiwiTimestampMapState {
  WGPUMapAsyncStatus status;
  int detached;
} KiwiTimestampMapState;

typedef struct KiwiTimestampSlot {
  WGPUBuffer resolve_buffer;
  WGPUBuffer read_buffer;
  KiwiTimestampMapState *map;
  uint64_t frame;
  struct timespec submitted_at;
  int occupied;
  int map_requested;
} KiwiTimestampSlot;

typedef struct KiwiTimestampTracker {
  WGPUInstance instance;
  WGPUQuerySet queries;
  WGPUPassTimestampWrites *writes;
  uint32_t pass_count;
  uint64_t byte_size;
  int active_slot;
  uint32_t dropped_frames;
  KiwiTimestampSlot slots[KIWI_TIMESTAMP_SLOT_COUNT];
} KiwiTimestampTracker;

typedef struct KiwiTimestampSample {
  uint64_t frame;
  uint32_t pass_index;
  uint64_t begin_ticks;
  uint64_t end_ticks;
  uint64_t map_latency_ns;
} KiwiTimestampSample;

void kiwi_timestamp_tracker_destroy(KiwiTimestampTracker *tracker);

static void kiwi_buffer_map_callback(WGPUMapAsyncStatus status, WGPUStringView message,
                                     void *userdata1, void *userdata2) {
  (void)userdata2;
  KiwiMapResult *result = userdata1;
  result->status = status;
  if (status != WGPUMapAsyncStatus_Success) {
    kiwi_copy_message(message);
  }
}

static void kiwi_timestamp_map_callback(WGPUMapAsyncStatus status, WGPUStringView message,
                                        void *userdata1, void *userdata2) {
  (void)userdata2;
  KiwiTimestampMapState *map = userdata1;
  map->status = status;
  if (status != WGPUMapAsyncStatus_Success) {
    kiwi_copy_message(message);
  }
  if (map->detached) free(map);
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

#if !defined(__APPLE__)
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
#endif

#if !defined(__APPLE__)
int kiwi_surface_set_drawable_size(GLFWwindow *window, uint32_t width, uint32_t height) {
  (void)window;
  (void)width;
  (void)height;
  return 1;
}

int kiwi_cocoa_private_pasteboard_round_trip(const char *text, size_t text_bytes) {
  (void)text;
  (void)text_bytes;
  errno = ENOTSUP;
  return 0;
}
#endif

uint32_t kiwi_native_backend_type(void) {
#if defined(__APPLE__)
  return WGPUBackendType_Metal;
#else
  return WGPUBackendType_Vulkan;
#endif
}

const char *kiwi_native_backend_name(void) {
#if defined(__APPLE__)
  return "Metal";
#else
  return "Vulkan";
#endif
}

WGPUAdapter kiwi_request_adapter_sync(WGPUInstance instance, WGPUSurface surface) {
  KiwiRequestResult result = {0};
  WGPURequestAdapterOptions options = WGPU_REQUEST_ADAPTER_OPTIONS_INIT;
  WGPURequestAdapterCallbackInfo callback = WGPU_REQUEST_ADAPTER_CALLBACK_INFO_INIT;

  kiwi_surface_error[0] = '\0';
  options.featureLevel = WGPUFeatureLevel_Core;
  options.backendType = kiwi_native_backend_type();
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

WGPUDevice kiwi_request_timestamp_device_sync(WGPUInstance instance, WGPUAdapter adapter) {
  const WGPUFeatureName features[] = {WGPUFeatureName_TimestampQuery};
  return kiwi_request_device_sync_with_features(instance, adapter, features, 1);
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

KiwiTimestampTracker *kiwi_timestamp_tracker_new(WGPUInstance instance, WGPUDevice device, uint32_t pass_count) {
  if (pass_count == 0 || pass_count > KIWI_TIMESTAMP_MAX_PASSES) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp tracker pass count %u is outside 1..%u", pass_count, KIWI_TIMESTAMP_MAX_PASSES);
    return NULL;
  }
  KiwiTimestampTracker *tracker = calloc(1, sizeof(*tracker));
  if (tracker == NULL) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp tracker allocation failed");
    return NULL;
  }
  tracker->instance = instance;
  tracker->pass_count = pass_count;
  tracker->byte_size = 2 * pass_count * sizeof(uint64_t);
  tracker->active_slot = -1;

  WGPUQuerySetDescriptor query_descriptor = WGPU_QUERY_SET_DESCRIPTOR_INIT;
  query_descriptor.label = (WGPUStringView){.data = "kiwi-render-timestamp-queries", .length = WGPU_STRLEN};
  query_descriptor.type = WGPUQueryType_Timestamp;
  query_descriptor.count = 2 * pass_count;
  tracker->queries = wgpuDeviceCreateQuerySet(device, &query_descriptor);
  tracker->writes = calloc(pass_count, sizeof(*tracker->writes));
  if (tracker->queries == NULL || tracker->writes == NULL) {
    snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp tracker query allocation failed");
    if (tracker->queries != NULL) wgpuQuerySetRelease(tracker->queries);
    free(tracker->writes);
    free(tracker);
    return NULL;
  }
  for (uint32_t index = 0; index < pass_count; ++index) {
    tracker->writes[index] = (WGPUPassTimestampWrites)WGPU_PASS_TIMESTAMP_WRITES_INIT;
    tracker->writes[index].querySet = tracker->queries;
    tracker->writes[index].beginningOfPassWriteIndex = 2 * index;
    tracker->writes[index].endOfPassWriteIndex = 2 * index + 1;
  }

  for (uint32_t index = 0; index < KIWI_TIMESTAMP_SLOT_COUNT; ++index) {
    tracker->slots[index].map = calloc(1, sizeof(*tracker->slots[index].map));
    if (tracker->slots[index].map == NULL) {
      snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp tracker map state allocation failed");
      kiwi_timestamp_tracker_destroy(tracker);
      return NULL;
    }
    WGPUBufferDescriptor resolve_descriptor = WGPU_BUFFER_DESCRIPTOR_INIT;
    resolve_descriptor.label = (WGPUStringView){.data = "kiwi-render-timestamp-resolve", .length = WGPU_STRLEN};
    resolve_descriptor.size = tracker->byte_size;
    resolve_descriptor.usage = WGPUBufferUsage_QueryResolve | WGPUBufferUsage_CopySrc;
    tracker->slots[index].resolve_buffer = wgpuDeviceCreateBuffer(device, &resolve_descriptor);
    WGPUBufferDescriptor read_descriptor = WGPU_BUFFER_DESCRIPTOR_INIT;
    read_descriptor.label = (WGPUStringView){.data = "kiwi-render-timestamp-read", .length = WGPU_STRLEN};
    read_descriptor.size = tracker->byte_size;
    read_descriptor.usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst;
    tracker->slots[index].read_buffer = wgpuDeviceCreateBuffer(device, &read_descriptor);
    if (tracker->slots[index].resolve_buffer == NULL || tracker->slots[index].read_buffer == NULL) {
      snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp tracker readback buffer allocation failed");
      kiwi_timestamp_tracker_destroy(tracker);
      return NULL;
    }
  }
  return tracker;
}

void kiwi_timestamp_tracker_destroy(KiwiTimestampTracker *tracker) {
  if (tracker == NULL) return;
  for (uint32_t index = 0; index < KIWI_TIMESTAMP_SLOT_COUNT; ++index) {
    KiwiTimestampSlot *slot = &tracker->slots[index];
    if (slot->map != NULL && slot->map_requested && slot->map->status == 0 && slot->read_buffer != NULL) {
      wgpuBufferUnmap(slot->read_buffer);
    }
  }
  for (int attempt = 0; attempt < 100 && tracker->instance != NULL; ++attempt) {
    int pending = 0;
    for (uint32_t index = 0; index < KIWI_TIMESTAMP_SLOT_COUNT; ++index) {
      KiwiTimestampSlot *slot = &tracker->slots[index];
      if (slot->map != NULL && slot->map_requested && slot->map->status == 0) pending = 1;
    }
    if (!pending) break;
    wgpuInstanceProcessEvents(tracker->instance);
    const struct timespec delay = {.tv_sec = 0, .tv_nsec = 1000000};
    nanosleep(&delay, NULL);
  }
  for (uint32_t index = 0; index < KIWI_TIMESTAMP_SLOT_COUNT; ++index) {
    KiwiTimestampSlot *slot = &tracker->slots[index];
    if (slot->map != NULL && slot->map_requested && slot->map->status == WGPUMapAsyncStatus_Success && slot->read_buffer != NULL) {
      wgpuBufferUnmap(slot->read_buffer);
    }
    if (slot->map != NULL) {
      if (slot->map_requested && slot->map->status == 0) {
        slot->map->detached = 1;
      } else {
        free(slot->map);
      }
    }
    if (slot->read_buffer != NULL) wgpuBufferRelease(slot->read_buffer);
    if (slot->resolve_buffer != NULL) wgpuBufferRelease(slot->resolve_buffer);
  }
  if (tracker->queries != NULL) wgpuQuerySetRelease(tracker->queries);
  free(tracker->writes);
  free(tracker);
}

int kiwi_timestamp_tracker_begin(KiwiTimestampTracker *tracker, uint64_t frame) {
  if (tracker == NULL || tracker->active_slot >= 0) return 0;
  for (uint32_t index = 0; index < KIWI_TIMESTAMP_SLOT_COUNT; ++index) {
    KiwiTimestampSlot *slot = &tracker->slots[index];
    if (!slot->occupied) {
      slot->occupied = 1;
      slot->map->status = 0;
      slot->frame = frame;
      slot->map_requested = 0;
      tracker->active_slot = (int)index;
      return 1;
    }
  }
  tracker->dropped_frames += 1;
  return 0;
}

const WGPUPassTimestampWrites *kiwi_timestamp_tracker_writes(KiwiTimestampTracker *tracker, uint32_t pass_index) {
  if (tracker == NULL || tracker->active_slot < 0 || pass_index >= tracker->pass_count) return NULL;
  return &tracker->writes[pass_index];
}

void kiwi_timestamp_tracker_resolve(KiwiTimestampTracker *tracker, WGPUCommandEncoder encoder) {
  if (tracker == NULL || tracker->active_slot < 0) return;
  KiwiTimestampSlot *slot = &tracker->slots[tracker->active_slot];
  wgpuCommandEncoderResolveQuerySet(encoder, tracker->queries, 0, 2 * tracker->pass_count, slot->resolve_buffer, 0);
  wgpuCommandEncoderCopyBufferToBuffer(encoder, slot->resolve_buffer, 0, slot->read_buffer, 0, tracker->byte_size);
}

void kiwi_timestamp_tracker_submit(KiwiTimestampTracker *tracker) {
  if (tracker == NULL || tracker->active_slot < 0) return;
  KiwiTimestampSlot *slot = &tracker->slots[tracker->active_slot];
  clock_gettime(CLOCK_MONOTONIC, &slot->submitted_at);
  WGPUBufferMapCallbackInfo callback = WGPU_BUFFER_MAP_CALLBACK_INFO_INIT;
  callback.mode = WGPUCallbackMode_AllowProcessEvents;
  callback.callback = kiwi_timestamp_map_callback;
  callback.userdata1 = slot->map;
  (void)wgpuBufferMapAsync(slot->read_buffer, WGPUMapMode_Read, 0, tracker->byte_size, callback);
  slot->map_requested = 1;
  tracker->active_slot = -1;
}

int kiwi_timestamp_tracker_poll(KiwiTimestampTracker *tracker, KiwiTimestampSample *samples, uint32_t capacity) {
  if (tracker == NULL || samples == NULL || capacity < tracker->pass_count) return -1;
  for (uint32_t slot_index = 0; slot_index < KIWI_TIMESTAMP_SLOT_COUNT; ++slot_index) {
    KiwiTimestampSlot *slot = &tracker->slots[slot_index];
    if (!slot->occupied || !slot->map_requested || slot->map->status == 0) continue;
    if (slot->map->status != WGPUMapAsyncStatus_Success) {
      slot->occupied = 0;
      slot->map_requested = 0;
      slot->map->status = 0;
      return -1;
    }
    const uint64_t *timestamps = wgpuBufferGetConstMappedRange(slot->read_buffer, 0, tracker->byte_size);
    if (timestamps == NULL) {
      snprintf(kiwi_surface_error, sizeof(kiwi_surface_error), "timestamp tracker mapped range was null");
      wgpuBufferUnmap(slot->read_buffer);
      slot->occupied = 0;
      slot->map_requested = 0;
      slot->map->status = 0;
      return -1;
    }
    struct timespec completed_at;
    clock_gettime(CLOCK_MONOTONIC, &completed_at);
    const uint64_t latency_ns = (completed_at.tv_sec - slot->submitted_at.tv_sec) * 1000000000ULL + (completed_at.tv_nsec - slot->submitted_at.tv_nsec);
    for (uint32_t pass_index = 0; pass_index < tracker->pass_count; ++pass_index) {
      samples[pass_index] = (KiwiTimestampSample){
        .frame = slot->frame,
        .pass_index = pass_index,
        .begin_ticks = timestamps[2 * pass_index],
        .end_ticks = timestamps[2 * pass_index + 1],
        .map_latency_ns = latency_ns,
      };
    }
    wgpuBufferUnmap(slot->read_buffer);
    slot->occupied = 0;
    slot->map_requested = 0;
    slot->map->status = 0;
    return (int)tracker->pass_count;
  }
  return 0;
}

uint32_t kiwi_timestamp_tracker_pending(const KiwiTimestampTracker *tracker) {
  if (tracker == NULL) return 0;
  uint32_t pending = 0;
  for (uint32_t index = 0; index < KIWI_TIMESTAMP_SLOT_COUNT; ++index) {
    if (tracker->slots[index].occupied) pending += 1;
  }
  return pending;
}

uint32_t kiwi_timestamp_tracker_dropped(const KiwiTimestampTracker *tracker) {
  return tracker == NULL ? 0 : tracker->dropped_frames;
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

static const char *kiwi_environment_value(char *const envp[], const char *name) {
  const size_t name_length = strlen(name);
  for (size_t index = 0; envp != NULL && envp[index] != NULL; ++index) {
    if (strncmp(envp[index], name, name_length) == 0 && envp[index][name_length] == '=') {
      return envp[index] + name_length + 1;
    }
  }
  return NULL;
}

int kiwi_execvpe(const char *file, char *const argv[], char *const envp[]) {
#if !defined(__APPLE__)
  return execvpe(file, argv, envp);
#else
  if (file == NULL || file[0] == '\0') {
    errno = ENOENT;
    return -1;
  }
  if (strchr(file, '/') != NULL) return execve(file, argv, envp);

  const char *path = kiwi_environment_value(envp, "PATH");
  if (path == NULL || path[0] == '\0') path = "/usr/bin:/bin";
  int saved_error = ENOENT;
  const char *segment = path;
  while (true) {
    const char *separator = strchr(segment, ':');
    const size_t directory_length = separator == NULL ? strlen(segment) : (size_t)(separator - segment);
    const size_t file_length = strlen(file);
    if (directory_length <= SIZE_MAX - file_length - 2) {
      char *candidate = malloc(directory_length + file_length + 2);
      if (candidate == NULL) {
        errno = ENOMEM;
        return -1;
      }
      if (directory_length == 0) {
        memcpy(candidate, file, file_length + 1);
      } else {
        memcpy(candidate, segment, directory_length);
        candidate[directory_length] = '/';
        memcpy(candidate + directory_length + 1, file, file_length + 1);
      }
      (void)execve(candidate, argv, envp);
      if (errno != ENOENT && errno != ENOTDIR) saved_error = errno;
      free(candidate);
    }
    if (separator == NULL) break;
    segment = separator + 1;
  }
  errno = saved_error;
  return -1;
#endif
}

int kiwi_open_uri(const char *uri) {
  if (uri == NULL || uri[0] == '\0') {
    errno = EINVAL;
    return -1;
  }
  pid_t child = fork();
  if (child < 0) return -1;
  if (child == 0) {
    pid_t detached = fork();
    if (detached < 0) _exit(127);
    if (detached > 0) _exit(0);
    int null_fd = open("/dev/null", O_RDWR);
    if (null_fd >= 0) {
      (void)dup2(null_fd, STDIN_FILENO);
      (void)dup2(null_fd, STDOUT_FILENO);
      (void)dup2(null_fd, STDERR_FILENO);
      if (null_fd > STDERR_FILENO) (void)close(null_fd);
    }
#if defined(__APPLE__)
    execlp("open", "open", uri, (char *)NULL);
#else
    execlp("xdg-open", "xdg-open", uri, (char *)NULL);
#endif
    _exit(127);
  }
  int status;
  do {
    if (waitpid(child, &status, 0) == child) {
      if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return 0;
      errno = EIO;
      return -1;
    }
  } while (errno == EINTR);
  return -1;
}
