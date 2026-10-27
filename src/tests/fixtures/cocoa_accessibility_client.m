#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned value_events, selection_events, focus_events;
static void observe(AXObserverRef observer, AXUIElementRef element, CFStringRef name, void *context) {
  (void)observer; (void)element; (void)context;
  if (CFEqual(name, kAXValueChangedNotification)) value_events++;
  else if (CFEqual(name, kAXSelectedTextChangedNotification)) selection_events++;
  else if (CFEqual(name, kAXFocusedUIElementChangedNotification)) focus_events++;
}
static void require(BOOL condition, NSString *message) {
  if (!condition) @throw [NSException exceptionWithName:@"KiwiAXFixtureFailure" reason:message userInfo:nil];
}
static id attribute(AXUIElementRef element, CFStringRef name) {
  CFTypeRef value = NULL;
  if (AXUIElementCopyAttributeValue(element, name, &value) != kAXErrorSuccess) return nil;
  return CFBridgingRelease(value);
}
static AXUIElementRef find_terminal(AXUIElementRef root, unsigned depth, unsigned *count) {
  if (depth > 12 || ++*count > 512) return NULL;
  if ([attribute(root, kAXIdentifierAttribute) isEqualToString:@"kiwi.terminal"]) return (AXUIElementRef)CFRetain(root);
  CFArrayRef children = NULL;
  if (AXUIElementCopyAttributeValues(root, kAXChildrenAttribute, 0, 128, &children) != kAXErrorSuccess) return NULL;
  AXUIElementRef found = NULL;
  for (CFIndex index = 0; index < CFArrayGetCount(children) && !found; ++index)
    found = find_terminal((AXUIElementRef)CFArrayGetValueAtIndex(children, index), depth + 1, count);
  CFRelease(children);
  return found;
}
static CFRange range_value(id value) {
  CFRange range = CFRangeMake(-1, -1);
  require(value && CFGetTypeID((__bridge CFTypeRef)value) == AXValueGetTypeID()
    && AXValueGetValue((__bridge AXValueRef)value, kAXValueCFRangeType, &range), @"expected AX UTF-16 range");
  return range;
}
static id parameter(AXUIElementRef element, CFStringRef name, id argument) {
  CFTypeRef result = NULL;
  AXError error = AXUIElementCopyParameterizedAttributeValue(element, name, (__bridge CFTypeRef)argument, &result);
  require(error == kAXErrorSuccess, [NSString stringWithFormat:@"parameter %@ failed: %d", name, error]);
  return CFBridgingRelease(result);
}
static id range_argument(NSRange range) {
  CFRange native = CFRangeMake((CFIndex)range.location, (CFIndex)range.length);
  return CFBridgingRelease(AXValueCreate(kAXValueCFRangeType, &native));
}
static void range_equals(id value, NSRange expected) {
  CFRange actual = range_value(value);
  require(actual.location == (CFIndex)expected.location && actual.length == (CFIndex)expected.length, @"AX range differs from expected UTF-16 offsets");
}
static void pump(double seconds) {
  CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + seconds;
  do { CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false); } while (CFAbsoluteTimeGetCurrent() < deadline);
}
static void command(NSString *path, NSString *value) {
  require([value writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"could not write fixture request");
}
static void wait_title(AXUIElementRef terminal, NSString *title) {
  for (unsigned index = 0; index < 150; ++index) {
    NSString *label = attribute(terminal, kAXDescriptionAttribute);
    if ([label containsString:title]) return;
    pump(.02);
  }
  require(NO, [@"terminal did not process fixture stage: " stringByAppendingString:title]);
}
int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc == 2 && strcmp(argv[1], "--check-trust") == 0) return AXIsProcessTrusted() ? 0 : 3;
    NSMutableDictionary *report = [@{ @"status": @"failed", @"scope": @"external AX text/range queries and notifications; not VoiceOver speech or navigation" } mutableCopy];
    AXUIElementRef app = NULL, terminal = NULL;
    AXObserverRef observer = NULL;
    int status = 1;
    @try {
      require(argc == 3 && atoi(argv[1]) > 0, @"client requires owned application PID and request path");
      require(AXIsProcessTrusted(), @"accessibility client permission unavailable; no settings were changed");
      pid_t pid = atoi(argv[1]);
      NSString *request = [NSString stringWithUTF8String:argv[2]];
      app = AXUIElementCreateApplication(pid);
      AXUIElementSetMessagingTimeout(app, .5);
      for (unsigned attempt = 0; attempt < 100 && !terminal; ++attempt) {
        CFArrayRef windows = NULL;
        if (AXUIElementCopyAttributeValues(app, kAXWindowsAttribute, 0, 8, &windows) == kAXErrorSuccess) {
          unsigned count = 0;
          for (CFIndex index = 0; index < CFArrayGetCount(windows) && !terminal; ++index)
            terminal = find_terminal((AXUIElementRef)CFArrayGetValueAtIndex(windows, index), 0, &count);
          CFRelease(windows);
        }
        if (!terminal) pump(.05);
      }
      require(terminal != NULL, @"owned Kiwi terminal was not exposed in the accessibility tree");
      wait_title(terminal, @"kiwi-ax-ready");
      NSString *text = attribute(terminal, kAXValueAttribute);
      require([text isKindOfClass:[NSString class]] && text.length <= 65536 && [text hasPrefix:@"alpha 界 😀"], @"initial Unicode viewport is missing or unbounded");
      require([text containsString:@"beta é"] && [text containsString:@"last ✓"], @"initial physical lines missing");
      require([attribute(terminal, kAXRoleAttribute) isEqualToString:@"AXTextArea"], @"terminal role differs");
      require([attribute(terminal, kAXNumberOfCharactersAttribute) unsignedIntegerValue] == text.length, @"character count is not UTF-16 length");
      range_equals(attribute(terminal, kAXVisibleCharacterRangeAttribute), NSMakeRange(0, text.length));
      NSMutableDictionary *writes = [NSMutableDictionary dictionary];
      report[@"write_attempts"] = writes;
      CFRange selection_before = range_value(attribute(terminal, kAXSelectedTextRangeAttribute));
      NSString *selected_before = attribute(terminal, kAXSelectedTextAttribute);
      for (NSString *name in @[@"AXValue", @"AXSelectedText", @"AXSelectedTextRange"]) {
        Boolean settable = true;
        require(AXUIElementIsAttributeSettable(terminal, (__bridge CFStringRef)name, &settable) == kAXErrorSuccess && !settable, @"terminal projection must remain read-only");
        id replacement = [name isEqualToString:@"AXSelectedTextRange"] ? range_argument(NSMakeRange(0, 1)) : @"fixture mutation";
        AXError write_error = AXUIElementSetAttributeValue(terminal, (__bridge CFStringRef)name, (__bridge CFTypeRef)replacement);
        BOOL text_unchanged = [attribute(terminal, kAXValueAttribute) isEqualToString:text];
        CFRange selection_after = range_value(attribute(terminal, kAXSelectedTextRangeAttribute));
        BOOL selection_unchanged = selection_before.location == selection_after.location
          && selection_before.length == selection_after.length
          && [attribute(terminal, kAXSelectedTextAttribute) isEqualToString:selected_before];
        writes[name] = @{ @"error": @(write_error), @"text_unchanged": @(text_unchanged), @"selection_unchanged": @(selection_unchanged) };
        require(text_unchanged, [@"read-only terminal text changed after setting " stringByAppendingString:name]);
        require(selection_unchanged, [@"read-only terminal selection changed after setting " stringByAppendingString:name]);
      }
      require([attribute(terminal, kAXValueAttribute) isEqualToString:text], @"external mutation changed terminal text");
      const NSRange emoji = [text rangeOfString:@"😀"], combining = [text rangeOfString:@"é"];
      for (NSValue *boxed in @[[NSValue valueWithRange:emoji], [NSValue valueWithRange:combining]]) {
        NSRange range = boxed.rangeValue;
        require([parameter(terminal, kAXStringForRangeParameterizedAttribute, range_argument(range)) isEqualToString:[text substringWithRange:range]], @"Unicode substring differs");
        for (NSUInteger index = range.location; index < NSMaxRange(range); ++index)
          range_equals(parameter(terminal, kAXRangeForIndexParameterizedAttribute, @(index)), range);
      }
      NSAttributedString *attributed = parameter(terminal, kAXAttributedStringForRangeParameterizedAttribute, range_argument(emoji));
      require([attributed isKindOfClass:[NSAttributedString class]] && [attributed.string isEqualToString:@"😀"], @"plain attributed substring differs");
      const NSUInteger first_end = [text rangeOfString:@"\n"].location + 1;
      const NSUInteger second_end = NSMaxRange([text rangeOfString:@"\n" options:0 range:NSMakeRange(first_end, text.length - first_end)]);
      range_equals(parameter(terminal, kAXRangeForLineParameterizedAttribute, @0), NSMakeRange(0, first_end));
      range_equals(parameter(terminal, kAXRangeForLineParameterizedAttribute, @1), NSMakeRange(first_end, second_end - first_end));
      require([parameter(terminal, kAXLineForIndexParameterizedAttribute, @(first_end)) integerValue] == 1, @"line mapping differs");
      range_equals(parameter(terminal, kAXRangeForIndexParameterizedAttribute, @(text.length)), NSMakeRange(text.length, 0));
      const NSRange last = [text rangeOfString:@"last ✓"];
      range_equals(attribute(terminal, kAXSelectedTextRangeAttribute), NSMakeRange(NSMaxRange(last), 0));
      require([attribute(terminal, kAXInsertionPointLineNumberAttribute) integerValue] == 2, @"caret line differs");
      report[@"text_queries"] = @"passed";
      report[@"utf16_characters"] = @(text.length);
      require(AXObserverCreate(pid, observe, &observer) == kAXErrorSuccess, @"could not create AX observer");
      for (NSString *name in @[@"AXValueChanged", @"AXSelectedTextChanged", @"AXFocusedUIElementChanged"])
        require(AXObserverAddNotification(observer, terminal, (__bridge CFStringRef)name, NULL) == kAXErrorSuccess, @"could not subscribe to AX notification");
      CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), kCFRunLoopDefaultMode);
      pump(.1);
      const unsigned old_values = value_events, old_selections = selection_events, old_focus = focus_events;
      command(request, @"unchanged");
      wait_title(terminal, @"kiwi-ax-unchanged");
      pump(.1);
      require(value_events == old_values && selection_events == old_selections, @"unchanged PTY turns emitted text or selection notifications");
      require(focus_events == old_focus, @"unchanged PTY turns repeated focus notifications");
      require([attribute(terminal, kAXValueAttribute) isEqualToString:text], @"unchanged stage modified text");
      report[@"unchanged_notifications"] = @"passed";
      command(request, @"update");
      wait_title(terminal, @"kiwi-ax-updated");
      pump(.1);
      require([attribute(terminal, kAXValueAttribute) containsString:@"updated ✓"], @"new PTY text missing");
      require(value_events > old_values && selection_events > old_selections, @"changed text/caret notifications missing");
      report[@"events"] = @{ @"value": @(value_events), @"selection": @(selection_events), @"focus": @(focus_events) };
      report[@"status"] = @"complete";
      status = 0;
    } @catch (NSException *exception) {
      report[@"failure"] = exception.reason ?: @"unknown AX failure";
    }
    if (observer) {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), kCFRunLoopDefaultMode);
      CFRelease(observer);
    }
    if (terminal) CFRelease(terminal);
    if (app) CFRelease(app);
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
    fwrite(json.bytes, 1, json.length, stdout); putchar('\n');
    return status;
  }
}
