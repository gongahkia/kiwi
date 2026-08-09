#define GLFW_EXPOSE_NATIVE_WAYLAND
#define GLFW_EXPOSE_NATIVE_X11
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <webgpu/webgpu.h>

#include <stdio.h>

static char kiwi_surface_error[160];

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
