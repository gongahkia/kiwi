#define GLFW_EXPOSE_NATIVE_COCOA
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <QuartzCore/CAMetalLayer.h>

#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <webgpu/webgpu.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

extern void kiwi_surface_set_error(const char *message);

typedef void (*KiwiCocoaMenuCallback)(void *userdata, uint32_t action);
typedef int (*KiwiCocoaAutomationCallback)(void *userdata, uint32_t action);

typedef struct KiwiCocoaCommandPaletteEntry {
  uint32_t action;
  const char *title;
  const char *description;
} KiwiCocoaCommandPaletteEntry;

typedef struct KiwiCocoaStandaloneWindow {
  NSWindow *window;
  struct KiwiCocoaStandaloneWindow *next;
} KiwiCocoaStandaloneWindow;

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
  KIWI_COCOA_MENU_COMMAND_PALETTE = 12,
  KIWI_COCOA_MENU_OPEN_CONFIGURATION = 13,
};

@interface KiwiCocoaMenuRegistration : NSObject {
 @public
  KiwiCocoaMenuCallback callback;
  void *userdata;
}
@end

@implementation KiwiCocoaMenuRegistration
@end

@interface KiwiCocoaAutomationRegistration : NSObject {
 @public
  KiwiCocoaAutomationCallback callback;
  void *userdata;
}
@end

@implementation KiwiCocoaAutomationRegistration
@end

@interface KiwiCocoaProgressRegistration : NSObject {
 @public
  NSTitlebarAccessoryViewController *controller;
  NSProgressIndicator *indicator;
}
@end

@implementation KiwiCocoaProgressRegistration
@end

@interface KiwiCocoaMenuDispatcher : NSObject <NSToolbarDelegate>
- (void)invokeAction:(id)sender;
@end

@interface KiwiCocoaAutomationDispatcher : NSObject
- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply;
@end

@interface KiwiCocoaCommandPalette : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate> {
 @public
  KiwiCocoaMenuCallback callback;
  void *userdata;
  NSWindow *_parent;
  NSPanel *_panel;
  NSSearchField *_search;
  NSTableView *_table;
  NSArray *_entries;
  NSMutableArray *_filtered;
  BOOL _invoked;
}
- (id)initWithWindow:(NSWindow *)window entries:(const KiwiCocoaCommandPaletteEntry *)entries count:(size_t)count;
- (void)show;
- (void)close;
- (void)invokeSelection:(id)sender;
@end

static NSMutableDictionary *kiwi_cocoa_menu_registrations;
static KiwiCocoaMenuDispatcher *kiwi_cocoa_menu_dispatcher;
static KiwiCocoaMenuRegistration *kiwi_cocoa_active_menu_registration;
static NSMutableDictionary *kiwi_cocoa_automation_registrations;
static KiwiCocoaAutomationDispatcher *kiwi_cocoa_automation_dispatcher;
static KiwiCocoaAutomationRegistration *kiwi_cocoa_active_automation_registration;
static NSMutableDictionary *kiwi_cocoa_progress_registrations;
static NSMutableDictionary *kiwi_cocoa_command_palette_registrations;
static NSWindow *kiwi_cocoa_tab_group_leader;
static KiwiCocoaStandaloneWindow *kiwi_cocoa_standalone_windows;

static NSString *const KIWI_COCOA_TOOLBAR_IDENTIFIER = @"io.github.gongahkia.kiwi.toolbar";
static NSString *const KIWI_COCOA_TOOLBAR_NEW_TAB = @"io.github.gongahkia.kiwi.toolbar.new-tab";
static NSString *const KIWI_COCOA_TOOLBAR_SPLIT_RIGHT = @"io.github.gongahkia.kiwi.toolbar.split-right";
static NSString *const KIWI_COCOA_TOOLBAR_SPLIT_DOWN = @"io.github.gongahkia.kiwi.toolbar.split-down";
static NSString *const KIWI_COCOA_TOOLBAR_COMMAND_PALETTE = @"io.github.gongahkia.kiwi.toolbar.command-palette";
static NSString *const KIWI_COCOA_TOOLBAR_SETTINGS = @"io.github.gongahkia.kiwi.toolbar.settings";

static int kiwi_cocoa_key_scalar(const UniChar *characters, UniCharCount length, uint32_t *output) {
  if (characters == NULL || output == NULL || length == 0 || length > 2) return 0;
  uint32_t scalar = characters[0];
  if (length == 2) {
    if (characters[0] < 0xd800 || characters[0] > 0xdbff || characters[1] < 0xdc00 || characters[1] > 0xdfff) return 0;
    scalar = 0x10000u + (((uint32_t)characters[0] - 0xd800u) << 10) + ((uint32_t)characters[1] - 0xdc00u);
  } else if (scalar >= 0xd800u && scalar <= 0xdfffu) {
    return 0;
  }
  if (scalar < 0x20u || scalar > 0x10ffffu || (scalar >= 0x7fu && scalar <= 0x9fu)) return 0;
  *output = scalar;
  return 1;
}

static int kiwi_cocoa_key_translate(const UCKeyboardLayout *layout, UInt16 keycode, UInt32 modifiers, uint32_t *output) {
  UInt32 dead_key_state = 0;
  UniChar characters[2] = { 0 };
  UniCharCount length = 0;
  OSStatus status = UCKeyTranslate(layout, keycode, kUCKeyActionDown, modifiers, LMGetKbdType(), kUCKeyTranslateNoDeadKeysBit, &dead_key_state, 2, &length, characters);
  return status == noErr && kiwi_cocoa_key_scalar(characters, length, output);
}

