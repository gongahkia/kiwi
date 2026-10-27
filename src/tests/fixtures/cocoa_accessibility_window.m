#define GLFW_EXPOSE_NATIVE_COCOA
#import <AppKit/AppKit.h>
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

// Test-only visibility setup for one owned window. Do not change the user's
// Space preferences or activate any other application.
void kiwi_accessibility_fixture_show(GLFWwindow *handle) {
  NSWindow *window = glfwGetCocoaWindow(handle);
  NSWindowCollectionBehavior behavior = window.collectionBehavior;
  behavior &= ~(NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorFullScreenNone);
  behavior |= NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
  if (@available(macOS 13.0, *)) {
    behavior &= ~(NSWindowCollectionBehaviorPrimary | NSWindowCollectionBehaviorAuxiliary);
    behavior |= NSWindowCollectionBehaviorCanJoinAllApplications;
  }
  window.collectionBehavior = behavior;
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:nil];
}
