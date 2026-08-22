#ifndef KIWI_VT_H
#define KIWI_VT_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(KIWI_VT_BUILD)
#define KIWI_VT_API __declspec(dllexport)
#else
#define KIWI_VT_API __declspec(dllimport)
#endif
#else
#define KIWI_VT_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define KIWI_VT_API_VERSION 1u

typedef struct kiwi_vt_terminal kiwi_vt_terminal;
typedef struct kiwi_vt_render_update kiwi_vt_render_update;
typedef struct kiwi_vt_mouse kiwi_vt_mouse;

typedef enum kiwi_vt_status {
  KIWI_VT_OK = 0,
  KIWI_VT_INVALID_ARGUMENT = 1,
  KIWI_VT_UNSUPPORTED_VERSION = 2,
  KIWI_VT_OUT_OF_MEMORY = 3,
  KIWI_VT_LUA_UNAVAILABLE = 4,
  KIWI_VT_LUA_ERROR = 5,
  KIWI_VT_BUFFER_TOO_SMALL = 6,
  KIWI_VT_NOT_FOUND = 7
} kiwi_vt_status;

typedef struct kiwi_vt_options {
  uint32_t struct_size;
  uint32_t api_version;
  uint32_t columns;
  uint32_t rows;
  uint32_t scrollback_limit;
  /* Zero preserves the portable 1/2/8/16 Kitty subset. A host that can
   * supply layout, shifted-layout, and PC-101 key variants may opt in to a
   * mask through bit 4; values must be from 0 through 31. */
  uint32_t keyboard_supported_flags;
} kiwi_vt_options;

/* A copied, renderer-neutral terminal summary. `struct_size` must be set by
 * the caller before kiwi_vt_render_update_info. Colors use 0xAARRGGBB. */
typedef struct kiwi_vt_render_state {
  uint32_t struct_size;
  uint32_t columns;
  uint32_t rows;
  uint32_t active_screen;
  uint32_t cursor_column;
  uint32_t cursor_row;
  uint32_t cursor_visible;
  uint32_t cursor_pending_wrap;
  uint32_t damage_cells;
  uint32_t damage_full;
  uint64_t generation;
} kiwi_vt_render_state;

/* A copied logical-cell descriptor. `struct_size` must be set by the caller
 * before kiwi_vt_render_update_cell. `display_text` is returned through that
 * function's two-call buffer parameters. */
typedef struct kiwi_vt_render_cell {
  uint32_t struct_size;
  uint32_t column;
  uint32_t row;
  uint32_t anchor_column;
  uint32_t width;
  uint32_t flags;
  uint32_t foreground;
  uint32_t background;
  uint32_t continuation;
} kiwi_vt_render_cell;

typedef struct kiwi_vt_key_event {
  uint32_t struct_size;
  uint32_t key;
  uint32_t action;
  uint32_t modifiers;
  /* Optional Unicode scalar sequence associated with this physical key. It is
   * used only when the terminal negotiated Kitty flags 8 and 16. Callers
   * compiled against the original v1 prefix may omit these fields by setting
   * struct_size to that prefix size. */
  const uint32_t *associated_text;
  uint32_t associated_text_count;
  /* Optional non-control Unicode scalar key variants for Kitty flag 4.
   * `layout_key` is the unshifted current-layout key, `shifted_key` is the
   * current-layout Shift result, and `base_key` is the unshifted US PC-101
   * physical-position key. Set unavailable values to zero. A host must not
   * advertise flag 4 unless it can provide all three meanings. */
  uint32_t layout_key;
  uint32_t shifted_key;
  uint32_t base_key;
} kiwi_vt_key_event;

typedef struct kiwi_vt_input_result {
  uint32_t struct_size;
  uint32_t local_action;
  uint32_t suppress_text;
} kiwi_vt_input_result;

/* A detached copy of the terminal modes a host needs to make input policy
 * decisions. `struct_size` must be set before kiwi_vt_terminal_input_modes. */