int kiwi_cocoa_key_variants(int scancode, uint32_t *layout_key, uint32_t *shifted_key) {
  @autoreleasepool {
    if (![NSThread isMainThread] || layout_key == NULL || shifted_key == NULL || scancode < 0 || scancode > UINT16_MAX) return 0;
    TISInputSourceRef input_source = TISCopyCurrentKeyboardLayoutInputSource();
    if (input_source == NULL) return 0;
    CFDataRef layout_data = (CFDataRef)TISGetInputSourceProperty(input_source, kTISPropertyUnicodeKeyLayoutData);
    const UCKeyboardLayout *layout = layout_data == NULL ? NULL : (const UCKeyboardLayout *)CFDataGetBytePtr(layout_data);
    uint32_t unshifted = 0;
    uint32_t shifted = 0;
    int translated = layout != NULL && kiwi_cocoa_key_translate(layout, (UInt16)scancode, 0, &unshifted) && kiwi_cocoa_key_translate(layout, (UInt16)scancode, shiftKey >> 8, &shifted);
    CFRelease(input_source);
    if (!translated) return 0;
    *layout_key = unshifted;
    *shifted_key = shifted;
    return 1;
  }
}

static BOOL kiwi_cocoa_menu_action_is_valid(uint32_t action) {
  return action >= KIWI_COCOA_MENU_NEW_TAB && action <= KIWI_COCOA_MENU_OPEN_CONFIGURATION;
}

static NSValue *kiwi_cocoa_menu_window_key(GLFWwindow *window) {
  NSWindow *native_window = window == NULL ? nil : glfwGetCocoaWindow(window);
  return native_window == nil ? nil : [NSValue valueWithPointer:native_window];
}

static NSWindow *kiwi_cocoa_native_window(GLFWwindow *window) {
  return window == NULL ? nil : glfwGetCocoaWindow(window);
}

static BOOL kiwi_cocoa_window_is_registered_standalone(NSWindow *window) {
  for (KiwiCocoaStandaloneWindow *entry = kiwi_cocoa_standalone_windows; entry != NULL; entry = entry->next) {
    if (entry->window == window) return YES;
  }
  return NO;
}

static BOOL kiwi_cocoa_set_window_standalone(NSWindow *window, BOOL standalone) {
  KiwiCocoaStandaloneWindow **link = &kiwi_cocoa_standalone_windows;
  while (*link != NULL) {
    KiwiCocoaStandaloneWindow *entry = *link;
    if (entry->window != window) {
      link = &entry->next;
      continue;
    }
    if (standalone) return YES;
    *link = entry->next;
    free(entry);
    return YES;
  }
  if (!standalone) return YES;
  KiwiCocoaStandaloneWindow *entry = calloc(1, sizeof(*entry));
  if (entry == NULL) return NO;
  entry->window = window;
  entry->next = kiwi_cocoa_standalone_windows;
  kiwi_cocoa_standalone_windows = entry;
  return YES;
}

enum {
  KIWI_COCOA_AUTOMATION_CLASS = UINT32_C(0x4b697769), /* Kiwi */
  KIWI_COCOA_AUTOMATION_NEW_WINDOW = UINT32_C(0x4e576477), /* NWdw */
  KIWI_COCOA_AUTOMATION_NEW_TAB = UINT32_C(0x4e546162), /* NTab */
  KIWI_COCOA_AUTOMATION_NEXT_TAB = UINT32_C(0x4e547874), /* NTxt */
  KIWI_COCOA_AUTOMATION_CLOSE_PANE = UINT32_C(0x43506e65), /* CPne */
  KIWI_COCOA_AUTOMATION_SPLIT_RIGHT = UINT32_C(0x53526774), /* SRgt */
  KIWI_COCOA_AUTOMATION_SPLIT_DOWN = UINT32_C(0x5344776e), /* SDwn */
  KIWI_COCOA_AUTOMATION_RELOAD_CONFIGURATION = UINT32_C(0x52636667), /* Rcfg */
  KIWI_COCOA_AUTOMATION_OPEN_CONFIGURATION = UINT32_C(0x4f636667), /* Ocfg */
};

static uint32_t kiwi_cocoa_automation_action_for_event(uint32_t event) {
  switch (event) {
    case KIWI_COCOA_AUTOMATION_NEW_WINDOW: return KIWI_COCOA_MENU_NEW_WINDOW;
    case KIWI_COCOA_AUTOMATION_NEW_TAB: return KIWI_COCOA_MENU_NEW_TAB;
    case KIWI_COCOA_AUTOMATION_NEXT_TAB: return KIWI_COCOA_MENU_NEXT_TAB;
    case KIWI_COCOA_AUTOMATION_CLOSE_PANE: return KIWI_COCOA_MENU_CLOSE_PANE;
    case KIWI_COCOA_AUTOMATION_SPLIT_RIGHT: return KIWI_COCOA_MENU_SPLIT_RIGHT;
    case KIWI_COCOA_AUTOMATION_SPLIT_DOWN: return KIWI_COCOA_MENU_SPLIT_DOWN;
    case KIWI_COCOA_AUTOMATION_RELOAD_CONFIGURATION: return KIWI_COCOA_MENU_RELOAD_CONFIGURATION;
    case KIWI_COCOA_AUTOMATION_OPEN_CONFIGURATION: return KIWI_COCOA_MENU_OPEN_CONFIGURATION;
    default: return 0;
  }
}

static uint32_t kiwi_cocoa_automation_event_for_action(uint32_t action) {
  switch (action) {
    case KIWI_COCOA_MENU_NEW_WINDOW: return KIWI_COCOA_AUTOMATION_NEW_WINDOW;
    case KIWI_COCOA_MENU_NEW_TAB: return KIWI_COCOA_AUTOMATION_NEW_TAB;
    case KIWI_COCOA_MENU_NEXT_TAB: return KIWI_COCOA_AUTOMATION_NEXT_TAB;
    case KIWI_COCOA_MENU_CLOSE_PANE: return KIWI_COCOA_AUTOMATION_CLOSE_PANE;
    case KIWI_COCOA_MENU_SPLIT_RIGHT: return KIWI_COCOA_AUTOMATION_SPLIT_RIGHT;
    case KIWI_COCOA_MENU_SPLIT_DOWN: return KIWI_COCOA_AUTOMATION_SPLIT_DOWN;
    case KIWI_COCOA_MENU_RELOAD_CONFIGURATION: return KIWI_COCOA_AUTOMATION_RELOAD_CONFIGURATION;
    case KIWI_COCOA_MENU_OPEN_CONFIGURATION: return KIWI_COCOA_AUTOMATION_OPEN_CONFIGURATION;
    default: return 0;
  }
}

@implementation KiwiCocoaCommandPalette

