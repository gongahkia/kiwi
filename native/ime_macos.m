#define GLFW_EXPOSE_NATIVE_COCOA
#import <AppKit/AppKit.h>

#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void kiwi_surface_set_error(const char *message);

enum { KIWI_COCOA_TEXT_MAX_BYTES = 1024 };

typedef void (*KiwiCocoaTextInputCallback)(void *userdata, const char *text, size_t text_bytes,
                                           int32_t selection_start, int32_t selection_end);

@interface KiwiCocoaTextInputView : NSView <NSTextInputClient> {
 @public
  NSView *forward_target;
  KiwiCocoaTextInputCallback preedit_callback;
  KiwiCocoaTextInputCallback commit_callback;
  void *callback_userdata;
  NSString *marked_text;
  NSRange marked_selection;
  NSRect caret_rect;
  NSEvent *current_key_event;
  BOOL handled_text;
  BOOL forwarded_command;
}
- (id)initWithFrame:(NSRect)frame target:(NSView *)target preedit:(KiwiCocoaTextInputCallback)preedit
              commit:(KiwiCocoaTextInputCallback)commit userdata:(void *)userdata;
- (void)setCaretX:(double)x y:(double)y width:(double)width height:(double)height;
@end

typedef struct KiwiCocoaTextInput {
  NSView *view;
  KiwiCocoaTextInputView *input;
} KiwiCocoaTextInput;

static void kiwi_text_set_error(const char *message) {
  kiwi_surface_set_error(message);
}

static int32_t kiwi_utf8_offset(NSString *text, NSUInteger utf16_offset) {
  if (utf16_offset == NSNotFound || utf16_offset > text.length) return -1;
  NSData *prefix = [[text substringToIndex:utf16_offset] dataUsingEncoding:NSUTF8StringEncoding];
  if (prefix == nil || prefix.length > INT32_MAX) return -1;
  return (int32_t)prefix.length;
}

static void kiwi_emit_text(KiwiCocoaTextInputCallback callback, void *userdata, NSString *text,
                           NSRange selected_range) {
  if (callback == NULL || text == nil) return;
  NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (utf8 == nil || utf8.length > KIWI_COCOA_TEXT_MAX_BYTES) return;
  int32_t selection_start = kiwi_utf8_offset(text, selected_range.location);
  int32_t selection_end = selected_range.location == NSNotFound || selected_range.length > text.length - selected_range.location
    ? -1 : kiwi_utf8_offset(text, NSMaxRange(selected_range));
  static const char empty[] = "";
  callback(userdata, utf8.length == 0 ? empty : utf8.bytes, utf8.length, selection_start, selection_end);
}

@implementation KiwiCocoaTextInputView

- (id)initWithFrame:(NSRect)frame target:(NSView *)target preedit:(KiwiCocoaTextInputCallback)preedit
              commit:(KiwiCocoaTextInputCallback)commit userdata:(void *)userdata {
  self = [super initWithFrame:frame];
  if (self != nil) {
    forward_target = target;
    preedit_callback = preedit;
    commit_callback = commit;
    callback_userdata = userdata;
    marked_text = [@"" retain];
    marked_selection = NSMakeRange(0, 0);
    caret_rect = NSMakeRect(0, 0, 1, 1);
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidBecomeKey:)
                                                 name:NSWindowDidBecomeKeyNotification object:target.window];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [marked_text release];
  [super dealloc];
}

- (BOOL)acceptsFirstResponder { return YES; }

- (NSView *)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  (void)notification;
  if (self.window != nil) [self.window makeFirstResponder:self];
}

- (void)clearMarkedText {
  if (marked_text.length == 0) return;
  [marked_text release];
  marked_text = [@"" retain];
  marked_selection = NSMakeRange(0, 0);
  kiwi_emit_text(preedit_callback, callback_userdata, marked_text, marked_selection);
}

- (void)setCaretX:(double)x y:(double)y width:(double)width height:(double)height {
  if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) || width <= 0 || height <= 0) return;
  const CGFloat local_y = self.isFlipped ? y : self.bounds.size.height - y - height;
  caret_rect = NSMakeRect(x, local_y, width, height);
}

- (void)keyDown:(NSEvent *)event {
  current_key_event = event;
  handled_text = NO;
  forwarded_command = NO;
  [self interpretKeyEvents:@[event]];
  if (!handled_text && !forwarded_command && forward_target != nil) [forward_target keyDown:event];
  current_key_event = nil;
}