typedef struct kiwi_vt_input_modes {
  uint32_t struct_size;
  uint32_t application_cursor;
  uint32_t bracketed_paste;
  uint32_t focus_reporting;
  uint32_t keyboard_flags;
  uint32_t mouse_protocol;
  uint32_t mouse_tracking;
  uint32_t alternate_screen;
  uint32_t alternate_scroll;
  uint32_t application_keypad;
  uint32_t backarrow;
} kiwi_vt_input_modes;

typedef struct kiwi_vt_effect {
  uint32_t struct_size;
  uint32_t kind;
} kiwi_vt_effect;

typedef struct kiwi_vt_mouse_button_event {
  uint32_t struct_size;
  uint32_t button;
  uint32_t action;
  uint32_t column;
  uint32_t row;
  uint32_t modifiers;
  /* Optional 1-origin physical coordinates used when the terminal negotiated
   * xterm SGR-Pixels (DECSET 1016). Set both fields to zero when unavailable.
   * Callers compiled against the original v1 prefix may omit these fields by
   * setting struct_size to that prefix size. */
  uint32_t pixel_x;
  uint32_t pixel_y;
} kiwi_vt_mouse_button_event;

typedef struct kiwi_vt_mouse_motion_event {
  uint32_t struct_size;
  uint32_t column;
  uint32_t row;
  uint32_t modifiers;
  uint32_t pixel_x;
  uint32_t pixel_y;
} kiwi_vt_mouse_motion_event;

typedef struct kiwi_vt_mouse_wheel_event {
  uint32_t struct_size;
  uint32_t column;
  uint32_t row;
  uint32_t modifiers;
  double delta;
  uint32_t pixel_x;
  uint32_t pixel_y;
  /* Optional horizontal scroll offset. Positive maps to xterm wheel button 6
   * (right) and negative to button 7 (left). Callers compiled against the
   * earlier v1 extension may omit it by using that smaller struct_size. */
  double horizontal_delta;
} kiwi_vt_mouse_wheel_event;

enum {
  KIWI_VT_SCREEN_PRIMARY = 0,
  KIWI_VT_SCREEN_ALTERNATE = 1,
};

enum {
  KIWI_VT_MOUSE_PROTOCOL_X10 = 0,
  KIWI_VT_MOUSE_PROTOCOL_UTF8 = 1,
  KIWI_VT_MOUSE_PROTOCOL_SGR = 2,
  KIWI_VT_MOUSE_PROTOCOL_URXVT = 3,
  KIWI_VT_MOUSE_PROTOCOL_SGR_PIXELS = 4,
};

enum {
  KIWI_VT_MOUSE_TRACKING_NONE = 0,
  KIWI_VT_MOUSE_TRACKING_X10 = 1,
  KIWI_VT_MOUSE_TRACKING_NORMAL = 2,
  KIWI_VT_MOUSE_TRACKING_BUTTON = 3,
  KIWI_VT_MOUSE_TRACKING_ANY = 4,
};

enum {
  KIWI_VT_EFFECT_WRITE_PTY = 1,
  KIWI_VT_EFFECT_BELL = 2,
  KIWI_VT_EFFECT_TITLE_CHANGED = 3,
  KIWI_VT_EFFECT_PWD_CHANGED = 4,
  KIWI_VT_EFFECT_SHELL_MARKER = 5,
  KIWI_VT_EFFECT_UNKNOWN_SEQUENCE = 6,
  KIWI_VT_EFFECT_PALETTE_CHANGED = 7,
  KIWI_VT_EFFECT_CURSOR_COLOR_CHANGED = 8,
  KIWI_VT_EFFECT_CLIPBOARD_WRITE_DENIED = 9,
  KIWI_VT_EFFECT_CLIPBOARD_WRITE_REQUESTED = 10,
  KIWI_VT_EFFECT_PROGRESS_CHANGED = 11,
  KIWI_VT_EFFECT_NOTIFICATION_REQUESTED = 12,
  KIWI_VT_EFFECT_OTHER = 255,
};