- (id)initWithWindow:(NSWindow *)window entries:(const KiwiCocoaCommandPaletteEntry *)entries count:(size_t)count {
  self = [super init];
  if (self == nil) return nil;
  _parent = [window retain];
  _entries = [[NSMutableArray alloc] initWithCapacity:count];
  _filtered = [[NSMutableArray alloc] initWithCapacity:count];
  for (size_t index = 0; index < count; index += 1) {
    NSString *title = [[NSString alloc] initWithUTF8String:entries[index].title];
    NSString *description = [[NSString alloc] initWithUTF8String:entries[index].description];
    if (title == nil || description == nil || title.length == 0) {
      [title release];
      [description release];
      [self release];
      return nil;
    }
    NSDictionary *entry = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSNumber numberWithUnsignedInt:entries[index].action], @"action",
        title, @"title", description, @"description", nil];
    [(NSMutableArray *)_entries addObject:entry];
    [entry release];
    [title release];
    [description release];
  }
  _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 520.0, 340.0)
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:NO];
  if (_panel == nil) {
    [self release];
    return nil;
  }
  _panel.title = @"Command Palette";
  _panel.hidesOnDeactivate = NO;
  _panel.releasedWhenClosed = NO;
  NSView *content = _panel.contentView;
  _search = [[NSSearchField alloc] initWithFrame:NSMakeRect(16.0, 296.0, 488.0, 28.0)];
  _search.placeholderString = @"Type to filter actions";
  _search.delegate = self;
  _search.target = self;
  _search.action = @selector(searchChanged:);
  [_search setSendsSearchStringImmediately:YES];
  [content addSubview:_search];
  _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 488.0, 272.0)];
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"command"];
  column.width = 488.0;
  [_table addTableColumn:column];
  [column release];
  _table.headerView = nil;
  _table.rowHeight = 44.0;
  _table.intercellSpacing = NSMakeSize(0.0, 2.0);
  _table.dataSource = self;
  _table.delegate = self;
  _table.target = self;
  _table.doubleAction = @selector(invokeSelection:);
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16.0, 16.0, 488.0, 270.0)];
  scroll.documentView = _table;
  scroll.hasVerticalScroller = YES;
  scroll.autohidesScrollers = YES;
  [content addSubview:scroll];
  [scroll release];
  [self refresh];
  return self;
}

- (void)dealloc {
  [self close];
  [_search release];
  [_table release];
  [_panel release];
  [_entries release];
  [_filtered release];
  [_parent release];
  [super dealloc];
}

- (void)refresh {
  NSString *query = _search == nil ? @"" : _search.stringValue;
  [_filtered removeAllObjects];
  for (NSDictionary *entry in _entries) {
    NSString *title = [entry objectForKey:@"title"];
    NSString *description = [entry objectForKey:@"description"];
    if (query.length == 0 || [title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [description rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
      [_filtered addObject:entry];
    }
  }
  [_table reloadData];
  if (_filtered.count > 0) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}

- (void)show {
  [self refresh];
  if (_parent != nil) [_parent addChildWindow:_panel ordered:NSWindowAbove];
  [_panel center];
  [_panel makeKeyAndOrderFront:nil];
  [_panel makeFirstResponder:_search];
}

- (void)close {
  if (_parent != nil && _panel != nil && _panel.parentWindow == _parent) [_parent removeChildWindow:_panel];
  [_panel orderOut:nil];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)_filtered.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  (void)column;
  NSTableCellView *cell = [tableView makeViewWithIdentifier:@"kiwi-command-palette-cell" owner:self];
  NSTextField *description = nil;
  if (cell == nil) {
    cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 470.0, 42.0)] autorelease];
    cell.identifier = @"kiwi-command-palette-cell";
    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(8.0, 20.0, 454.0, 18.0)];
    title.editable = NO;
    title.bezeled = NO;
    title.drawsBackground = NO;
    title.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    cell.textField = title;
    [cell addSubview:title];
    [title release];
    description = [[NSTextField alloc] initWithFrame:NSMakeRect(8.0, 3.0, 454.0, 16.0)];
    description.tag = 9001;
    description.editable = NO;
    description.bezeled = NO;
    description.drawsBackground = NO;
    description.textColor = NSColor.secondaryLabelColor;
    description.font = [NSFont systemFontOfSize:11.0];
    [cell addSubview:description];
    [description release];
  } else {
    for (NSView *view in cell.subviews) {
      if (view.tag == 9001) {
        description = (NSTextField *)view;
        break;
      }
    }
  }
  NSDictionary *entry = [_filtered objectAtIndex:(NSUInteger)row];
  cell.textField.stringValue = [entry objectForKey:@"title"];
  description.stringValue = [entry objectForKey:@"description"];
  return cell;
}

- (void)searchChanged:(id)sender {
  (void)sender;
  [self refresh];
}

- (void)invokeSelection:(id)sender {
  (void)sender;
  NSInteger row = _table.selectedRow;
  if (row < 0 || row >= (NSInteger)_filtered.count || _invoked) return;
  _invoked = YES;
  NSDictionary *entry = [_filtered objectAtIndex:(NSUInteger)row];
  if (callback != NULL) callback(userdata, [[entry objectForKey:@"action"] unsignedIntValue]);
  [self close];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
  (void)control;
  (void)textView;
  if (command == @selector(insertNewline:)) {
    [self invokeSelection:nil];
    return YES;
  }
  if (command == @selector(cancelOperation:)) {
    [self close];
    return YES;
  }
  return NO;
}
@end

static NSValue *kiwi_cocoa_progress_window_key(GLFWwindow *window) {
  NSWindow *native_window = kiwi_cocoa_native_window(window);
  return native_window == nil ? nil : [NSValue valueWithPointer:native_window];
}

static KiwiCocoaProgressRegistration *kiwi_cocoa_progress_registration(GLFWwindow *window) {
  NSValue *key = kiwi_cocoa_progress_window_key(window);
  return key == nil ? nil : [kiwi_cocoa_progress_registrations objectForKey:key];
}