- (void)keyUp:(NSEvent *)event {
  if (forward_target != nil) [forward_target keyUp:event];
}

- (void)flagsChanged:(NSEvent *)event {
  if (forward_target != nil) [forward_target flagsChanged:event];
}

- (BOOL)hasMarkedText { return marked_text.length > 0; }

- (NSRange)markedRange {
  return marked_text.length == 0 ? NSMakeRange(NSNotFound, 0) : NSMakeRange(0, marked_text.length);
}

- (NSRange)selectedRange { return marked_selection; }

- (void)setMarkedText:(id)value selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
  (void)replacementRange;
  NSString *text = [value isKindOfClass:[NSAttributedString class]] ? [value string] : value;
  if (![text isKindOfClass:[NSString class]]) return;
  NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (utf8 == nil || utf8.length > KIWI_COCOA_TEXT_MAX_BYTES || selectedRange.location == NSNotFound
      || selectedRange.location > text.length || selectedRange.length > text.length - selectedRange.location) return;
  handled_text = YES;
  [marked_text release];
  marked_text = [text copy];
  marked_selection = selectedRange;
  kiwi_emit_text(preedit_callback, callback_userdata, marked_text, marked_selection);
}

- (void)unmarkText {
  handled_text = YES;
  [self clearMarkedText];
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
  return @[NSMarkedClauseSegmentAttributeName];
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
  if (range.location == NSNotFound || range.location > marked_text.length) {
    if (actualRange != NULL) *actualRange = NSMakeRange(NSNotFound, 0);
    return nil;
  }
  const NSUInteger length = MIN(range.length, marked_text.length - range.location);
  const NSRange resolved = NSMakeRange(range.location, length);
  if (actualRange != NULL) *actualRange = resolved;
  return [[[NSAttributedString alloc] initWithString:[marked_text substringWithRange:resolved]] autorelease];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
  (void)point;
  return NSNotFound;
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
  if (actualRange != NULL) *actualRange = range;
  NSRect window_rect = [self convertRect:caret_rect toView:nil];
  return self.window == nil ? NSZeroRect : [self.window convertRectToScreen:window_rect];
}

- (void)doCommandBySelector:(SEL)selector {
  (void)selector;
  forwarded_command = YES;
  if (current_key_event != nil && forward_target != nil) [forward_target keyDown:current_key_event];
}

- (void)insertText:(id)value replacementRange:(NSRange)replacementRange {
  (void)replacementRange;
  NSString *text = [value isKindOfClass:[NSAttributedString class]] ? [value string] : value;
  if (![text isKindOfClass:[NSString class]]) return;
  NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (utf8 == nil || utf8.length == 0 || utf8.length > KIWI_COCOA_TEXT_MAX_BYTES) return;
  handled_text = YES;
  [self clearMarkedText];
  kiwi_emit_text(commit_callback, callback_userdata, text, NSMakeRange(0, text.length));
}

@end

KiwiCocoaTextInput *kiwi_cocoa_text_input_new(void *opaque_window, KiwiCocoaTextInputCallback preedit,
                                               KiwiCocoaTextInputCallback commit, void *userdata) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_text_set_error("Cocoa text input must be initialized on the main thread");
      return NULL;
    }
    GLFWwindow *window = opaque_window;
    NSView *view = window == NULL ? nil : glfwGetCocoaView(window);
    if (view == nil || view.window == nil || preedit == NULL || commit == NULL) {
      kiwi_text_set_error("GLFW did not expose a Cocoa view for text input");
      return NULL;
    }
    KiwiCocoaTextInput *adapter = calloc(1, sizeof(*adapter));
    if (adapter == NULL) {
      kiwi_text_set_error("could not allocate Cocoa text-input adapter");
      return NULL;
    }
    adapter->view = [view retain];
    adapter->input = [[KiwiCocoaTextInputView alloc] initWithFrame:view.bounds target:view preedit:preedit commit:commit userdata:userdata];
    if (adapter->input == nil) {
      [adapter->view release];
      free(adapter);
      kiwi_text_set_error("could not create Cocoa text-input responder");
      return NULL;
    }
    [view addSubview:adapter->input];
    if (![view.window makeFirstResponder:adapter->input]) {
      [adapter->input removeFromSuperview];
      [adapter->input release];
      [adapter->view release];
      free(adapter);
      kiwi_text_set_error("Cocoa window rejected the text-input responder");
      return NULL;
    }
    return adapter;
  }
}

