#define GLFW_EXPOSE_NATIVE_COCOA
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>

#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <webgpu/webgpu.h>
#include <errno.h>
#include <sys/wait.h>
#include <unistd.h>

extern void kiwi_surface_set_error(const char *message);

typedef void (*KiwiCocoaMenuCallback)(void *userdata, uint32_t action);

enum {
  KIWI_COCOA_MENU_NEW_TAB = 1,
  KIWI_COCOA_MENU_NEW_WINDOW = 2,
  KIWI_COCOA_MENU_NEXT_TAB = 3,
  KIWI_COCOA_MENU_CLOSE_PANE = 4,
  KIWI_COCOA_MENU_SPLIT_RIGHT = 5,
  KIWI_COCOA_MENU_SPLIT_DOWN = 6,
  KIWI_COCOA_MENU_RELOAD_CONFIGURATION = 7,
  KIWI_COCOA_MENU_MOVE_SESSION_NEW_WINDOW = 8,
  KIWI_COCOA_MENU_MOVE_SESSION_NEXT_WINDOW = 9,
  KIWI_COCOA_MENU_DUPLICATE_SESSION_NEW_WINDOW = 10,
  KIWI_COCOA_MENU_DUPLICATE_SESSION_NEXT_WINDOW = 11,
};

@interface KiwiCocoaMenuRegistration : NSObject {
 @public
  KiwiCocoaMenuCallback callback;
  void *userdata;
}
@end

@implementation KiwiCocoaMenuRegistration
@end

@interface KiwiCocoaMenuDispatcher : NSObject
- (void)invokeAction:(id)sender;
@end

static NSMutableDictionary *kiwi_cocoa_menu_registrations;
static KiwiCocoaMenuDispatcher *kiwi_cocoa_menu_dispatcher;
static KiwiCocoaMenuRegistration *kiwi_cocoa_active_menu_registration;

static BOOL kiwi_cocoa_menu_action_is_valid(uint32_t action) {
  return action >= KIWI_COCOA_MENU_NEW_TAB && action <= KIWI_COCOA_MENU_DUPLICATE_SESSION_NEXT_WINDOW;
}

static NSValue *kiwi_cocoa_menu_window_key(GLFWwindow *window) {
  NSWindow *native_window = window == NULL ? nil : glfwGetCocoaWindow(window);
  return native_window == nil ? nil : [NSValue valueWithPointer:native_window];
}

static KiwiCocoaMenuRegistration *kiwi_cocoa_menu_registration(GLFWwindow *window) {
  NSValue *key = kiwi_cocoa_menu_window_key(window);
  return key == nil ? nil : [kiwi_cocoa_menu_registrations objectForKey:key];
}

static KiwiCocoaMenuRegistration *kiwi_cocoa_menu_registration_for_window(NSWindow *window) {
  return window == nil ? nil : [kiwi_cocoa_menu_registrations objectForKey:[NSValue valueWithPointer:window]];
}

@implementation KiwiCocoaMenuDispatcher
- (void)windowDidBecomeKey:(NSNotification *)notification {
  KiwiCocoaMenuRegistration *registration = kiwi_cocoa_menu_registration_for_window(notification.object);
  if (registration != nil) kiwi_cocoa_active_menu_registration = registration;
}

- (void)invokeAction:(id)sender {
  if (![sender isKindOfClass:[NSMenuItem class]]) return;
  NSNumber *number = [(NSMenuItem *)sender representedObject];
  if (![number isKindOfClass:[NSNumber class]]) return;
  uint32_t action = number.unsignedIntValue;
  if (!kiwi_cocoa_menu_action_is_valid(action)) return;
  NSWindow *key_window = NSApp.keyWindow ?: NSApp.mainWindow;
  KiwiCocoaMenuRegistration *registration = kiwi_cocoa_menu_registration_for_window(key_window);
  if (registration == nil) registration = kiwi_cocoa_active_menu_registration;
  if (registration != nil && registration->callback != NULL) {
    registration->callback(registration->userdata, action);
  }
}
@end

static NSMenuItem *kiwi_cocoa_menu_item(NSString *title, uint32_t action) {
  NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title action:@selector(invokeAction:)
                                            keyEquivalent:@""] autorelease];
  item.target = kiwi_cocoa_menu_dispatcher;
  item.representedObject = [NSNumber numberWithUnsignedInt:action];
  return item;
}