static const char *kiwi_cocoa_progress_tooltip(uint32_t state) {
  switch (state) {
    case 1: return "Terminal task progress";
    case 2: return "Terminal task failed";
    case 3: return "Terminal task in progress";
    case 4: return "Terminal task paused";
    default: return "";
  }
}

static void kiwi_cocoa_progress_remove(GLFWwindow *window) {
  NSValue *key = kiwi_cocoa_progress_window_key(window);
  KiwiCocoaProgressRegistration *registration = key == nil ? nil : [kiwi_cocoa_progress_registrations objectForKey:key];
  NSWindow *native_window = kiwi_cocoa_native_window(window);
  if (registration != nil && native_window != nil) {
    NSUInteger index = [native_window.titlebarAccessoryViewControllers indexOfObjectIdenticalTo:registration->controller];
    if (index != NSNotFound) [native_window removeTitlebarAccessoryViewControllerAtIndex:index];
  }
  if (key != nil && kiwi_cocoa_progress_registrations != nil) [kiwi_cocoa_progress_registrations removeObjectForKey:key];
}

static KiwiCocoaProgressRegistration *kiwi_cocoa_progress_install(GLFWwindow *window) {
  KiwiCocoaProgressRegistration *existing = kiwi_cocoa_progress_registration(window);
  if (existing != nil) return existing;
  NSWindow *native_window = kiwi_cocoa_native_window(window);
  NSValue *key = kiwi_cocoa_progress_window_key(window);
  if (native_window == nil || key == nil) {
    kiwi_surface_set_error("GLFW did not expose a Cocoa window for terminal progress");
    return nil;
  }
  if (kiwi_cocoa_progress_registrations == nil) kiwi_cocoa_progress_registrations = [[NSMutableDictionary alloc] init];
  NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 88.0, 16.0)];
  NSProgressIndicator *indicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0, 1.0, 88.0, 14.0)];
  [indicator setControlSize:NSControlSizeSmall];
  [indicator setIndeterminate:NO];
  [indicator setMinValue:0.0];
  [indicator setMaxValue:100.0];
  [container addSubview:indicator];
  NSTitlebarAccessoryViewController *controller = [[NSTitlebarAccessoryViewController alloc] init];
  controller.view = container;
  controller.layoutAttribute = NSLayoutAttributeRight;
  [native_window addTitlebarAccessoryViewController:controller];
  KiwiCocoaProgressRegistration *registration = [[KiwiCocoaProgressRegistration alloc] init];
  registration->controller = controller;
  registration->indicator = indicator;
  [kiwi_cocoa_progress_registrations setObject:registration forKey:key];
  [registration release];
  [controller release];
  [indicator release];
  [container release];
  return kiwi_cocoa_progress_registration(window);
}

int kiwi_cocoa_progress_set(GLFWwindow *window, uint32_t progress, uint32_t state) {
  @autoreleasepool {
    if (![NSThread isMainThread] || window == NULL || progress > 100 || state > 4) {
      kiwi_surface_set_error("Cocoa terminal progress needs a main-thread window, state 0 through 4, and progress 0 through 100");
      return 0;
    }
    if (state == 0) {
      kiwi_cocoa_progress_remove(window);
      return 1;
    }
    KiwiCocoaProgressRegistration *registration = kiwi_cocoa_progress_install(window);
    if (registration == nil) return 0;
    NSProgressIndicator *indicator = registration->indicator;
    BOOL indeterminate = state == 3;
    [indicator setIndeterminate:indeterminate];
    if (indeterminate) {
      [indicator startAnimation:nil];
    } else {
      [indicator stopAnimation:nil];
      [indicator setDoubleValue:(double)progress];
    }
    NSString *tooltip = [NSString stringWithUTF8String:kiwi_cocoa_progress_tooltip(state)];
    if (!indeterminate) tooltip = [tooltip stringByAppendingFormat:@" (%u%%)", progress];
    [indicator setToolTip:tooltip];
    return 1;
  }
}

int kiwi_cocoa_progress_round_trip(GLFWwindow *window) {
  @autoreleasepool {
    if (!kiwi_cocoa_progress_set(window, 73, 1)) return 0;
    KiwiCocoaProgressRegistration *registration = kiwi_cocoa_progress_registration(window);
    if (registration == nil || registration->indicator == nil || registration->indicator.isIndeterminate ||
        registration->indicator.doubleValue != 73.0) {
      kiwi_surface_set_error("Cocoa terminal progress did not retain a determinate titlebar value");
      return 0;
    }
    if (!kiwi_cocoa_progress_set(window, 73, 2) || registration->indicator.isIndeterminate ||
        registration->indicator.doubleValue != 73.0 || ![registration->indicator.toolTip isEqualToString:@"Terminal task failed (73%)"]) {
      kiwi_surface_set_error("Cocoa terminal progress did not retain an error titlebar state");
      return 0;
    }
    if (!kiwi_cocoa_progress_set(window, 0, 3)) return 0;
    registration = kiwi_cocoa_progress_registration(window);
    if (registration == nil || registration->indicator == nil || !registration->indicator.isIndeterminate) {
      kiwi_surface_set_error("Cocoa terminal progress did not retain an indeterminate titlebar state");
      return 0;
    }
    if (!kiwi_cocoa_progress_set(window, 73, 4) || registration->indicator.isIndeterminate ||
        registration->indicator.doubleValue != 73.0 || ![registration->indicator.toolTip isEqualToString:@"Terminal task paused (73%)"]) {
      kiwi_surface_set_error("Cocoa terminal progress did not retain a paused titlebar state");
      return 0;
    }
    if (!kiwi_cocoa_progress_set(window, 0, 0) || kiwi_cocoa_progress_registration(window) != nil) {
      kiwi_surface_set_error("Cocoa terminal progress did not clear its titlebar accessory");
      return 0;
    }
    return 1;
  }
}

static KiwiCocoaMenuRegistration *kiwi_cocoa_menu_registration(GLFWwindow *window) {
  NSValue *key = kiwi_cocoa_menu_window_key(window);
  return key == nil ? nil : [kiwi_cocoa_menu_registrations objectForKey:key];
}

static KiwiCocoaMenuRegistration *kiwi_cocoa_menu_registration_for_window(NSWindow *window) {
  return window == nil ? nil : [kiwi_cocoa_menu_registrations objectForKey:[NSValue valueWithPointer:window]];
}