enum {
  KIWI_VT_MOUSE_ACTION_RELEASE = 0,
  KIWI_VT_MOUSE_ACTION_PRESS = 1,
};

enum {
  KIWI_VT_KEY_ACTION_RELEASE = 0,
  KIWI_VT_KEY_ACTION_PRESS = 1,
  KIWI_VT_KEY_ACTION_REPEAT = 2,
};

enum {
  KIWI_VT_MODIFIER_SHIFT = 0x0001u,
  KIWI_VT_MODIFIER_CONTROL = 0x0002u,
  KIWI_VT_MODIFIER_ALT = 0x0004u,
  KIWI_VT_MODIFIER_SUPER = 0x0008u,
};

enum {
  KIWI_VT_KEYBOARD_FLAG_DISAMBIGUATE = 0x0001u,
  KIWI_VT_KEYBOARD_FLAG_EVENT_TYPES = 0x0002u,
  KIWI_VT_KEYBOARD_FLAG_ALTERNATE_KEYS = 0x0004u,
  KIWI_VT_KEYBOARD_FLAG_ALL_KEYS = 0x0008u,
  KIWI_VT_KEYBOARD_FLAG_ASSOCIATED_TEXT = 0x0010u,
};

enum {
  KIWI_VT_KEY_ESCAPE = 256,
  KIWI_VT_KEY_ENTER = 257,
  KIWI_VT_KEY_TAB = 258,
  KIWI_VT_KEY_BACKSPACE = 259,
  KIWI_VT_KEY_INSERT = 260,
  KIWI_VT_KEY_DELETE = 261,
  KIWI_VT_KEY_RIGHT = 262,
  KIWI_VT_KEY_LEFT = 263,
  KIWI_VT_KEY_DOWN = 264,
  KIWI_VT_KEY_UP = 265,
  KIWI_VT_KEY_PAGE_UP = 266,
  KIWI_VT_KEY_PAGE_DOWN = 267,
  KIWI_VT_KEY_HOME = 268,
  KIWI_VT_KEY_END = 269,
  KIWI_VT_KEY_F1 = 290,
  KIWI_VT_KEY_F2 = 291,
  KIWI_VT_KEY_F3 = 292,
  KIWI_VT_KEY_F4 = 293,
  KIWI_VT_KEY_F5 = 294,
  KIWI_VT_KEY_F6 = 295,
  KIWI_VT_KEY_F7 = 296,
  KIWI_VT_KEY_F8 = 297,
  KIWI_VT_KEY_F9 = 298,
  KIWI_VT_KEY_F10 = 299,
  KIWI_VT_KEY_F11 = 300,
  KIWI_VT_KEY_F12 = 301,
  KIWI_VT_KEY_KP_0 = 320,
  KIWI_VT_KEY_KP_1 = 321,
  KIWI_VT_KEY_KP_2 = 322,
  KIWI_VT_KEY_KP_3 = 323,
  KIWI_VT_KEY_KP_4 = 324,
  KIWI_VT_KEY_KP_5 = 325,
  KIWI_VT_KEY_KP_6 = 326,
  KIWI_VT_KEY_KP_7 = 327,
  KIWI_VT_KEY_KP_8 = 328,
  KIWI_VT_KEY_KP_9 = 329,
  KIWI_VT_KEY_KP_DECIMAL = 330,
  KIWI_VT_KEY_KP_DIVIDE = 331,
  KIWI_VT_KEY_KP_MULTIPLY = 332,
  KIWI_VT_KEY_KP_SUBTRACT = 333,
  KIWI_VT_KEY_KP_ADD = 334,
  KIWI_VT_KEY_KP_ENTER = 335,
  KIWI_VT_KEY_KP_EQUAL = 336,
};

