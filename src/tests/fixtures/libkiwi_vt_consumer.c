#include <kiwi/vt.h>

#include <stdio.h>
#include <string.h>

static int check(kiwi_vt_status status, kiwi_vt_status expected, const kiwi_vt_terminal *terminal, const char *operation) {
  if (status == expected) return 0;
  const char *error = terminal == NULL ? kiwi_vt_last_error() : kiwi_vt_terminal_last_error(terminal);
  fprintf(stderr, "%s: status=%d expected=%d error=%s\n", operation, status, expected, error);
  return 1;
}

int main(void) {
  kiwi_vt_options options = {
      .struct_size = sizeof(options),
      .api_version = KIWI_VT_API_VERSION,
      .columns = 8,
      .rows = 1,
      .scrollback_limit = 32,
  };
  kiwi_vt_terminal *terminal = NULL;
  kiwi_vt_options incompatible = options;
  incompatible.api_version = KIWI_VT_API_VERSION + 1;
  if (check(kiwi_vt_terminal_new(&incompatible, &terminal), KIWI_VT_UNSUPPORTED_VERSION, terminal, "incompatible API version") || kiwi_vt_last_error()[0] == '\0') return 1;
  if (check(kiwi_vt_terminal_new(&options, &terminal), KIWI_VT_OK, terminal, "new")) return 1;
  if (check(kiwi_vt_terminal_resize(terminal, 0, 1), KIWI_VT_INVALID_ARGUMENT, terminal, "invalid resize") || kiwi_vt_terminal_last_error(terminal)[0] == '\0') return 1;
  if (check(kiwi_vt_terminal_set_cell_metrics(terminal, 0, 17), KIWI_VT_INVALID_ARGUMENT, terminal, "invalid cell metrics")) return 1;
  if (check(kiwi_vt_terminal_set_cell_metrics(terminal, 9, 17), KIWI_VT_OK, terminal, "set cell metrics")) return 1;

  size_t consumed = 0;
  if (check(kiwi_vt_terminal_write(terminal, "hello", 5, &consumed), KIWI_VT_OK, terminal, "write") || consumed != 5) return 1;
  if (check(kiwi_vt_terminal_finish(terminal), KIWI_VT_OK, terminal, "finish")) return 1;

  size_t required = 0;
  if (check(kiwi_vt_terminal_text(terminal, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "text size") || required != 6) return 1;
  char text[6];
  if (check(kiwi_vt_terminal_text(terminal, text, sizeof(text), &required), KIWI_VT_OK, terminal, "text") || strcmp(text, "hello") != 0) return 1;

  kiwi_vt_render_update *update = NULL;
  if (check(kiwi_vt_terminal_begin_render_update(terminal, &update), KIWI_VT_OK, terminal, "begin render update")) return 1;
  kiwi_vt_render_state state = { .struct_size = sizeof(state) };
  if (check(kiwi_vt_render_update_info(update, &state), KIWI_VT_OK, terminal, "render state") || state.columns != 8 || state.rows != 1 || state.cursor_column != 5 || state.damage_cells == 0) return 1;
  kiwi_vt_render_cell cell = { .struct_size = sizeof(cell) };
  if (check(kiwi_vt_render_update_cell(update, 0, 0, &cell, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "cell size") || required != 2 || cell.continuation != 0) return 1;
  char display_text[2];
  if (check(kiwi_vt_render_update_cell(update, 0, 0, &cell, display_text, sizeof(display_text), &required), KIWI_VT_OK, terminal, "cell") || strcmp(display_text, "h") != 0) return 1;
  if (check(kiwi_vt_terminal_write(terminal, "x", 1, &consumed), KIWI_VT_INVALID_ARGUMENT, terminal, "write during render update")) return 1;
  if (check(kiwi_vt_render_update_end(update, 1), KIWI_VT_OK, terminal, "end render update")) return 1;
  update = NULL;
  if (check(kiwi_vt_terminal_begin_render_update(terminal, &update), KIWI_VT_OK, terminal, "begin clean render update")) return 1;
  state.struct_size = sizeof(state);
  if (check(kiwi_vt_render_update_info(update, &state), KIWI_VT_OK, terminal, "clean render state") || state.damage_cells != 0) return 1;
  if (check(kiwi_vt_render_update_end(update, 0), KIWI_VT_OK, terminal, "end clean render update")) return 1;

  if (check(kiwi_vt_terminal_write(terminal, "\a", 1, &consumed), KIWI_VT_OK, terminal, "bell effect")) return 1;
  kiwi_vt_effect effect = { .struct_size = sizeof(effect) };
  static const char expected_bell_payload[] = "{\"kind\":{\"bytes\":\"YmVsbA==\"},\"value\":{}}";
  if (check(kiwi_vt_terminal_take_effect(terminal, &effect, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "bell effect size") || effect.kind != KIWI_VT_EFFECT_BELL || required != sizeof(expected_bell_payload)) return 1;
  char effect_payload[sizeof(expected_bell_payload)];
  if (check(kiwi_vt_terminal_take_effect(terminal, &effect, effect_payload, sizeof(effect_payload), &required), KIWI_VT_OK, terminal, "bell effect") || strcmp(effect_payload, expected_bell_payload) != 0) return 1;
  static const char title_effect[] = "\033]2;Kiwi\a";
  static const char expected_title_payload[] = "{\"kind\":{\"bytes\":\"dGl0bGVfY2hhbmdlZA==\"},\"value\":{\"title\":{\"bytes\":\"S2l3aQ==\"}}}";
  if (check(kiwi_vt_terminal_write(terminal, title_effect, sizeof(title_effect) - 1, &consumed), KIWI_VT_OK, terminal, "title effect")) return 1;
  if (check(kiwi_vt_terminal_take_effect(terminal, &effect, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "title effect size") || effect.kind != KIWI_VT_EFFECT_TITLE_CHANGED || required != sizeof(expected_title_payload)) return 1;
  char title_payload[sizeof(expected_title_payload)];
  if (check(kiwi_vt_terminal_take_effect(terminal, &effect, title_payload, sizeof(title_payload), &required), KIWI_VT_OK, terminal, "title effect") || strcmp(title_payload, expected_title_payload) != 0) return 1;
  static const char unknown_mode[] = "\033[?9999h";
  if (check(kiwi_vt_terminal_write(terminal, unknown_mode, sizeof(unknown_mode) - 1, &consumed), KIWI_VT_OK, terminal, "unknown effect")) return 1;
  if (check(kiwi_vt_terminal_take_effect(terminal, &effect, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "unknown effect size") || effect.kind != KIWI_VT_EFFECT_UNKNOWN_SEQUENCE || required > 512) return 1;
  char unknown_payload[512];
  if (check(kiwi_vt_terminal_take_effect(terminal, &effect, unknown_payload, sizeof(unknown_payload), &required), KIWI_VT_OK, terminal, "unknown effect") || strstr(unknown_payload, "\"parameters\":[9999]") == NULL) return 1;

  if (check(kiwi_vt_terminal_encode_text(terminal, 0x20ac, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "text input size") || required != 4) return 1;
  char input_text[4];
  if (check(kiwi_vt_terminal_encode_text(terminal, 0x20ac, input_text, sizeof(input_text), &required), KIWI_VT_OK, terminal, "text input") || strcmp(input_text, "€") != 0) return 1;
  kiwi_vt_key_event key = {
      .struct_size = sizeof(key),
      .key = KIWI_VT_KEY_UP,
      .action = KIWI_VT_KEY_ACTION_PRESS,
      .modifiers = 0,
  };
  kiwi_vt_input_result input = { .struct_size = sizeof(input) };
  if (check(kiwi_vt_terminal_encode_key(terminal, &key, &input, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "key input size") || required != 4) return 1;
  char key_bytes[4];
  if (check(kiwi_vt_terminal_encode_key(terminal, &key, &input, key_bytes, sizeof(key_bytes), &required), KIWI_VT_OK, terminal, "key input") || strcmp(key_bytes, "\033[A") != 0 || input.local_action != KIWI_VT_LOCAL_ACTION_NONE) return 1;
  if (check(kiwi_vt_terminal_write(terminal, "\033[?67h", 6, &consumed), KIWI_VT_OK, terminal, "enable backarrow")) return 1;
  key.key = KIWI_VT_KEY_BACKSPACE;
  if (check(kiwi_vt_terminal_encode_key(terminal, &key, &input, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "backarrow input size") || required != 2) return 1;
  char backarrow_bytes[2];
  if (check(kiwi_vt_terminal_encode_key(terminal, &key, &input, backarrow_bytes, sizeof(backarrow_bytes), &required), KIWI_VT_OK, terminal, "backarrow input") || strcmp(backarrow_bytes, "\b") != 0) return 1;
  key.key = 'C';
  key.modifiers = KIWI_VT_MODIFIER_CONTROL | KIWI_VT_MODIFIER_SHIFT;
  if (check(kiwi_vt_terminal_encode_key(terminal, &key, &input, key_bytes, sizeof(key_bytes), &required), KIWI_VT_OK, terminal, "local key input") || required != 0 || input.local_action != KIWI_VT_LOCAL_ACTION_COPY || input.suppress_text != 1) return 1;
  if (check(kiwi_vt_terminal_write(terminal, "\033=", 2, &consumed), KIWI_VT_OK, terminal, "enable application keypad")) return 1;
  key.key = KIWI_VT_KEY_KP_1;
  key.modifiers = 0;
  if (check(kiwi_vt_terminal_encode_key(terminal, &key, &input, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "application keypad input size") || required != 4) return 1;
  char keypad_bytes[4];
  if (check(kiwi_vt_terminal_encode_key(terminal, &key, &input, keypad_bytes, sizeof(keypad_bytes), &required), KIWI_VT_OK, terminal, "application keypad input") || strcmp(keypad_bytes, "\033Oq") != 0 || input.suppress_text != 1) return 1;
  key.key = KIWI_VT_KEY_UP;
  if (check(kiwi_vt_terminal_write(terminal, "\033[=24u", 7, &consumed), KIWI_VT_OK, terminal, "enable associated key text")) return 1;
  static const uint32_t associated_a[] = { 'A' };
  key.key = 'A';
  key.modifiers = KIWI_VT_MODIFIER_SHIFT;
  key.associated_text = associated_a;
  key.associated_text_count = 1;
  if (check(kiwi_vt_terminal_encode_key(terminal, &key, &input, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "associated key input size") || required != 11) return 1;
  char associated_key_bytes[11];
  if (check(kiwi_vt_terminal_encode_key(terminal, &key, &input, associated_key_bytes, sizeof(associated_key_bytes), &required), KIWI_VT_OK, terminal, "associated key input") || strcmp(associated_key_bytes, "\033[97;2;65u") != 0 || input.suppress_text != 1) return 1;
  key.associated_text = NULL;
  key.associated_text_count = 0;
  if (check(kiwi_vt_terminal_write(terminal, "\033[?2004h", 8, &consumed), KIWI_VT_OK, terminal, "enable bracketed paste")) return 1;
  if (check(kiwi_vt_terminal_encode_paste(terminal, "x", 1, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "paste input size") || required != 14) return 1;
  char paste_bytes[14];
  if (check(kiwi_vt_terminal_encode_paste(terminal, "x", 1, paste_bytes, sizeof(paste_bytes), &required), KIWI_VT_OK, terminal, "paste input") || strcmp(paste_bytes, "\033[200~x\033[201~") != 0) return 1;

  static const char mouse_modes[] = "\033[?1006h\033[?1000h\033[?1004h";
  if (check(kiwi_vt_terminal_write(terminal, mouse_modes, sizeof(mouse_modes) - 1, &consumed), KIWI_VT_OK, terminal, "enable mouse modes")) return 1;
  kiwi_vt_input_modes modes = { .struct_size = sizeof(modes) };
  if (check(kiwi_vt_terminal_input_modes(terminal, &modes), KIWI_VT_OK, terminal, "input modes") || modes.bracketed_paste != 1 || modes.focus_reporting != 1 || modes.keyboard_flags != 24 || modes.mouse_protocol != KIWI_VT_MOUSE_PROTOCOL_SGR || modes.mouse_tracking != KIWI_VT_MOUSE_TRACKING_NORMAL || modes.alternate_screen != 0 || modes.alternate_scroll != 0 || modes.application_keypad != 1 || modes.backarrow != 1) return 1;
  kiwi_vt_mouse *mouse = NULL;
  if (check(kiwi_vt_mouse_new(terminal, &mouse), KIWI_VT_OK, terminal, "new mouse")) return 1;
  kiwi_vt_mouse_button_event button = {
      .struct_size = sizeof(button),
      .button = 0,
      .action = KIWI_VT_MOUSE_ACTION_PRESS,
      .column = 4,
      .row = 2,
      .modifiers = KIWI_VT_MODIFIER_SHIFT,
  };
  if (check(kiwi_vt_mouse_encode_button(mouse, &button, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "mouse button size") || required != 10) return 1;
  char mouse_bytes[11];
  if (check(kiwi_vt_mouse_encode_button(mouse, &button, mouse_bytes, sizeof(mouse_bytes), &required), KIWI_VT_OK, terminal, "mouse button") || strcmp(mouse_bytes, "\033[<4;4;2M") != 0) return 1;
  kiwi_vt_mouse_wheel_event wheel = {
      .struct_size = sizeof(wheel),
      .column = 4,
      .row = 2,
      .modifiers = 0,
      .delta = 1,
  };
  if (check(kiwi_vt_mouse_encode_wheel(mouse, &wheel, mouse_bytes, sizeof(mouse_bytes), &required), KIWI_VT_OK, terminal, "mouse wheel") || strcmp(mouse_bytes, "\033[<64;4;2M") != 0) return 1;
  wheel.delta = 0;
  wheel.horizontal_delta = 1;
  if (check(kiwi_vt_mouse_encode_wheel(mouse, &wheel, mouse_bytes, sizeof(mouse_bytes), &required), KIWI_VT_OK, terminal, "horizontal mouse wheel") || strcmp(mouse_bytes, "\033[<66;4;2M") != 0) return 1;
  wheel.delta = 1;
  wheel.horizontal_delta = 0;
  if (check(kiwi_vt_mouse_encode_focus(mouse, 0, mouse_bytes, sizeof(mouse_bytes), &required), KIWI_VT_OK, terminal, "mouse focus") || strcmp(mouse_bytes, "\033[O") != 0) return 1;
  static const char any_motion[] = "\033[?1003h";
  if (check(kiwi_vt_terminal_write(terminal, any_motion, sizeof(any_motion) - 1, &consumed), KIWI_VT_OK, terminal, "enable any-motion mouse")) return 1;
  kiwi_vt_mouse_motion_event motion = {
      .struct_size = sizeof(motion),
      .column = 5,
      .row = 3,
      .modifiers = 0,
  };
  if (check(kiwi_vt_mouse_encode_motion(mouse, &motion, mouse_bytes, sizeof(mouse_bytes), &required), KIWI_VT_OK, terminal, "mouse motion") || strcmp(mouse_bytes, "\033[<35;5;3M") != 0) return 1;
  static const char pixel_mouse_mode[] = "\033[?1016h";
  if (check(kiwi_vt_terminal_write(terminal, pixel_mouse_mode, sizeof(pixel_mouse_mode) - 1, &consumed), KIWI_VT_OK, terminal, "enable pixel mouse")) return 1;
  button.pixel_x = 14;
  button.pixel_y = 22;
  if (check(kiwi_vt_mouse_encode_button(mouse, &button, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "pixel mouse button size") || required != 12) return 1;
  char pixel_mouse_bytes[12];
  if (check(kiwi_vt_mouse_encode_button(mouse, &button, pixel_mouse_bytes, sizeof(pixel_mouse_bytes), &required), KIWI_VT_OK, terminal, "pixel mouse button") || strcmp(pixel_mouse_bytes, "\033[<4;14;22M") != 0) return 1;
  static const char alternate_scroll_modes[] = "\033[?1003l\033[?1007h\033[?1049h";
  if (check(kiwi_vt_terminal_write(terminal, alternate_scroll_modes, sizeof(alternate_scroll_modes) - 1, &consumed), KIWI_VT_OK, terminal, "enable alternate scroll")) return 1;
  modes.struct_size = sizeof(modes);
  if (check(kiwi_vt_terminal_input_modes(terminal, &modes), KIWI_VT_OK, terminal, "alternate input modes") || modes.mouse_tracking != KIWI_VT_MOUSE_TRACKING_NONE || modes.alternate_screen != 1 || modes.alternate_scroll != 1) return 1;
  if (check(kiwi_vt_mouse_encode_wheel(mouse, &wheel, mouse_bytes, sizeof(mouse_bytes), &required), KIWI_VT_OK, terminal, "alternate scroll wheel") || strcmp(mouse_bytes, "\033[A") != 0) return 1;
  kiwi_vt_mouse_free(mouse);

  static const char geometry_and_status_query[] = "\033[14t\033[16t\033[18t\033[>c\033[5n";
  if (check(kiwi_vt_terminal_write(terminal, geometry_and_status_query, sizeof(geometry_and_status_query) - 1, &consumed), KIWI_VT_OK, terminal, "geometry and status query")) return 1;
  char geometry[32];
  if (check(kiwi_vt_terminal_take_response(terminal, geometry, sizeof(geometry), &required), KIWI_VT_OK, terminal, "text area pixel geometry") || strcmp(geometry, "\033[4;17;72t") != 0) return 1;
  if (check(kiwi_vt_terminal_take_response(terminal, geometry, sizeof(geometry), &required), KIWI_VT_OK, terminal, "cell pixel geometry") || strcmp(geometry, "\033[6;17;9t") != 0) return 1;
  if (check(kiwi_vt_terminal_take_response(terminal, geometry, sizeof(geometry), &required), KIWI_VT_OK, terminal, "text area cell geometry") || strcmp(geometry, "\033[8;1;8t") != 0) return 1;
  if (check(kiwi_vt_terminal_take_response(terminal, geometry, sizeof(geometry), &required), KIWI_VT_OK, terminal, "secondary device attributes") || strcmp(geometry, "\033[>0;1;0c") != 0) return 1;
  if (check(kiwi_vt_terminal_take_response(terminal, NULL, 0, &required), KIWI_VT_BUFFER_TOO_SMALL, terminal, "response size") || required != 5) return 1;
  char response[5];
  if (check(kiwi_vt_terminal_take_response(terminal, response, sizeof(response), &required), KIWI_VT_OK, terminal, "response") || strcmp(response, "\033[0n") != 0) return 1;
  if (check(kiwi_vt_terminal_take_response(terminal, response, sizeof(response), &required), KIWI_VT_NOT_FOUND, terminal, "empty response")) return 1;

  if (check(kiwi_vt_terminal_resize(terminal, 5, 2), KIWI_VT_OK, terminal, "resize")) return 1;
  kiwi_vt_mouse *terminal_owned_mouse = NULL;
  if (check(kiwi_vt_mouse_new(terminal, &terminal_owned_mouse), KIWI_VT_OK, terminal, "terminal-owned mouse")) return 1;
  kiwi_vt_terminal_free(terminal);
  return 0;
}