void kiwi_cocoa_text_input_destroy(KiwiCocoaTextInput *adapter) {
  if (adapter == NULL) return;
  if (adapter->input != nil) {
    if (adapter->input.window.firstResponder == adapter->input) [adapter->input.window makeFirstResponder:adapter->view];
    [adapter->input removeFromSuperview];
    [adapter->input release];
  }
  [adapter->view release];
  free(adapter);
}

void kiwi_cocoa_text_input_set_caret(KiwiCocoaTextInput *adapter, double x, double y, double width, double height) {
  if (adapter != NULL) [adapter->input setCaretX:x y:y width:width height:height];
}

typedef struct KiwiCocoaTextInputSmoke {
  int preedit_calls;
  int commit_calls;
  int saw_marked_text;
  int saw_clear;
  int saw_commit_text;
  int32_t preedit_start;
  int32_t preedit_end;
} KiwiCocoaTextInputSmoke;

static void kiwi_cocoa_text_input_smoke_preedit(void *userdata, const char *text, size_t text_bytes,
                                                 int32_t selection_start, int32_t selection_end) {
  KiwiCocoaTextInputSmoke *smoke = userdata;
  smoke->preedit_calls += 1;
  if (text_bytes == 3 && memcmp(text, "\xE4\xB8\xAD", 3) == 0) {
    smoke->saw_marked_text = 1;
    smoke->preedit_start = selection_start;
    smoke->preedit_end = selection_end;
  }
  if (text_bytes == 0) smoke->saw_clear = 1;
}

static void kiwi_cocoa_text_input_smoke_commit(void *userdata, const char *text, size_t text_bytes,
                                                int32_t selection_start, int32_t selection_end) {
  (void)selection_start;
  (void)selection_end;
  KiwiCocoaTextInputSmoke *smoke = userdata;
  smoke->commit_calls += 1;
  if (text_bytes == 3 && memcmp(text, "\xE8\xAA\x9E", 3) == 0) smoke->saw_commit_text = 1;
}

int kiwi_cocoa_text_input_round_trip(void *opaque_window) {
  @autoreleasepool {
    KiwiCocoaTextInputSmoke smoke = {0};
    KiwiCocoaTextInput *adapter = kiwi_cocoa_text_input_new(opaque_window, kiwi_cocoa_text_input_smoke_preedit,
                                                             kiwi_cocoa_text_input_smoke_commit, &smoke);
    if (adapter == NULL) return 0;
    [adapter->input setCaretX:12 y:18 width:9 height:18];
    [adapter->input setMarkedText:@"中" selectedRange:NSMakeRange(0, 1) replacementRange:NSMakeRange(NSNotFound, 0)];
    NSRange actual = NSMakeRange(NSNotFound, 0);
    NSRect candidate_rect = [adapter->input firstRectForCharacterRange:NSMakeRange(0, 0) actualRange:&actual];
    [adapter->input insertText:@"語" replacementRange:NSMakeRange(NSNotFound, 0)];
    const int valid = smoke.preedit_calls >= 2 && smoke.commit_calls == 1 && smoke.saw_marked_text && smoke.saw_clear
      && smoke.saw_commit_text && smoke.preedit_start == 0 && smoke.preedit_end == 3 && actual.location == 0
      && candidate_rect.size.width > 0 && candidate_rect.size.height > 0;
    kiwi_cocoa_text_input_destroy(adapter);
    if (!valid) kiwi_text_set_error("Cocoa text-input round trip did not preserve marked text, commit, and candidate geometry");
    return valid;
  }
}

int kiwi_cocoa_text_input_inject_smoke(KiwiCocoaTextInput *adapter) {
  @autoreleasepool {
    if (adapter == NULL || adapter->input == nil) {
      kiwi_text_set_error("Cocoa text-input smoke needs an active responder");
      return 0;
    }
    [adapter->input setMarkedText:@"中" selectedRange:NSMakeRange(0, 1) replacementRange:NSMakeRange(NSNotFound, 0)];
    [adapter->input insertText:@"語" replacementRange:NSMakeRange(NSNotFound, 0)];
    return 1;
  }
}
