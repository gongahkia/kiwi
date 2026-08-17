#define GLFW_EXPOSE_NATIVE_COCOA
#import <AppKit/AppKit.h>

#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { KIWI_A11Y_MAX_TEXT_BYTES = 1024 * 1024, KIWI_A11Y_MAX_TITLE_BYTES = 4096 };

typedef struct KiwiAccessibility {
  NSView *view;
  NSArray *previous_children;
  NSAccessibilityElement *terminal;
  int active;
} KiwiAccessibility;

static char kiwi_accessibility_error[512];

static void kiwi_a11y_set_error(const char *message) {
  snprintf(kiwi_accessibility_error, sizeof(kiwi_accessibility_error), "%s", message);
}

KiwiAccessibility *kiwi_accessibility_new(void *opaque_window) {
  kiwi_accessibility_error[0] = '\0';
  if (![NSThread isMainThread]) {
    kiwi_a11y_set_error("Cocoa accessibility must be initialized on the main thread");
    return NULL;
  }
  GLFWwindow *window = opaque_window;
  NSView *view = window == NULL ? nil : glfwGetCocoaView(window);
  if (view == nil) {
    kiwi_a11y_set_error("GLFW did not expose a Cocoa accessibility view");
    return NULL;
  }

  KiwiAccessibility *adapter = calloc(1, sizeof(*adapter));
  if (adapter == NULL) {
    kiwi_a11y_set_error("could not allocate Cocoa accessibility adapter");
    return NULL;
  }
  adapter->view = [view retain];
  adapter->previous_children = [[view accessibilityChildren] copy];
  adapter->terminal = [[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole
                                                                        frame:view.bounds
                                                                        label:@"Kiwi terminal"
                                                                       parent:view] retain];
  adapter->terminal.accessibilityIdentifier = @"kiwi.terminal";
  adapter->terminal.accessibilityValue = @"";
  adapter->terminal.accessibilityEnabled = YES;
  NSMutableArray *children = [NSMutableArray arrayWithArray:adapter->previous_children ?: @[]];
  [children addObject:adapter->terminal];
  view.accessibilityChildren = children;
  adapter->active = 1;
  return adapter;
}

void kiwi_accessibility_destroy(KiwiAccessibility *adapter) {
  if (adapter == NULL) return;
  if (adapter->active && adapter->view != nil) adapter->view.accessibilityChildren = adapter->previous_children;
  [adapter->terminal release];
  [adapter->previous_children release];
  [adapter->view release];
  free(adapter);
}

int kiwi_accessibility_update(KiwiAccessibility *adapter, const char *text, size_t text_bytes, int32_t character_count,
                              int32_t caret_offset, int32_t selection_start, int32_t selection_end, int focused, const char *title) {
  (void)character_count;
  (void)caret_offset;
  (void)selection_start;
  (void)selection_end;
  kiwi_accessibility_error[0] = '\0';
  if (adapter == NULL || !adapter->active || text == NULL || title == NULL || text_bytes > KIWI_A11Y_MAX_TEXT_BYTES || strlen(title) > KIWI_A11Y_MAX_TITLE_BYTES || memchr(text, '\0', text_bytes) != NULL) {
    kiwi_a11y_set_error("invalid bounded Cocoa accessibility projection");
    return 0;
  }
  NSString *value = [[[NSString alloc] initWithBytes:text length:text_bytes encoding:NSUTF8StringEncoding] autorelease];
  NSString *label = [NSString stringWithUTF8String:title];
  if (value == nil || label == nil) {
    kiwi_a11y_set_error("Cocoa accessibility projection is not valid UTF-8");
    return 0;
  }
  adapter->terminal.accessibilityFrameInParentSpace = adapter->view.bounds;
  adapter->terminal.accessibilityLabel = label;
  adapter->terminal.accessibilityValue = value;
  adapter->terminal.accessibilityFocused = focused != 0;
  NSAccessibilityPostNotification(adapter->terminal, NSAccessibilityValueChangedNotification);
  if (focused != 0) NSAccessibilityPostNotification(adapter->terminal, NSAccessibilityFocusedUIElementChangedNotification);
  return 1;
}

int kiwi_cocoa_accessibility_round_trip(void *opaque_window) {
  GLFWwindow *window = opaque_window;
  NSView *view = window == NULL ? nil : glfwGetCocoaView(window);
  if (view == nil) {
    kiwi_a11y_set_error("GLFW did not expose a Cocoa accessibility view");
    return 0;
  }
  NSArray *const children_before = [[view accessibilityChildren] copy];
  KiwiAccessibility *const adapter = kiwi_accessibility_new(opaque_window);
  if (adapter == NULL) {
    [children_before release];
    return 0;
  }
  static const char text[] = "Kiwi accessibility smoke \xE2\x9C\x93";
  static const char title[] = "Kiwi accessibility smoke title";
  int valid = kiwi_accessibility_update(adapter, text, sizeof(text) - 1, 26, 26, -1, -1, 1, title);
  valid = valid && [adapter->terminal.accessibilityIdentifier isEqualToString:@"kiwi.terminal"];
  valid = valid && [adapter->terminal.accessibilityRole isEqualToString:NSAccessibilityStaticTextRole];
  valid = valid && [adapter->terminal.accessibilityLabel isEqualToString:[NSString stringWithUTF8String:title]];
  valid = valid && [adapter->terminal.accessibilityValue isEqualToString:[NSString stringWithUTF8String:text]];
  valid = valid && adapter->terminal.accessibilityFocused;
  kiwi_accessibility_destroy(adapter);
  valid = valid && [[view accessibilityChildren] isEqualToArray:children_before];
  [children_before release];
  if (!valid) kiwi_a11y_set_error("Cocoa accessibility projection round trip did not preserve its declared semantics");
  return valid;
}

void kiwi_accessibility_poll(KiwiAccessibility *adapter) {
  (void)adapter;
}

int kiwi_accessibility_active(const KiwiAccessibility *adapter) {
  return adapter != NULL && adapter->active;
}

const char *kiwi_accessibility_bus_name(const KiwiAccessibility *adapter) {
  (void)adapter;
  return "NSAccessibility";
}

const char *kiwi_accessibility_last_error(void) {
  return kiwi_accessibility_error;
}