static KiwiCocoaAutomationRegistration *kiwi_cocoa_automation_registration(GLFWwindow *window) {
  NSValue *key = kiwi_cocoa_menu_window_key(window);
  return key == nil ? nil : [kiwi_cocoa_automation_registrations objectForKey:key];
}

static KiwiCocoaAutomationRegistration *kiwi_cocoa_automation_registration_for_window(NSWindow *window) {
  return window == nil ? nil : [kiwi_cocoa_automation_registrations objectForKey:[NSValue valueWithPointer:window]];
}

static uint32_t kiwi_cocoa_toolbar_action(NSString *identifier) {
  if ([identifier isEqualToString:KIWI_COCOA_TOOLBAR_NEW_TAB]) return KIWI_COCOA_MENU_NEW_TAB;
  if ([identifier isEqualToString:KIWI_COCOA_TOOLBAR_SPLIT_RIGHT]) return KIWI_COCOA_MENU_SPLIT_RIGHT;
  if ([identifier isEqualToString:KIWI_COCOA_TOOLBAR_SPLIT_DOWN]) return KIWI_COCOA_MENU_SPLIT_DOWN;
  if ([identifier isEqualToString:KIWI_COCOA_TOOLBAR_COMMAND_PALETTE]) return KIWI_COCOA_MENU_COMMAND_PALETTE;
  if ([identifier isEqualToString:KIWI_COCOA_TOOLBAR_SETTINGS]) return KIWI_COCOA_MENU_OPEN_CONFIGURATION;
  return 0;
}

static NSString *kiwi_cocoa_toolbar_label(uint32_t action) {
  switch (action) {
    case KIWI_COCOA_MENU_NEW_TAB: return @"New Tab";
    case KIWI_COCOA_MENU_SPLIT_RIGHT: return @"Split Right";
    case KIWI_COCOA_MENU_SPLIT_DOWN: return @"Split Down";
    case KIWI_COCOA_MENU_COMMAND_PALETTE: return @"Commands";
    case KIWI_COCOA_MENU_OPEN_CONFIGURATION: return @"Settings";
    default: return nil;
  }
}

@implementation KiwiCocoaMenuDispatcher
- (void)windowDidBecomeKey:(NSNotification *)notification {
  KiwiCocoaMenuRegistration *registration = kiwi_cocoa_menu_registration_for_window(notification.object);
  if (registration != nil) kiwi_cocoa_active_menu_registration = registration;
}

- (void)invokeAction:(id)sender {
  if (sender == nil || ![sender respondsToSelector:@selector(tag)]) return;
  NSInteger tag = [sender tag];
  if (tag <= 0 || tag > UINT32_MAX) return;
  uint32_t action = (uint32_t)tag;
  if (!kiwi_cocoa_menu_action_is_valid(action)) return;
  NSWindow *key_window = NSApp.keyWindow ?: NSApp.mainWindow;
  KiwiCocoaMenuRegistration *registration = kiwi_cocoa_menu_registration_for_window(key_window);
  if (registration == nil) registration = kiwi_cocoa_active_menu_registration;
  if (registration != nil && registration->callback != NULL) {
    registration->callback(registration->userdata, action);
  }
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
  (void)toolbar;
  return @[
      KIWI_COCOA_TOOLBAR_NEW_TAB,
      KIWI_COCOA_TOOLBAR_SPLIT_RIGHT,
      KIWI_COCOA_TOOLBAR_SPLIT_DOWN,
      KIWI_COCOA_TOOLBAR_COMMAND_PALETTE,
      KIWI_COCOA_TOOLBAR_SETTINGS,
      NSToolbarFlexibleSpaceItemIdentifier,
  ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
  (void)toolbar;
  return @[
      KIWI_COCOA_TOOLBAR_NEW_TAB,
      KIWI_COCOA_TOOLBAR_SPLIT_RIGHT,
      KIWI_COCOA_TOOLBAR_SPLIT_DOWN,
      NSToolbarFlexibleSpaceItemIdentifier,
      KIWI_COCOA_TOOLBAR_COMMAND_PALETTE,
      KIWI_COCOA_TOOLBAR_SETTINGS,
  ];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
willBeInsertedIntoToolbar:(BOOL)willBeInserted {
  (void)toolbar;
  (void)willBeInserted;
  uint32_t action = kiwi_cocoa_toolbar_action(identifier);
  NSString *label = kiwi_cocoa_toolbar_label(action);
  if (label == nil) return nil;
  NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
  item.label = label;
  item.paletteLabel = label;
  item.toolTip = label;
  item.tag = (NSInteger)action;
  item.target = self;
  item.action = @selector(invokeAction:);
  return item;
}
@end

@implementation KiwiCocoaAutomationDispatcher
- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
  if (event == nil || reply == nil || event.eventClass != KIWI_COCOA_AUTOMATION_CLASS) return;
  uint32_t action = kiwi_cocoa_automation_action_for_event(event.eventID);
  NSWindow *key_window = NSApp.keyWindow ?: NSApp.mainWindow;
  KiwiCocoaAutomationRegistration *registration = kiwi_cocoa_automation_registration_for_window(key_window);
  if (registration == nil) registration = kiwi_cocoa_active_automation_registration;
  BOOL accepted = action != 0 && registration != nil && registration->callback != NULL && registration->callback(registration->userdata, action) != 0;
  [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithBoolean:accepted] forKeyword:keyDirectObject];
  if (!accepted) {
    [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithInt32:errAEEventFailed] forKeyword:keyErrorNumber];
    [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"Kiwi could not perform the requested automation action."] forKeyword:keyErrorString];
  }
}
@end

