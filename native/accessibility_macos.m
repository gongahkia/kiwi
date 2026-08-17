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
  NSRange selected_range;
  int active;
} KiwiAccessibility;

static char kiwi_accessibility_error[512];

static void kiwi_a11y_set_error(const char *message) {
  snprintf(kiwi_accessibility_error, sizeof(kiwi_accessibility_error), "%s", message);
}

/* The Lua projection uses Unicode scalar offsets; NSAccessibility uses the
 * NSString UTF-16 index space.  Keep the conversion at this bridge boundary. */
static NSInteger kiwi_utf16_index_for_scalar_offset(NSString *value, int32_t offset) {
  if (offset < 0) return NSNotFound;
  NSInteger scalars = 0;
  NSUInteger index = 0;
  while (index < value.length && scalars < offset) {
    const unichar unit = [value characterAtIndex:index++];
    if (CFStringIsSurrogateHighCharacter(unit) && index < value.length
        && CFStringIsSurrogateLowCharacter([value characterAtIndex:index])) index += 1;
    scalars += 1;
  }
  return scalars == offset ? (NSInteger)index : NSNotFound;
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
  adapter->terminal = [[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityTextAreaRole
                                                                        frame:view.bounds
                                                                        label:@"Kiwi terminal"
                                                                       parent:view] retain];
  adapter->terminal.accessibilityIdentifier = @"kiwi.terminal";
  adapter->terminal.accessibilityValue = @"";
  adapter->terminal.accessibilityNumberOfCharacters = 0;
  adapter->terminal.accessibilitySelectedTextRange = NSMakeRange(NSNotFound, 0);
  adapter->terminal.accessibilityVisibleCharacterRange = NSMakeRange(0, 0);
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
  kiwi_accessibility_error[0] = '\0';
  if (adapter == NULL || !adapter->active || text == NULL || title == NULL || text_bytes > KIWI_A11Y_MAX_TEXT_BYTES || strlen(title) > KIWI_A11Y_MAX_TITLE_BYTES || memchr(text, '\0', text_bytes) != NULL
      || character_count < 0 || caret_offset < -1 || caret_offset > character_count || selection_start < -1 || selection_end < -1
      || (selection_start >= 0 && (selection_end < selection_start || selection_end > character_count))) {
    kiwi_a11y_set_error("invalid bounded Cocoa accessibility projection");
    return 0;
  }
  NSString *value = [[[NSString alloc] initWithBytes:text length:text_bytes encoding:NSUTF8StringEncoding] autorelease];
  NSString *label = [NSString stringWithUTF8String:title];
  if (value == nil || label == nil) {
    kiwi_a11y_set_error("Cocoa accessibility projection is not valid UTF-8");
    return 0;
  }
  const NSInteger utf16_character_count = kiwi_utf16_index_for_scalar_offset(value, character_count);
  const NSInteger utf16_caret = kiwi_utf16_index_for_scalar_offset(value, caret_offset);
  const NSInteger utf16_selection_start = kiwi_utf16_index_for_scalar_offset(value, selection_start);
  const NSInteger utf16_selection_end = kiwi_utf16_index_for_scalar_offset(value, selection_end);
  if (utf16_character_count == NSNotFound || (caret_offset >= 0 && utf16_caret == NSNotFound)
      || (selection_start >= 0 && (utf16_selection_start == NSNotFound || utf16_selection_end == NSNotFound))) {
    kiwi_a11y_set_error("Cocoa accessibility projection offsets do not match bounded UTF-8 text");
    return 0;
  }
  NSRange selected_range = NSMakeRange(NSNotFound, 0);
  if (selection_start >= 0) {
    selected_range = NSMakeRange((NSUInteger)utf16_selection_start, (NSUInteger)(utf16_selection_end - utf16_selection_start));
  } else if (caret_offset >= 0) {
    selected_range = NSMakeRange((NSUInteger)utf16_caret, 0);
  }
  NSString *selected_text = nil;
  if (selected_range.location != NSNotFound && NSMaxRange(selected_range) <= value.length) {
    selected_text = [value substringWithRange:selected_range];
  }
  NSInteger insertion_line = 0;
  if (utf16_caret != NSNotFound) {
    for (NSUInteger index = 0; index < (NSUInteger)utf16_caret; ++index) {
      if ([value characterAtIndex:index] == '\n') insertion_line += 1;
    }
  }
  adapter->terminal.accessibilityFrameInParentSpace = adapter->view.bounds;
  adapter->terminal.accessibilityLabel = label;
  adapter->terminal.accessibilityValue = value;
  adapter->terminal.accessibilityNumberOfCharacters = utf16_character_count;
  adapter->terminal.accessibilitySelectedTextRange = selected_range;
  adapter->terminal.accessibilitySelectedTextRanges = selected_range.location == NSNotFound ? @[] : @[ [NSValue valueWithRange:selected_range] ];
  adapter->terminal.accessibilitySelectedText = selected_text;
  adapter->terminal.accessibilityInsertionPointLineNumber = insertion_line;
  adapter->terminal.accessibilityVisibleCharacterRange = NSMakeRange(0, (NSUInteger)utf16_character_count);
  adapter->terminal.accessibilityFocused = focused != 0;
  adapter->selected_range = selected_range;
  NSAccessibilityPostNotification(adapter->terminal, NSAccessibilityValueChangedNotification);
  NSAccessibilityPostNotification(adapter->terminal, NSAccessibilitySelectedTextChangedNotification);
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
  int valid = kiwi_accessibility_update(adapter, text, sizeof(text) - 1, 26, 26, 24, 26, 1, title);
  valid = valid && [adapter->terminal.accessibilityIdentifier isEqualToString:@"kiwi.terminal"];
  valid = valid && [adapter->terminal.accessibilityRole isEqualToString:NSAccessibilityTextAreaRole];
  valid = valid && [adapter->terminal.accessibilityLabel isEqualToString:[NSString stringWithUTF8String:title]];
  valid = valid && [adapter->terminal.accessibilityValue isEqualToString:[NSString stringWithUTF8String:text]];
  valid = valid && adapter->terminal.accessibilityNumberOfCharacters == 26;
  valid = valid && NSEqualRanges(adapter->terminal.accessibilitySelectedTextRange, NSMakeRange(24, 2));
  valid = valid && [adapter->terminal.accessibilitySelectedText isEqualToString:@" \xE2\x9C\x93"];
  valid = valid && NSEqualRanges(adapter->terminal.accessibilityVisibleCharacterRange, NSMakeRange(0, 26));
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