enum {
  KIWI_VT_LOCAL_ACTION_NONE = 0,
  KIWI_VT_LOCAL_ACTION_COPY = 1,
  KIWI_VT_LOCAL_ACTION_PASTE = 2,
  KIWI_VT_LOCAL_ACTION_SEARCH_BEGIN = 3,
  KIWI_VT_LOCAL_ACTION_SEARCH_NEXT = 4,
  KIWI_VT_LOCAL_ACTION_SEARCH_PREVIOUS = 5,
  KIWI_VT_LOCAL_ACTION_OPEN_HYPERLINK = 6,
  KIWI_VT_LOCAL_ACTION_SCROLL_UP = 7,
  KIWI_VT_LOCAL_ACTION_SCROLL_DOWN = 8,
  KIWI_VT_LOCAL_ACTION_REGION_PREVIOUS_PROMPT = 9,
  KIWI_VT_LOCAL_ACTION_REGION_PREVIOUS_COMMAND = 10,
  KIWI_VT_LOCAL_ACTION_REGION_PREVIOUS_OUTPUT = 11,
  KIWI_VT_LOCAL_ACTION_REGION_NEXT_PROMPT = 12,
  KIWI_VT_LOCAL_ACTION_REGION_NEXT_COMMAND = 13,
  KIWI_VT_LOCAL_ACTION_REGION_NEXT_OUTPUT = 14,
};

enum {
  KIWI_VT_CELL_FLAG_BOLD = 0x001u,
  KIWI_VT_CELL_FLAG_SEMANTIC = 0x002u,
  KIWI_VT_CELL_FLAG_RECENT = 0x004u,
  KIWI_VT_CELL_FLAG_FAINT = 0x008u,
  KIWI_VT_CELL_FLAG_ITALIC = 0x010u,
  KIWI_VT_CELL_FLAG_UNDERLINE = 0x020u,
  KIWI_VT_CELL_FLAG_INVERSE = 0x040u,
  KIWI_VT_CELL_FLAG_CONCEALED = 0x080u,
  KIWI_VT_CELL_FLAG_STRIKE = 0x100u,
  KIWI_VT_CELL_FLAG_HYPERLINK = 0x200u,
  KIWI_VT_CELL_FLAG_PROTECTED = 0x400u,
};

KIWI_VT_API uint32_t kiwi_vt_api_version(void);
KIWI_VT_API const char *kiwi_vt_version(void);
/* Borrowed thread-local diagnostic for failures that occur before a terminal
 * handle exists, such as kiwi_vt_terminal_new. */
KIWI_VT_API const char *kiwi_vt_last_error(void);

KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_new(const kiwi_vt_options *options, kiwi_vt_terminal **terminal);
KIWI_VT_API void kiwi_vt_terminal_free(kiwi_vt_terminal *terminal);

KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_write(kiwi_vt_terminal *terminal, const void *bytes, size_t byte_count, size_t *consumed);
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_finish(kiwi_vt_terminal *terminal);
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_resize(kiwi_vt_terminal *terminal, uint32_t columns, uint32_t rows);
/* Set physical cell metrics for read-only xterm geometry queries. The host
 * owns measurement and window geometry; this function accepts no resize or
 * position request from terminal applications. */
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_set_cell_metrics(kiwi_vt_terminal *terminal, uint32_t width, uint32_t height);
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_input_modes(kiwi_vt_terminal *terminal, kiwi_vt_input_modes *modes);

/* `required` includes the terminating NUL. Supplying a NULL buffer performs a
 * size query and returns KIWI_VT_BUFFER_TOO_SMALL when a value is available.
 * The handle is single-threaded: concurrent calls on it are unsupported. */
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_text(kiwi_vt_terminal *terminal, char *buffer, size_t buffer_size, size_t *required);
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_take_response(kiwi_vt_terminal *terminal, char *buffer, size_t buffer_size, size_t *required);