static void kiwi_cocoa_install_automation(void) {
  if (kiwi_cocoa_automation_dispatcher != nil) return;
  static const uint32_t event_identifiers[] = {
      KIWI_COCOA_AUTOMATION_NEW_WINDOW,
      KIWI_COCOA_AUTOMATION_NEW_TAB,
      KIWI_COCOA_AUTOMATION_NEXT_TAB,
      KIWI_COCOA_AUTOMATION_CLOSE_PANE,
      KIWI_COCOA_AUTOMATION_SPLIT_RIGHT,
      KIWI_COCOA_AUTOMATION_SPLIT_DOWN,
      KIWI_COCOA_AUTOMATION_RELOAD_CONFIGURATION,
      KIWI_COCOA_AUTOMATION_OPEN_CONFIGURATION,
  };
  kiwi_cocoa_automation_registrations = [[NSMutableDictionary alloc] init];
  kiwi_cocoa_automation_dispatcher = [[KiwiCocoaAutomationDispatcher alloc] init];
  NSAppleEventManager *manager = [NSAppleEventManager sharedAppleEventManager];
  for (size_t index = 0; index < sizeof(event_identifiers) / sizeof(event_identifiers[0]); index += 1) {
    [manager setEventHandler:kiwi_cocoa_automation_dispatcher
                 andSelector:@selector(handleAppleEvent:withReplyEvent:)
               forEventClass:KIWI_COCOA_AUTOMATION_CLASS andEventID:event_identifiers[index]];
  }
}

int kiwi_cocoa_automation_install(GLFWwindow *window, KiwiCocoaAutomationCallback callback, void *userdata) {
  @autoreleasepool {
    if (![NSThread isMainThread] || window == NULL || callback == NULL) {
      kiwi_surface_set_error("Cocoa automation installation needs a main-thread window and callback");
      return 0;
    }
    NSValue *key = kiwi_cocoa_menu_window_key(window);
    if (key == nil) {
      kiwi_surface_set_error("GLFW did not expose a Cocoa window for automation");
      return 0;
    }
    kiwi_cocoa_install_automation();
    KiwiCocoaAutomationRegistration *registration = [[KiwiCocoaAutomationRegistration alloc] init];
    registration->callback = callback;
    registration->userdata = userdata;
    [kiwi_cocoa_automation_registrations setObject:registration forKey:key];
    if (NSApp.keyWindow == glfwGetCocoaWindow(window) || kiwi_cocoa_active_automation_registration == nil) {
      kiwi_cocoa_active_automation_registration = registration;
    }
    [registration release];
    return 1;
  }
}

void kiwi_cocoa_automation_remove(GLFWwindow *window) {
  @autoreleasepool {
    NSValue *key = kiwi_cocoa_menu_window_key(window);
    KiwiCocoaAutomationRegistration *registration = key == nil ? nil : [kiwi_cocoa_automation_registrations objectForKey:key];
    if (registration == kiwi_cocoa_active_automation_registration) kiwi_cocoa_active_automation_registration = nil;
    if (key != nil && kiwi_cocoa_automation_registrations != nil) [kiwi_cocoa_automation_registrations removeObjectForKey:key];
  }
}

int kiwi_cocoa_automation_invoke_smoke(GLFWwindow *window, uint32_t action) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_surface_set_error("Cocoa automation smoke needs the main thread");
      return 0;
    }
    uint32_t event_identifier = kiwi_cocoa_automation_event_for_action(action);
    KiwiCocoaAutomationRegistration *registration = kiwi_cocoa_automation_registration(window);
    if (event_identifier == 0 || registration == nil || registration->callback == NULL || kiwi_cocoa_automation_dispatcher == nil) {
      kiwi_surface_set_error("Cocoa automation smoke needs an installed bounded action callback");
      return 0;
    }
    kiwi_cocoa_active_automation_registration = registration;
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:KIWI_COCOA_AUTOMATION_CLASS
                                                                              eventID:event_identifier
                                                                     targetDescriptor:nil
                                                                             returnID:kAutoGenerateReturnID
                                                                        transactionID:kAnyTransactionID];
    NSAppleEventDescriptor *reply = [NSAppleEventDescriptor recordDescriptor];
    [kiwi_cocoa_automation_dispatcher handleAppleEvent:event withReplyEvent:reply];
    NSAppleEventDescriptor *result = [reply paramDescriptorForKeyword:keyDirectObject];
    if (result != nil && result.booleanValue) return 1;
    kiwi_surface_set_error("Cocoa automation smoke action was rejected by the live controller");
    return 0;
  }
}

static NSMenuItem *kiwi_cocoa_menu_item(NSString *title, uint32_t action) {
  NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title action:@selector(invokeAction:)
                                            keyEquivalent:@""] autorelease];
  item.target = kiwi_cocoa_menu_dispatcher;
  item.tag = (NSInteger)action;
  return item;
}

static void kiwi_cocoa_install_window_toolbar(NSWindow *window) {
  if (window == nil || kiwi_cocoa_menu_dispatcher == nil) return;
  NSToolbar *existing = window.toolbar;
  if ([existing.identifier isEqualToString:KIWI_COCOA_TOOLBAR_IDENTIFIER]) return;
  NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:KIWI_COCOA_TOOLBAR_IDENTIFIER];
  toolbar.delegate = kiwi_cocoa_menu_dispatcher;
  toolbar.allowsUserCustomization = NO;
  toolbar.autosavesConfiguration = NO;
  toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
  window.toolbar = toolbar;
  if ([window respondsToSelector:@selector(setToolbarStyle:)]) {
    window.toolbarStyle = NSWindowToolbarStyleUnified;
  }
  [toolbar release];
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
  [file_menu addItem:kiwi_cocoa_menu_item(@"Command Palette…", KIWI_COCOA_MENU_COMMAND_PALETTE)];
  [file_menu addItem:[NSMenuItem separatorItem]];
  [file_menu addItem:kiwi_cocoa_menu_item(@"Settings…", KIWI_COCOA_MENU_OPEN_CONFIGURATION)];
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
    kiwi_cocoa_install_window_toolbar(glfwGetCocoaWindow(window));
    if (NSApp.keyWindow == glfwGetCocoaWindow(window) || kiwi_cocoa_active_menu_registration == nil) {
      kiwi_cocoa_active_menu_registration = registration;
    }
    [registration release];
    return 1;
  }
}

