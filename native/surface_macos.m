#define GLFW_EXPOSE_NATIVE_COCOA
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>

#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <webgpu/webgpu.h>

extern void kiwi_surface_set_error(const char *message);

WGPUSurface kiwi_surface_from_glfw(WGPUInstance instance, GLFWwindow *window) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_surface_set_error("Cocoa surface creation must run on the main thread");
      return NULL;
    }

    NSView *view = glfwGetCocoaView(window);
    if (view == nil) {
      kiwi_surface_set_error("GLFW did not expose a Cocoa content view");
      return NULL;
    }

    CAMetalLayer *layer = nil;
    if ([view.layer isKindOfClass:[CAMetalLayer class]]) {
      layer = (CAMetalLayer *)view.layer;
    } else {
      view.wantsLayer = YES;
      layer = [CAMetalLayer layer];
      layer.opaque = YES;
      layer.contentsScale = view.window.backingScaleFactor > 0.0 ? view.window.backingScaleFactor : 1.0;
      layer.drawableSize = CGSizeMake(view.bounds.size.width * layer.contentsScale, view.bounds.size.height * layer.contentsScale);
      view.layer = layer;
    }

    WGPUSurfaceSourceMetalLayer source = WGPU_SURFACE_SOURCE_METAL_LAYER_INIT;
    WGPUSurfaceDescriptor descriptor = WGPU_SURFACE_DESCRIPTOR_INIT;
    source.layer = (__bridge void *)layer;
    descriptor.nextInChain = (WGPUChainedStruct *)&source;
    WGPUSurface surface = wgpuInstanceCreateSurface(instance, &descriptor);
    if (surface == NULL) kiwi_surface_set_error("wgpu failed to create a Metal-layer surface");
    return surface;
  }
}
