#import <AppKit/AppKit.h>
#include <assert.h>

static unsigned value_events, selection_events, focus_events;
static void record_notification(id element, NSString *notification) {
  assert(element != nil);
  if ([notification isEqualToString:NSAccessibilityValueChangedNotification]) value_events++;
  else if ([notification isEqualToString:NSAccessibilitySelectedTextChangedNotification]) selection_events++;
  else if ([notification isEqualToString:NSAccessibilityFocusedUIElementChangedNotification]) focus_events++;
  else assert(!"unexpected notification");
}
// Exercise the production bridge and AppKit text element, recording its explicit
// notifications without requiring accessibility permission or a visible window.
#define NSAccessibilityPostNotification record_notification
#include "../../../native/accessibility_macos.m"
#undef NSAccessibilityPostNotification

static void range_equals(NSRange actual, NSUInteger location, NSUInteger length) {
  assert(NSEqualRanges(actual, NSMakeRange(location, length)));
}
static int update(KiwiAccessibility *adapter, const char *text, int32_t count, int32_t caret,
                  int32_t start, int32_t end, int focus) {
  return kiwi_accessibility_update(adapter, text, strlen(text), count, caret, start, end, focus, "fixture");
}
int main(void) {
  @autoreleasepool {
    KiwiAccessibility adapter = {0};
    adapter.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 480)];
    adapter.terminal = [[KiwiTerminalAccessibilityElement accessibilityElementWithRole:NSAccessibilityTextAreaRole
      frame:NSMakeRect(0, 0, 800, 480) label:@"fixture" parent:adapter.view] retain];
    assert([adapter.terminal isKindOfClass:[KiwiTerminalAccessibilityElement class]]);
    adapter.active = 1;
    // Scalar offsets 0..10 map to UTF-16 offsets 0..11; the emoji occupies two
    // code units and e+accent remains one composed character in range queries.
    const char *text = "A😀é\n界\nend";
    assert(update(&adapter, text, 10, 4, 1, 4, 1));
    assert(adapter.terminal.accessibilityNumberOfCharacters == 11);
    range_equals(adapter.terminal.accessibilitySelectedTextRange, 1, 4);
    assert([adapter.terminal.accessibilitySelectedText isEqualToString:@"😀é"]);
    assert(value_events == 1 && selection_events == 1 && focus_events == 1);
    for (unsigned index = 0; index < 1000; ++index) assert(update(&adapter, text, 10, 4, 1, 4, 1));
    assert(value_events == 1 && selection_events == 1 && focus_events == 1);
    assert(update(&adapter, text, 10, 6, -1, -1, 1));
    range_equals(adapter.terminal.accessibilitySelectedTextRange, 7, 0);
    assert(adapter.terminal.accessibilityInsertionPointLineNumber == 1);
    assert(value_events == 1 && selection_events == 2 && focus_events == 1);
    assert(update(&adapter, text, 10, 6, -1, -1, 0));
    assert(update(&adapter, text, 10, 6, -1, -1, 1));
    assert(value_events == 1 && selection_events == 2 && focus_events == 2);
    assert(!update(&adapter, text, 9, 6, -1, -1, 1));
    assert(!update(&adapter, text, 11, 6, -1, -1, 1));
    assert(!update(&adapter, text, 10, 6, 3, 11, 1));
    assert([adapter.terminal.accessibilityValue isEqualToString:@"A😀é\n界\nend"]);
    assert(value_events == 1 && selection_events == 2 && focus_events == 2);
    KiwiTerminalAccessibilityElement *element = (KiwiTerminalAccessibilityElement *)adapter.terminal;
    assert([[element accessibilityStringForRange:NSMakeRange(1, 4)] isEqualToString:@"😀é"]);
    assert([[element accessibilityAttributedStringForRange:NSMakeRange(1, 4)].string isEqualToString:@"😀é"]);
    assert([[element accessibilityAttributedStringForRange:NSMakeRange(1, 4)] attributesAtIndex:0 effectiveRange:NULL].count == 0);
    assert([[element accessibilityStringForRange:NSMakeRange(11, 0)] isEqualToString:@""]);
    assert([element accessibilityStringForRange:NSMakeRange(12, 0)] == nil);
    assert([element accessibilityStringForRange:NSMakeRange(NSNotFound, 1)] == nil);
    assert([element accessibilityStringForRange:NSMakeRange(1, NSUIntegerMax)] == nil);
    assert([element accessibilityStringForRange:NSMakeRange(1, 1)] == nil);
    assert([element accessibilityStringForRange:NSMakeRange(2, 1)] == nil);
    assert([element accessibilityStringForRange:NSMakeRange(2, 0)] == nil);
    assert([element accessibilityAttributedStringForRange:NSMakeRange(2, 1)] == nil);
    range_equals([element accessibilityRangeForLine:0], 0, 6);
    range_equals([element accessibilityRangeForLine:1], 6, 2);
    range_equals([element accessibilityRangeForLine:2], 8, 3);
    range_equals([element accessibilityRangeForLine:-1], NSNotFound, 0);
    range_equals([element accessibilityRangeForLine:3], NSNotFound, 0);
    range_equals([element accessibilityRangeForLine:NSIntegerMax], NSNotFound, 0);
    for (NSInteger index = 0; index <= 11; ++index) {
      assert([element accessibilityLineForIndex:index] == (index < 6 ? 0 : index < 8 ? 1 : 2));
    }
    assert([element accessibilityLineForIndex:-1] == NSNotFound);
    assert([element accessibilityLineForIndex:12] == NSNotFound);
    assert([element accessibilityLineForIndex:NSIntegerMax] == NSNotFound);
    range_equals([element accessibilityRangeForIndex:1], 1, 2);
    range_equals([element accessibilityRangeForIndex:2], 1, 2);
    range_equals([element accessibilityRangeForIndex:3], 3, 2);
    range_equals([element accessibilityRangeForIndex:4], 3, 2);
    range_equals([element accessibilityRangeForIndex:11], 11, 0);
    range_equals([element accessibilityRangeForIndex:12], NSNotFound, 0);
    range_equals([element accessibilityRangeForIndex:-1], NSNotFound, 0);
    assert(update(&adapter, "👩‍💻", 3, 3, -1, -1, 1));
    for (NSInteger index = 0; index < 5; ++index) range_equals([element accessibilityRangeForIndex:index], 0, 5);
    assert(!update(&adapter, "\xff", 1, 1, -1, -1, 1));
    assert([element.accessibilityValue isEqualToString:@"👩‍💻"]);
    char *oversized = malloc(KIWI_A11Y_MAX_TEXT_BYTES + 2);
    assert(oversized != NULL);
    memset(oversized, 'x', KIWI_A11Y_MAX_TEXT_BYTES + 1);
    oversized[KIWI_A11Y_MAX_TEXT_BYTES + 1] = '\0';
    assert(!update(&adapter, oversized, KIWI_A11Y_MAX_TEXT_BYTES + 1, 0, -1, -1, 1));
    free(oversized);
    assert([element.accessibilityValue isEqualToString:@"👩‍💻"]);
    assert(update(&adapter, "A", 1, 1, 0, 1, 1));
    const unsigned previous_values = value_events, previous_selections = selection_events;
    assert(update(&adapter, "B", 1, 1, 0, 1, 1));
    assert(value_events == previous_values + 1 && selection_events == previous_selections + 1);
    assert(update(&adapter, "\n\n", 2, 2, -1, -1, 1));
    range_equals([element accessibilityRangeForLine:0], 0, 1);
    range_equals([element accessibilityRangeForLine:1], 1, 1);
    range_equals([element accessibilityRangeForLine:2], 2, 0);
    range_equals([element accessibilityRangeForLine:3], NSNotFound, 0);
    assert([element accessibilityLineForIndex:2] == 2);
    assert(update(&adapter, "", 0, 0, -1, -1, 1));
    range_equals([element accessibilityRangeForLine:0], 0, 0);
    range_equals([element accessibilityRangeForIndex:0], 0, 0);
    assert([[element accessibilityStringForRange:NSMakeRange(0, 0)] isEqualToString:@""]);
    [adapter.terminal release];
    [adapter.view release];
  }
  puts("Cocoa accessibility passed: UTF-16 and composed ranges, physical lines, malformed offsets, empty text, and notification deduplication.");
  return 0;
}