int kiwi_cocoa_toolbar_invoke_smoke(GLFWwindow *window, uint32_t action) {
  @autoreleasepool {
    if (![NSThread isMainThread] || !kiwi_cocoa_menu_action_is_valid(action)) {
      kiwi_surface_set_error("Cocoa toolbar smoke received an invalid action");
      return 0;
    }
    KiwiCocoaMenuRegistration *registration = kiwi_cocoa_menu_registration(window);
    NSWindow *native_window = kiwi_cocoa_native_window(window);
    NSToolbarItem *item = nil;
    for (NSToolbarItem *candidate in native_window.toolbar.items) {
      if ((uint32_t)candidate.tag == action) {
        item = candidate;
        break;
      }
    }
    if (registration == nil || registration->callback == NULL || item == nil ||
        native_window.toolbar.delegate != kiwi_cocoa_menu_dispatcher) {
      kiwi_surface_set_error("Cocoa toolbar smoke needs an installed native toolbar action");
      return 0;
    }
    kiwi_cocoa_active_menu_registration = registration;
    [kiwi_cocoa_menu_dispatcher invokeAction:item];
    return 1;
  }
}

static BOOL kiwi_cocoa_is_local_file_url(NSURL *url) {
  if (url == nil || !url.isFileURL || ![url.path hasPrefix:@"/"]) return NO;
  NSString *host = url.host;
  if (host == nil || host.length == 0 || [host caseInsensitiveCompare:@"localhost"] == NSOrderedSame) return YES;
  NSString *local_host = NSProcessInfo.processInfo.hostName;
  if ([host caseInsensitiveCompare:local_host] == NSOrderedSame) return YES;
  NSString *local_short_host = [local_host componentsSeparatedByString:@"."].firstObject;
  return local_short_host.length > 0 && [host caseInsensitiveCompare:local_short_host] == NSOrderedSame;
}

int kiwi_cocoa_window_set_represented_directory(GLFWwindow *window, const char *uri) {
  @autoreleasepool {
    NSWindow *native_window = kiwi_cocoa_native_window(window);
    if (![NSThread isMainThread] || native_window == nil) {
      kiwi_surface_set_error("Cocoa proxy URL needs a main-thread window");
      return 0;
    }
    if (uri == NULL || uri[0] == '\0') {
      native_window.representedURL = nil;
      return 1;
    }
    if (strlen(uri) > 2048) {
      kiwi_surface_set_error("Cocoa proxy URL exceeds the bounded OSC 7 directory length");
      return 0;
    }
    NSString *value = [NSString stringWithUTF8String:uri];
    NSURL *url = value == nil ? nil : [NSURL URLWithString:value];
    if (url == nil || !url.isFileURL || ![url.path hasPrefix:@"/"]) {
      kiwi_surface_set_error("Cocoa proxy URL needs an absolute file URI");
      return 0;
    }
    // An OSC 7 remote host is metadata, not a path available to Finder.
    native_window.representedURL = kiwi_cocoa_is_local_file_url(url) ? url : nil;
    return 1;
  }
}

int kiwi_cocoa_window_directory_round_trip(GLFWwindow *window) {
  @autoreleasepool {
    NSWindow *native_window = kiwi_cocoa_native_window(window);
    if (!kiwi_cocoa_window_set_represented_directory(window, "file://localhost/private/tmp/kiwi-cocoa-smoke") ||
        native_window == nil || native_window.representedURL == nil ||
        ![native_window.representedURL.path isEqualToString:@"/private/tmp/kiwi-cocoa-smoke"]) {
      if (native_window != nil && native_window.representedURL != nil) {
        kiwi_surface_set_error("Cocoa proxy URL smoke did not retain the local directory path");
      }
      return 0;
    }
    if (!kiwi_cocoa_window_set_represented_directory(window, "file://remote.example/private/tmp/kiwi-cocoa-smoke") ||
        native_window.representedURL != nil) {
      if (native_window.representedURL != nil) {
        kiwi_surface_set_error("Cocoa proxy URL smoke exposed a remote directory as local");
      }
      return 0;
    }
    return 1;
  }
}

int kiwi_cocoa_window_represented_directory_matches(GLFWwindow *window, const char *path) {
  @autoreleasepool {
    NSWindow *native_window = kiwi_cocoa_native_window(window);
    if (![NSThread isMainThread] || native_window == nil) {
      kiwi_surface_set_error("Cocoa proxy URL inspection needs a main-thread window");
      return 0;
    }
    if (path == NULL) return native_window.representedURL == nil;
    NSString *expected_path = [NSString stringWithUTF8String:path];
    if (expected_path == nil || ![expected_path hasPrefix:@"/"]) {
      kiwi_surface_set_error("Cocoa proxy URL inspection needs an absolute path");
      return 0;
    }
    return native_window.representedURL != nil && [native_window.representedURL.path isEqualToString:expected_path];
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

int kiwi_cocoa_command_palette_show(GLFWwindow *window,
                                    const KiwiCocoaCommandPaletteEntry *entries,
                                    size_t count, KiwiCocoaMenuCallback callback,
                                    void *userdata) {
  @autoreleasepool {
    NSWindow *native_window = kiwi_cocoa_native_window(window);
    NSValue *key = kiwi_cocoa_menu_window_key(window);
    if (![NSThread isMainThread] || native_window == nil || key == nil || entries == NULL ||
        callback == NULL || count == 0 || count > 32) {
      kiwi_surface_set_error("Cocoa command palette needs a main-thread window, callback, and one through 32 entries");
      return 0;
    }
    for (size_t index = 0; index < count; index += 1) {
      if (!kiwi_cocoa_menu_action_is_valid(entries[index].action) ||
          entries[index].action == KIWI_COCOA_MENU_COMMAND_PALETTE ||
          entries[index].title == NULL || entries[index].description == NULL ||
          entries[index].title[0] == '\0' || strlen(entries[index].title) > 128 ||
          strlen(entries[index].description) > 256) {
        kiwi_surface_set_error("Cocoa command palette received an invalid bounded entry");
        return 0;
      }
    }
    if (kiwi_cocoa_command_palette_registrations == nil) {
      kiwi_cocoa_command_palette_registrations = [[NSMutableDictionary alloc] init];
    }
    KiwiCocoaCommandPalette *existing = [kiwi_cocoa_command_palette_registrations objectForKey:key];
    if (existing != nil) {
      [existing close];
      [kiwi_cocoa_command_palette_registrations removeObjectForKey:key];
    }
    KiwiCocoaCommandPalette *palette = [[KiwiCocoaCommandPalette alloc] initWithWindow:native_window entries:entries count:count];
    if (palette == nil) {
      kiwi_surface_set_error("Cocoa command palette could not copy valid UTF-8 entries");
      return 0;
    }
    palette->callback = callback;
    palette->userdata = userdata;
    [kiwi_cocoa_command_palette_registrations setObject:palette forKey:key];
    [palette show];
    [palette release];
    return 1;
  }
}

void kiwi_cocoa_command_palette_remove(GLFWwindow *window) {
  @autoreleasepool {
    NSValue *key = kiwi_cocoa_menu_window_key(window);
    KiwiCocoaCommandPalette *palette = key == nil ? nil : [kiwi_cocoa_command_palette_registrations objectForKey:key];
    if (palette != nil) [palette close];
    if (key != nil && kiwi_cocoa_command_palette_registrations != nil) {
      [kiwi_cocoa_command_palette_registrations removeObjectForKey:key];
    }
  }
}

int kiwi_cocoa_command_palette_invoke_smoke(GLFWwindow *window) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_surface_set_error("Cocoa command palette smoke needs the main thread");
      return 0;
    }
    NSValue *key = kiwi_cocoa_menu_window_key(window);
    KiwiCocoaCommandPalette *palette = key == nil ? nil : [kiwi_cocoa_command_palette_registrations objectForKey:key];
    if (palette == nil || !palette->_panel.isVisible || palette->_filtered.count == 0) {
      kiwi_surface_set_error("Cocoa command palette smoke needs a visible palette with an entry");
      return 0;
    }
    [palette invokeSelection:nil];
    return 1;
  }
}