/* Return and consume one bounded host effect. `payload` is deterministic JSON
 * whose string values are represented as {"bytes":"base64"}, preserving
 * arbitrary byte strings without asking the terminal to perform an OS action.
 * It uses the normal two-call buffer convention and does not consume the
 * effect until its payload buffer is sufficient. */
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_take_effect(kiwi_vt_terminal *terminal, kiwi_vt_effect *effect, char *payload, size_t payload_size, size_t *payload_required);

/* Encode host input from the terminal's current negotiated modes. Key-event
 * and input-result structs are size-tagged. `associated_text` is a bounded
 * non-control Unicode scalar sequence for Kitty associated-text reporting and
 * is otherwise ignored. The three optional key-variant fields encode Kitty
 * flag 4 only for terminals whose construction mask opted into that flag.
 * Text/key/paste use the same two-call byte buffer convention as
 * kiwi_vt_terminal_text. A key with no terminal bytes and no local action
 * returns KIWI_VT_NOT_FOUND. */
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_encode_text(kiwi_vt_terminal *terminal, uint32_t codepoint, char *buffer, size_t buffer_size, size_t *required);
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_encode_key(kiwi_vt_terminal *terminal, const kiwi_vt_key_event *event, kiwi_vt_input_result *result, char *buffer, size_t buffer_size, size_t *required);
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_encode_paste(kiwi_vt_terminal *terminal, const void *bytes, size_t byte_count, char *buffer, size_t buffer_size, size_t *required);

/* A mouse handle retains button/motion state for one terminal. It is invalid
 * after its terminal is freed. Its event encoders use the terminal's current
 * negotiated modes and the normal two-call byte buffer convention. When the
 * terminal selects DECSET 1016, supply a matching nonzero pixel_x/pixel_y
 * pair; ordinary cell coordinates are used for every other encoding. */
KIWI_VT_API kiwi_vt_status kiwi_vt_mouse_new(kiwi_vt_terminal *terminal, kiwi_vt_mouse **mouse);
KIWI_VT_API void kiwi_vt_mouse_free(kiwi_vt_mouse *mouse);
KIWI_VT_API kiwi_vt_status kiwi_vt_mouse_encode_button(kiwi_vt_mouse *mouse, const kiwi_vt_mouse_button_event *event, char *buffer, size_t buffer_size, size_t *required);
KIWI_VT_API kiwi_vt_status kiwi_vt_mouse_encode_motion(kiwi_vt_mouse *mouse, const kiwi_vt_mouse_motion_event *event, char *buffer, size_t buffer_size, size_t *required);
KIWI_VT_API kiwi_vt_status kiwi_vt_mouse_encode_wheel(kiwi_vt_mouse *mouse, const kiwi_vt_mouse_wheel_event *event, char *buffer, size_t buffer_size, size_t *required);
KIWI_VT_API kiwi_vt_status kiwi_vt_mouse_encode_focus(kiwi_vt_mouse *mouse, uint32_t focused, char *buffer, size_t buffer_size, size_t *required);

/* A render update borrows a frozen logical view. No other operation on its
 * terminal is valid until the caller ends the update. `consume_damage` is
 * nonzero to acknowledge the update's logical damage. */
KIWI_VT_API kiwi_vt_status kiwi_vt_terminal_begin_render_update(kiwi_vt_terminal *terminal, kiwi_vt_render_update **update);
KIWI_VT_API kiwi_vt_status kiwi_vt_render_update_info(const kiwi_vt_render_update *update, kiwi_vt_render_state *state);
KIWI_VT_API kiwi_vt_status kiwi_vt_render_update_cell(const kiwi_vt_render_update *update, uint32_t column, uint32_t row, kiwi_vt_render_cell *cell, char *display_text, size_t display_text_size, size_t *display_text_required);
KIWI_VT_API kiwi_vt_status kiwi_vt_render_update_end(kiwi_vt_render_update *update, uint32_t consume_damage);

/* Borrowed until the next operation on this terminal or terminal destruction. */
KIWI_VT_API const char *kiwi_vt_terminal_last_error(const kiwi_vt_terminal *terminal);

#ifdef __cplusplus
}
#endif

#endif