static void kiwi_cocoa_install_main_menu(void) {
  if (kiwi_cocoa_menu_dispatcher != nil) return;
  kiwi_cocoa_menu_registrations = [[NSMutableDictionary alloc] init];
  kiwi_cocoa_menu_dispatcher = [[KiwiCocoaMenuDispatcher alloc] init];
  [[NSNotificationCenter defaultCenter] addObserver:kiwi_cocoa_menu_dispatcher
                                           selector:@selector(windowDidBecomeKey:)
                                               name:NSWindowDidBecomeKeyNotification object:nil];

  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Kiwi"];
  NSMenuItem *application_item = [[[NSMenuItem alloc] initWithTitle:@"Kiwi" action:nil keyEquivalent:@""] autorelease];
  NSMenu *application_menu = [[NSMenu alloc] initWithTitle:@"Kiwi"];
  [application_menu addItem:[[[NSMenuItem alloc] initWithTitle:@"Quit Kiwi" action:@selector(terminate:)
                                                   keyEquivalent:@"q"] autorelease]];
  application_item.submenu = application_menu;
  [application_menu release];
  [menu addItem:application_item];

  NSMenuItem *file_item = [[[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""] autorelease];
  NSMenu *file_menu = [[NSMenu alloc] initWithTitle:@"File"];
  [file_menu addItem:kiwi_cocoa_menu_item(@"New Tab", KIWI_COCOA_MENU_NEW_TAB)];
  [file_menu addItem:kiwi_cocoa_menu_item(@"New Window", KIWI_COCOA_MENU_NEW_WINDOW)];
  [file_menu addItem:[NSMenuItem separatorItem]];
  [file_menu addItem:kiwi_cocoa_menu_item(@"Reload Configuration", KIWI_COCOA_MENU_RELOAD_CONFIGURATION)];
  file_item.submenu = file_menu;
  [file_menu release];
  [menu addItem:file_item];

  NSMenuItem *window_item = [[[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""] autorelease];
  NSMenu *window_menu = [[NSMenu alloc] initWithTitle:@"Window"];
  [window_menu addItem:kiwi_cocoa_menu_item(@"Next Tab", KIWI_COCOA_MENU_NEXT_TAB)];
  [window_menu addItem:kiwi_cocoa_menu_item(@"Close Pane", KIWI_COCOA_MENU_CLOSE_PANE)];
  [window_menu addItem:[NSMenuItem separatorItem]];
  [window_menu addItem:kiwi_cocoa_menu_item(@"Split Right", KIWI_COCOA_MENU_SPLIT_RIGHT)];
  [window_menu addItem:kiwi_cocoa_menu_item(@"Split Down", KIWI_COCOA_MENU_SPLIT_DOWN)];
  [window_menu addItem:[NSMenuItem separatorItem]];
  [window_menu addItem:kiwi_cocoa_menu_item(@"Move Session to New Window", KIWI_COCOA_MENU_MOVE_SESSION_NEW_WINDOW)];
  [window_menu addItem:kiwi_cocoa_menu_item(@"Move Session to Next Window", KIWI_COCOA_MENU_MOVE_SESSION_NEXT_WINDOW)];
  [window_menu addItem:kiwi_cocoa_menu_item(@"Duplicate Session to New Window", KIWI_COCOA_MENU_DUPLICATE_SESSION_NEW_WINDOW)];
  [window_menu addItem:kiwi_cocoa_menu_item(@"Duplicate Session to Next Window", KIWI_COCOA_MENU_DUPLICATE_SESSION_NEXT_WINDOW)];
  window_item.submenu = window_menu;
  [window_menu release];
  [menu addItem:window_item];
  NSApp.mainMenu = menu;
  [menu release];
}

int kiwi_cocoa_menu_install(GLFWwindow *window, KiwiCocoaMenuCallback callback, void *userdata) {
  @autoreleasepool {
    if (![NSThread isMainThread] || window == NULL || callback == NULL) {
      kiwi_surface_set_error("Cocoa menu installation needs a main-thread window and callback");
      return 0;
    }
    NSValue *key = kiwi_cocoa_menu_window_key(window);
    if (key == nil) {
      kiwi_surface_set_error("GLFW did not expose a Cocoa window for the menu");
      return 0;
    }
    kiwi_cocoa_install_main_menu();
    KiwiCocoaMenuRegistration *registration = [[KiwiCocoaMenuRegistration alloc] init];
    registration->callback = callback;
    registration->userdata = userdata;
    [kiwi_cocoa_menu_registrations setObject:registration forKey:key];
    if (NSApp.keyWindow == glfwGetCocoaWindow(window) || kiwi_cocoa_active_menu_registration == nil) {
      kiwi_cocoa_active_menu_registration = registration;
    }
    [registration release];
    return 1;
  }
}

void kiwi_cocoa_menu_remove(GLFWwindow *window) {
  @autoreleasepool {
    NSValue *key = kiwi_cocoa_menu_window_key(window);
    KiwiCocoaMenuRegistration *registration = key == nil ? nil : [kiwi_cocoa_menu_registrations objectForKey:key];
    if (registration == kiwi_cocoa_active_menu_registration) kiwi_cocoa_active_menu_registration = nil;
    if (key != nil && kiwi_cocoa_menu_registrations != nil) [kiwi_cocoa_menu_registrations removeObjectForKey:key];
  }
}

int kiwi_cocoa_menu_invoke_smoke(GLFWwindow *window, uint32_t action) {
  @autoreleasepool {
    if (![NSThread isMainThread] || !kiwi_cocoa_menu_action_is_valid(action)) {
      kiwi_surface_set_error("Cocoa menu smoke received an invalid action");
      return 0;
    }
    KiwiCocoaMenuRegistration *registration = kiwi_cocoa_menu_registration(window);
    if (registration == nil || registration->callback == NULL ||
        kiwi_cocoa_menu_dispatcher == nil || NSApp.mainMenu.numberOfItems < 3) {
      kiwi_surface_set_error("Cocoa menu smoke needs an installed window callback");
      return 0;
    }
    kiwi_cocoa_active_menu_registration = registration;
    NSMenuItem *item = kiwi_cocoa_menu_item(@"Kiwi menu smoke", action);
    [kiwi_cocoa_menu_dispatcher invokeAction:item];
    return 1;
  }
}

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

int kiwi_cocoa_system_appearance(GLFWwindow *window) {
  @autoreleasepool {
    if (![NSThread isMainThread] || window == NULL) return -1;
    NSView *view = glfwGetCocoaView(window);
    if (view == nil) return -1;
    NSString *name = [view.effectiveAppearance bestMatchFromAppearancesWithNames:@[
      NSAppearanceNameAqua,
      NSAppearanceNameDarkAqua,
    ]];
    if (name == nil) return -1;
    return [name isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
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