void kiwi_cocoa_progress_remove_bridge(GLFWwindow *window) {
  @autoreleasepool {
    kiwi_cocoa_progress_remove(window);
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

static void kiwi_cocoa_configure_window_tabs(NSWindow *window) {
  if (window == nil) return;
  if (kiwi_cocoa_window_is_registered_standalone(window)) return;
  window.tabbingIdentifier = @"io.github.gongahkia.kiwi";
  window.tabbingMode = NSWindowTabbingModePreferred;
  if (kiwi_cocoa_tab_group_leader == nil) {
    kiwi_cocoa_tab_group_leader = window;
    return;
  }
  if (kiwi_cocoa_tab_group_leader == window) return;
  if (![kiwi_cocoa_tab_group_leader.tabbedWindows containsObject:window]) {
    [kiwi_cocoa_tab_group_leader addTabbedWindow:window ordered:NSWindowAbove];
  }
}

int kiwi_cocoa_window_set_tab_grouping(GLFWwindow *window, int grouped) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_surface_set_error("Cocoa window-tab configuration needs the main thread");
      return 0;
    }
    NSWindow *native_window = kiwi_cocoa_native_window(window);
    if (native_window == nil) {
      kiwi_surface_set_error("Cocoa window-tab configuration needs a native window");
      return 0;
    }
    if (grouped != 0) {
      kiwi_cocoa_set_window_standalone(native_window, NO);
      native_window.tabbingMode = NSWindowTabbingModePreferred;
      kiwi_cocoa_configure_window_tabs(native_window);
    } else {
      if (!kiwi_cocoa_set_window_standalone(native_window, YES)) {
        kiwi_surface_set_error("Cocoa standalone-window registry allocation failed");
        return 0;
      }
    }
    return 1;
  }
}

int kiwi_cocoa_window_tabs_round_trip(GLFWwindow *first, GLFWwindow *second) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_surface_set_error("Cocoa window-tab smoke needs the main thread");
      return 0;
    }
    NSWindow *first_window = kiwi_cocoa_native_window(first);
    NSWindow *second_window = kiwi_cocoa_native_window(second);
    if (first_window == nil || second_window == nil || first_window == second_window ||
        ![first_window.tabbingIdentifier isEqualToString:@"io.github.gongahkia.kiwi"] ||
        ![second_window.tabbingIdentifier isEqualToString:@"io.github.gongahkia.kiwi"] ||
        ![first_window.tabbedWindows containsObject:second_window]) {
      kiwi_surface_set_error("Cocoa native windows did not join Kiwi's tab group");
      return 0;
    }
    return 1;
  }
}

int kiwi_cocoa_window_is_standalone(GLFWwindow *window) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_surface_set_error("Cocoa standalone-window inspection needs the main thread");
      return 0;
    }
    NSWindow *native_window = kiwi_cocoa_native_window(window);
    if (native_window == nil || !kiwi_cocoa_window_is_registered_standalone(native_window) ||
        native_window.tabbingMode != NSWindowTabbingModeDisallowed ||
        native_window.tabbedWindows.count > 1) {
      kiwi_surface_set_error("Cocoa window was not configured as a standalone window");
      return 0;
    }
    return 1;
  }
}

int kiwi_cocoa_window_select_next_tab(GLFWwindow *window) {
  @autoreleasepool {
    if (![NSThread isMainThread]) {
      kiwi_surface_set_error("Cocoa native-tab selection needs the main thread");
      return 0;
    }
    NSWindow *native_window = kiwi_cocoa_native_window(window);
    if (native_window == nil || native_window.tabbedWindows.count < 2) {
      kiwi_surface_set_error("Cocoa native-tab selection needs at least two Kiwi windows");
      return 0;
    }
    [native_window selectNextTab:nil];
    return 1;
  }
}

void kiwi_cocoa_window_tabs_remove_bridge(GLFWwindow *window) {
  @autoreleasepool {
    NSWindow *native_window = kiwi_cocoa_native_window(window);
    kiwi_cocoa_set_window_standalone(native_window, NO);
    if (native_window == kiwi_cocoa_tab_group_leader) {
      kiwi_cocoa_tab_group_leader = nil;
      for (NSWindow *candidate in native_window.tabbedWindows) {
        if (candidate != native_window) {
          kiwi_cocoa_tab_group_leader = candidate;
          break;
        }
      }
    }
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
    kiwi_cocoa_configure_window_tabs(view.window);

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
