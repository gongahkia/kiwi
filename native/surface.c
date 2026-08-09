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

WGPUDevice kiwi_request_device_sync(WGPUInstance instance, WGPUAdapter adapter) {
  KiwiRequestResult result = {0};
  WGPUDeviceDescriptor descriptor = WGPU_DEVICE_DESCRIPTOR_INIT;
  WGPURequestDeviceCallbackInfo callback = WGPU_REQUEST_DEVICE_CALLBACK_INFO_INIT;

  kiwi_surface_error[0] = '\0';
  descriptor.label = (WGPUStringView){.data = "kiwi-m0-device", .length = WGPU_STRLEN};
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
