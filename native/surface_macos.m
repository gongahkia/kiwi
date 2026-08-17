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

int kiwi_surface_set_drawable_size(GLFWwindow *window, uint32_t width, uint32_t height) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_surface_set_error("Cocoa drawable-size updates must run on the main thread");
      return 0;
    }
    NSView *view = glfwGetCocoaView(window);
    CAMetalLayer *layer = [view.layer isKindOfClass:[CAMetalLayer class]] ? (CAMetalLayer *)view.layer : nil;
    if (view == nil || layer == nil || width == 0 || height == 0) {
      kiwi_surface_set_error("GLFW did not expose a configured Cocoa Metal layer");
      return 0;
    }
    layer.contentsScale = view.window.backingScaleFactor > 0.0 ? view.window.backingScaleFactor : 1.0;
    layer.drawableSize = CGSizeMake(width, height);
    return 1;
  }
}

int kiwi_cocoa_private_pasteboard_round_trip(const char *text, size_t text_bytes) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_surface_set_error("Cocoa pasteboard checks must run on the main thread");
      return 0;
    }
    if (text == NULL || text_bytes == 0 || text_bytes > 4096 || memchr(text, '\0', text_bytes) != NULL) {
      kiwi_surface_set_error("invalid bounded Cocoa pasteboard text");
      return 0;
    }
    NSString *expected = [[[NSString alloc] initWithBytes:text length:text_bytes encoding:NSUTF8StringEncoding] autorelease];
    if (expected == nil) {
      kiwi_surface_set_error("Cocoa pasteboard text is not valid UTF-8");
      return 0;
    }
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    if (pasteboard == nil || ![pasteboard clearContents] || ![pasteboard setString:expected forType:NSPasteboardTypeString]) {
      kiwi_surface_set_error("could not write the private Cocoa pasteboard");
      return 0;
    }
    NSString *actual = [pasteboard stringForType:NSPasteboardTypeString];
    if (actual == nil || ![actual isEqualToString:expected]) {
      kiwi_surface_set_error("private Cocoa pasteboard round trip did not preserve text");
      return 0;
    }
    return 1;
  }
}
