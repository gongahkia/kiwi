#define _GNU_SOURCE
#include "kiwi/vt.h"

#include <dlfcn.h>
#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define KIWI_LUA_OK 0
#define KIWI_LUA_TNIL 0
#define KIWI_LUA_TNUMBER 3
#define KIWI_LUA_TSTRING 4
#define KIWI_LUA_TTABLE 5
#define KIWI_LUA_TFUNCTION 6
#define KIWI_LUA_GLOBALSINDEX (-10002)
#define KIWI_LUA_REGISTRYINDEX (-10000)
#define KIWI_VT_DEFAULT_SCROLLBACK 2000u
#define KIWI_VT_MAX_COLUMNS 4096u
#define KIWI_VT_MAX_ROWS 4096u
#define KIWI_VT_MAX_SCROLLBACK 100000u

#ifndef KIWI_VT_VERSION
#define KIWI_VT_VERSION "0.0.0"
#endif

typedef struct lua_State lua_State;

typedef struct kiwi_lua_api {
  void *library;
  lua_State *(*luaL_newstate)(void);
  void (*luaL_openlibs)(lua_State *state);
  int (*luaL_loadstring)(lua_State *state, const char *source);
  int (*lua_pcall)(lua_State *state, int arguments, int results, int error_function);
  void (*lua_close)(lua_State *state);
  void (*lua_getfield)(lua_State *state, int index, const char *name);
  void (*lua_rawgeti)(lua_State *state, int index, int reference);
  void (*lua_createtable)(lua_State *state, int array_count, int record_count);
  void (*lua_rawseti)(lua_State *state, int index, int array_index);
  void (*lua_pushnil)(lua_State *state);
  void (*lua_pushinteger)(lua_State *state, ptrdiff_t value);
  void (*lua_pushboolean)(lua_State *state, int value);
  void (*lua_pushnumber)(lua_State *state, double value);
  const char *(*lua_pushlstring)(lua_State *state, const char *value, size_t length);
  const char *(*lua_tolstring)(lua_State *state, int index, size_t *length);
  ptrdiff_t (*lua_tointeger)(lua_State *state, int index);
  int (*lua_type)(lua_State *state, int index);
  int (*luaL_ref)(lua_State *state, int index);
  void (*luaL_unref)(lua_State *state, int index, int reference);
  void (*lua_setfield)(lua_State *state, int index, const char *name);
  void (*lua_settop)(lua_State *state, int index);
} kiwi_lua_api;

struct kiwi_vt_render_update;
struct kiwi_vt_mouse;

struct kiwi_vt_terminal {
  kiwi_lua_api lua;
  lua_State *state;
  int reference;
  struct kiwi_vt_render_update *active_update;
  struct kiwi_vt_mouse *mice;
  char *effect;
  size_t effect_length;
  uint32_t effect_kind;
  char *response;
  size_t response_length;
  char error[512];
};

struct kiwi_vt_render_update {
  kiwi_vt_terminal *terminal;
  int reference;
};

struct kiwi_vt_mouse {
  kiwi_vt_terminal *terminal;
  int reference;
  struct kiwi_vt_mouse *next;
};

static _Thread_local char kiwi_vt_global_error[512];

static const char kiwi_vt_bootstrap[] =
    "local VT = require('kiwi.vt')\n"
    "local Headless = require('kiwi.vt.headless')\n"
    "local Base64 = require('kiwi.terminal.base64')\n"
    "local function effect_json(value)\n"
    "  local value_type = type(value)\n"
    "  if value_type == 'nil' then return 'null' end\n"
    "  if value_type == 'boolean' then return value and 'true' or 'false' end\n"
    "  if value_type == 'number' then return string.format('%.17g', value) end\n"
    "  if value_type == 'string' then return '{\\\"bytes\\\":\\\"' .. Base64.encode(value) .. '\\\"}' end\n"
    "  if value_type ~= 'table' then error('unsupported effect value type: ' .. value_type) end\n"
    "  local keys, array, maximum = {}, next(value) ~= nil, 0\n"
    "  for key in pairs(value) do\n"
    "    if type(key) == 'number' and key >= 1 and key % 1 == 0 then\n"
    "      if key > maximum then maximum = key end\n"
    "    else\n"
    "      array = false\n"
    "      if type(key) ~= 'string' or key:find('[^A-Za-z0-9_]') then error('unsupported effect key') end\n"
    "      keys[#keys + 1] = key\n"
    "    end\n"
    "  end\n"
    "  if array then\n"
    "    local values = {}\n"
    "    for index = 1, maximum do\n"
    "      if value[index] == nil then error('sparse effect array') end\n"
    "      values[index] = effect_json(value[index])\n"
    "    end\n"
    "    return '[' .. table.concat(values, ',') .. ']'\n"
    "  end\n"
    "  table.sort(keys)\n"
    "  local fields = {}\n"
    "  for index, key in ipairs(keys) do fields[index] = '\\\"' .. key .. '\\\":' .. effect_json(value[key]) end\n"
    "  return '{' .. table.concat(fields, ',') .. '}'\n"
    "end\n"
    "local function with_input_modes(terminal, callback)\n"
    "  local view = terminal:begin_render_update()\n"
    "  local results = { xpcall(function() return callback(view.input_modes) end, debug.traceback) }\n"
    "  terminal:end_render_update(false)\n"
    "  if not results[1] then error(results[2], 0) end\n"
    "  return unpack(results, 2)\n"
    "end\n"
    "kiwi_vt_capi = {\n"
    "  new = function(columns, rows, scrollback, keyboard_supported_flags, osc52_read)\n"
    "    local state_options = { scrollback_limit = scrollback }\n"
    "    if keyboard_supported_flags ~= 0 then state_options.keyboard_supported_flags = keyboard_supported_flags end\n"
    "    if osc52_read ~= 0 then state_options.osc52_read = true end\n"
    "    return VT.new({ columns = columns, rows = rows, state_options = state_options })\n"
    "  end,\n"
    "  write = function(terminal, bytes) return terminal:write(bytes) end,\n"
    "  finish = function(terminal) terminal:finish() end,\n"
    "  resize = function(terminal, columns, rows) terminal:resize(columns, rows) end,\n"
    "  set_cell_metrics = function(terminal, width, height) terminal:set_cell_metrics(width, height) end,\n"
    "  text = function(terminal) return Headless.render_terminal(terminal, { trim_trailing = true }).text end,\n"
    "  response = function(terminal) return terminal:pop_response() end,\n"
    "  effect = function(terminal) local effect = terminal:pop_effect(); if effect == nil then return nil end; return effect.kind, '{\\\"kind\\\":{\\\"bytes\\\":\\\"' .. Base64.encode(effect.kind) .. '\\\"},\\\"value\\\":' .. effect_json(effect.value) .. '}' end,\n"
    "  input_modes = function(terminal) return with_input_modes(terminal, function(modes)\n"
    "    local protocol = ({ x10 = 0, utf8 = 1, sgr = 2, urxvt = 3, ['sgr-pixels'] = 4 })[modes.mouse_protocol] or 0\n"
    "    local tracking = ({ none = 0, x10 = 1, normal = 2, button = 3, any = 4 })[modes.mouse_tracking] or 0\n"
    "    local shift_escape = modes.mouse_shift_escape == false and 1 or modes.mouse_shift_escape == true and 2 or 0\n"
    "    return modes.application_cursor and 1 or 0, modes.bracketed_paste and 1 or 0, modes.focus_reporting and 1 or 0, modes.keyboard_flags or 0, protocol, tracking, modes.alternate_screen and 1 or 0, modes.alternate_scroll and 1 or 0, modes.application_keypad and 1 or 0, modes.backarrow and 1 or 0, shift_escape\n"
    "  end) end,\n"
    "  input_text = function(terminal, codepoint) return with_input_modes(terminal, function(modes) return VT.Input.text(codepoint, modes) end) end,\n"
    "  input_key = function(terminal, key, action, modifiers, associated_text, layout_key, shifted_key, base_key, unicode_key)\n"
    "    return with_input_modes(terminal, function(modes)\n"
    "      local event = { key = key, action = action, modifiers = modifiers }\n"
    "      if associated_text ~= nil then event.associated_text = associated_text end\n"
    "      if layout_key ~= nil then event.layout_key = layout_key end\n"
    "      if shifted_key ~= nil then event.shifted_key = shifted_key end\n"
    "      if base_key ~= nil then event.base_key = base_key end\n"
    "      if unicode_key ~= nil then event.unicode_key = unicode_key end\n"
    "      local result = VT.Input.key(event, modes)\n"
    "      if result == nil then return '', 0, nil end\n"
    "      return result.local_action or '', result.suppress_text and 1 or 0, result.bytes\n"
    "    end)\n"
    "  end,\n"
    "  input_paste = function(terminal, bytes) return with_input_modes(terminal, function(modes) return VT.Input.paste(bytes, modes) end) end,\n"
    "  new_mouse = function() return VT.Input.new_mouse() end,\n"
    "  input_mouse_button = function(terminal, mouse, button, action, column, row, modifiers, pixel_x, pixel_y) return with_input_modes(terminal, function(modes) return mouse:button({ button = button, action = action, column = column, row = row, modifiers = modifiers, pixel_x = pixel_x, pixel_y = pixel_y }, modes) end) end,\n"
    "  input_mouse_motion = function(terminal, mouse, column, row, modifiers, pixel_x, pixel_y) return with_input_modes(terminal, function(modes) return mouse:motion({ column = column, row = row, modifiers = modifiers, pixel_x = pixel_x, pixel_y = pixel_y }, modes) end) end,\n"
    "  input_mouse_wheel = function(terminal, mouse, column, row, delta, modifiers, pixel_x, pixel_y, horizontal_delta) return with_input_modes(terminal, function(modes) return mouse:wheel({ column = column, row = row, delta = delta, modifiers = modifiers, pixel_x = pixel_x, pixel_y = pixel_y, horizontal_delta = horizontal_delta }, modes) end) end,\n"
    "  input_mouse_focus = function(terminal, mouse, focused) return with_input_modes(terminal, function(modes) return mouse:focus(focused, modes) end) end,\n"
    "  begin_render = function(terminal) return terminal:begin_render_update() end,\n"
    "  render_info = function(view)\n"
    "    return view.columns, view.rows, view.active_screen == 'alternate' and 1 or 0, view.cursor.column, view.cursor.row, view.cursor.visible and 1 or 0, view.cursor.pending_wrap and 1 or 0, view.damage.cells, view.damage.full and 1 or 0, view.generation\n"
    "  end,\n"
    "  render_cell = function(view, column, row)\n"
    "    local cell = view:cell(column, row)\n"
    "    return cell.continuation and cell.anchor_column or column, cell.width, cell.flags, cell.fg, cell.bg, cell.continuation and 1 or 0, cell.display_text or cell.glyph or ''\n"
    "  end,\n"
    "  end_render = function(terminal, consumed) terminal:end_render_update(consumed) end,\n"
    "  close = function(terminal) terminal:close() end,\n"
    "}\n";

static void kiwi_vt_set_error(kiwi_vt_terminal *terminal, const char *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  if (terminal != NULL) {
    (void)vsnprintf(terminal->error, sizeof(terminal->error), format, arguments);
    (void)snprintf(kiwi_vt_global_error, sizeof(kiwi_vt_global_error), "%s", terminal->error);
  } else {
    (void)vsnprintf(kiwi_vt_global_error, sizeof(kiwi_vt_global_error), format, arguments);
  }
  va_end(arguments);
}

static void kiwi_vt_copy_lua_error(kiwi_vt_terminal *terminal, const char *prefix) {
  size_t length = 0;
  const char *message = terminal->lua.lua_tolstring(terminal->state, -1, &length);
  if (message == NULL) {
    kiwi_vt_set_error(terminal, "%s", prefix);
    return;
  }
  kiwi_vt_set_error(terminal, "%s: %.*s", prefix, (int)(length > 400 ? 400 : length), message);
}

static void kiwi_vt_reset_stack(kiwi_vt_terminal *terminal) {
  terminal->lua.lua_settop(terminal->state, 0);
}

static void kiwi_lua_getglobal(kiwi_lua_api *lua, lua_State *state, const char *name) {
  lua->lua_getfield(state, KIWI_LUA_GLOBALSINDEX, name);
}

static bool kiwi_vt_load_lua(kiwi_vt_terminal *terminal) {
  static const char *const names[] = {
#if defined(__APPLE__)
      "libluajit-5.1.2.dylib",
      "libluajit-5.1.dylib",
      "libluajit.dylib",
#else
      "libluajit-5.1.so.2",
      "libluajit-5.1.so",
#endif
      NULL,
  };
  kiwi_lua_api *lua = &terminal->lua;
  const char *configured = getenv("KIWI_VT_LUAJIT_LIB");
  if (configured != NULL && configured[0] != '\0') {
    lua->library = dlopen(configured, RTLD_NOW | RTLD_LOCAL);
  }
  for (size_t index = 0; names[index] != NULL && lua->library == NULL; ++index) {
    lua->library = dlopen(names[index], RTLD_NOW | RTLD_LOCAL);
  }
  if (lua->library == NULL) {
    kiwi_vt_set_error(terminal, "LuaJIT runtime unavailable%s%s: %s", configured == NULL || configured[0] == '\0' ? "" : " at ", configured == NULL || configured[0] == '\0' ? "" : configured, dlerror() == NULL ? "dlopen failed" : dlerror());
    return false;
  }

#define KIWI_LOAD_LUA_SYMBOL(field, symbol)                                                                                     \
  do {                                                                                                                           \
    lua->field = dlsym(lua->library, symbol);                                                                                   \
    if (lua->field == NULL) {                                                                                                   \
      kiwi_vt_set_error(terminal, "LuaJIT runtime is missing %s", symbol);                                                   \
      dlclose(lua->library);                                                                                                    \
      lua->library = NULL;                                                                                                      \
      return false;                                                                                                             \
    }                                                                                                                            \
  } while (0)

  KIWI_LOAD_LUA_SYMBOL(luaL_newstate, "luaL_newstate");
  KIWI_LOAD_LUA_SYMBOL(luaL_openlibs, "luaL_openlibs");
  KIWI_LOAD_LUA_SYMBOL(luaL_loadstring, "luaL_loadstring");
  KIWI_LOAD_LUA_SYMBOL(lua_pcall, "lua_pcall");
  KIWI_LOAD_LUA_SYMBOL(lua_close, "lua_close");
  KIWI_LOAD_LUA_SYMBOL(lua_getfield, "lua_getfield");
  KIWI_LOAD_LUA_SYMBOL(lua_rawgeti, "lua_rawgeti");
  KIWI_LOAD_LUA_SYMBOL(lua_createtable, "lua_createtable");
  KIWI_LOAD_LUA_SYMBOL(lua_rawseti, "lua_rawseti");
  KIWI_LOAD_LUA_SYMBOL(lua_pushnil, "lua_pushnil");
  KIWI_LOAD_LUA_SYMBOL(lua_pushinteger, "lua_pushinteger");
  KIWI_LOAD_LUA_SYMBOL(lua_pushboolean, "lua_pushboolean");
  KIWI_LOAD_LUA_SYMBOL(lua_pushnumber, "lua_pushnumber");
  KIWI_LOAD_LUA_SYMBOL(lua_pushlstring, "lua_pushlstring");
  KIWI_LOAD_LUA_SYMBOL(lua_tolstring, "lua_tolstring");
  KIWI_LOAD_LUA_SYMBOL(lua_tointeger, "lua_tointeger");
  KIWI_LOAD_LUA_SYMBOL(lua_type, "lua_type");
  KIWI_LOAD_LUA_SYMBOL(luaL_ref, "luaL_ref");
  KIWI_LOAD_LUA_SYMBOL(luaL_unref, "luaL_unref");
  KIWI_LOAD_LUA_SYMBOL(lua_setfield, "lua_setfield");
  KIWI_LOAD_LUA_SYMBOL(lua_settop, "lua_settop");
#undef KIWI_LOAD_LUA_SYMBOL
  return true;
}

static bool kiwi_vt_lua_root(char *root, size_t root_size) {
  const char *configured = getenv("KIWI_LIBKIWI_LUA_ROOT");
  if (configured != NULL && configured[0] != '\0') {
    if (strlen(configured) >= root_size) return false;
    (void)snprintf(root, root_size, "%s", configured);
    return true;
  }

  Dl_info source;
  if (dladdr((const void *)&kiwi_vt_terminal_new, &source) == 0 || source.dli_fname == NULL) return false;
  char library_path[PATH_MAX];
  if (realpath(source.dli_fname, library_path) == NULL) return false;
  char *slash = strrchr(library_path, '/');
  if (slash == NULL) return false;
  *slash = '\0';
  int written = snprintf(root, root_size, "%s/../lua", library_path);
  return written >= 0 && (size_t)written < root_size;
}

static bool kiwi_vt_configure_package_path(kiwi_vt_terminal *terminal) {
  char root[PATH_MAX];
  if (!kiwi_vt_lua_root(root, sizeof(root))) {
    kiwi_vt_set_error(terminal, "cannot resolve the libkiwi-vt Lua module directory; set KIWI_LIBKIWI_LUA_ROOT");
    return false;
  }

  kiwi_lua_api *lua = &terminal->lua;
  kiwi_lua_getglobal(lua, terminal->state, "package");
  lua->lua_getfield(terminal->state, -1, "path");
  size_t existing_length = 0;
  const char *existing = lua->lua_tolstring(terminal->state, -1, &existing_length);
  size_t root_length = strlen(root);
  const char suffix[] = "/?.lua;";
  const char init_suffix[] = "/?/init.lua;";
  size_t required = root_length * 2 + sizeof(suffix) + sizeof(init_suffix) + existing_length;
  char *path = malloc(required);
  if (path == NULL) {
    kiwi_vt_set_error(terminal, "out of memory while configuring the Lua module path");
    kiwi_vt_reset_stack(terminal);
    return false;
  }
  (void)snprintf(path, required, "%s%s%s%s%s", root, suffix, root, init_suffix, existing == NULL ? "" : existing);
  lua->lua_pushlstring(terminal->state, path, strlen(path));
  lua->lua_setfield(terminal->state, -3, "path");
  free(path);
  kiwi_vt_reset_stack(terminal);
  return true;
}

static kiwi_vt_status kiwi_vt_pcall(kiwi_vt_terminal *terminal, int arguments, int results) {
  if (terminal->lua.lua_pcall(terminal->state, arguments, results, 0) == KIWI_LUA_OK) return KIWI_VT_OK;
  kiwi_vt_copy_lua_error(terminal, "Lua terminal operation failed");
  kiwi_vt_reset_stack(terminal);
  return KIWI_VT_LUA_ERROR;
}

static kiwi_vt_status kiwi_vt_push_method(kiwi_vt_terminal *terminal, const char *name) {
  kiwi_lua_api *lua = &terminal->lua;
  kiwi_lua_getglobal(lua, terminal->state, "kiwi_vt_capi");
  if (lua->lua_type(terminal->state, -1) != KIWI_LUA_TTABLE) {
    kiwi_vt_set_error(terminal, "libkiwi-vt bootstrap did not export its C API table");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  lua->lua_getfield(terminal->state, -1, name);
  if (lua->lua_type(terminal->state, -1) != KIWI_LUA_TFUNCTION) {
    kiwi_vt_set_error(terminal, "libkiwi-vt bootstrap is missing method %s", name);
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  return KIWI_VT_OK;
}

static kiwi_vt_status kiwi_vt_push_terminal_method(kiwi_vt_terminal *terminal, const char *name) {
  kiwi_vt_status status = kiwi_vt_push_method(terminal, name);
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_rawgeti(terminal->state, KIWI_LUA_REGISTRYINDEX, terminal->reference);
  return KIWI_VT_OK;
}

static kiwi_vt_status kiwi_vt_require_idle(kiwi_vt_terminal *terminal) {
  if (terminal == NULL) {
    kiwi_vt_set_error(NULL, "terminal handle is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  if (terminal->active_update != NULL) {
    kiwi_vt_set_error(terminal, "terminal render update is active");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  return KIWI_VT_OK;
}

static kiwi_vt_status kiwi_vt_require_mouse(kiwi_vt_mouse *mouse, kiwi_vt_terminal **terminal) {
  if (mouse == NULL || mouse->terminal == NULL) {
    kiwi_vt_set_error(NULL, "mouse handle is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  *terminal = mouse->terminal;
  return kiwi_vt_require_idle(*terminal);
}

static kiwi_vt_status kiwi_vt_push_mouse_method(kiwi_vt_mouse *mouse, const char *name, kiwi_vt_terminal **terminal) {
  kiwi_vt_status status = kiwi_vt_require_mouse(mouse, terminal);
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_push_method(*terminal, name);
  if (status != KIWI_VT_OK) return status;
  (*terminal)->lua.lua_rawgeti((*terminal)->state, KIWI_LUA_REGISTRYINDEX, (*terminal)->reference);
  (*terminal)->lua.lua_rawgeti((*terminal)->state, KIWI_LUA_REGISTRYINDEX, mouse->reference);
  return KIWI_VT_OK;
}

static kiwi_vt_status kiwi_vt_require_render_update(const kiwi_vt_render_update *update, kiwi_vt_terminal **terminal) {
  if (update == NULL || update->terminal == NULL || update->terminal->active_update != update) {
    kiwi_vt_set_error(NULL, "render update handle is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  *terminal = update->terminal;
  return KIWI_VT_OK;
}

static kiwi_vt_status kiwi_vt_push_render_update_method(const kiwi_vt_render_update *update, const char *name, kiwi_vt_terminal **terminal) {
  kiwi_vt_status status = kiwi_vt_require_render_update(update, terminal);
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_push_method(*terminal, name);
  if (status != KIWI_VT_OK) return status;
  (*terminal)->lua.lua_rawgeti((*terminal)->state, KIWI_LUA_REGISTRYINDEX, update->reference);
  return KIWI_VT_OK;
}

static kiwi_vt_status kiwi_vt_render_update_end_internal(kiwi_vt_render_update *update, uint32_t consume_damage);

static kiwi_vt_status kiwi_vt_copy_top_string(kiwi_vt_terminal *terminal, char *buffer, size_t buffer_size, size_t *required) {
  kiwi_lua_api *lua = &terminal->lua;
  size_t length = 0;
  const char *value = lua->lua_tolstring(terminal->state, -1, &length);
  if (value == NULL || length == SIZE_MAX) {
    kiwi_vt_set_error(terminal, "libkiwi-vt returned a non-string result");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  size_t needed = length + 1;
  if (required != NULL) *required = needed;
  if (buffer == NULL || buffer_size < needed) {
    if (buffer != NULL && buffer_size > 0) buffer[0] = '\0';
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, value, length);
  buffer[length] = '\0';
  kiwi_vt_reset_stack(terminal);
  return KIWI_VT_OK;
}

static kiwi_vt_status kiwi_vt_copy_top_optional_string(kiwi_vt_terminal *terminal, char *buffer, size_t buffer_size, size_t *required) {
  if (terminal->lua.lua_type(terminal->state, -1) == KIWI_LUA_TNIL) {
    if (required != NULL) *required = 0;
    if (buffer != NULL && buffer_size > 0) buffer[0] = '\0';
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_NOT_FOUND;
  }
  return kiwi_vt_copy_top_string(terminal, buffer, buffer_size, required);
}

static uint32_t kiwi_vt_local_action(const char *value, size_t length) {
#define KIWI_VT_LOCAL_ACTION(name, constant) \
  if (length == sizeof(name) - 1 && memcmp(value, name, sizeof(name) - 1) == 0) return constant
  KIWI_VT_LOCAL_ACTION("copy", KIWI_VT_LOCAL_ACTION_COPY);
  KIWI_VT_LOCAL_ACTION("paste", KIWI_VT_LOCAL_ACTION_PASTE);
  KIWI_VT_LOCAL_ACTION("search_begin", KIWI_VT_LOCAL_ACTION_SEARCH_BEGIN);
  KIWI_VT_LOCAL_ACTION("search_next", KIWI_VT_LOCAL_ACTION_SEARCH_NEXT);
  KIWI_VT_LOCAL_ACTION("search_previous", KIWI_VT_LOCAL_ACTION_SEARCH_PREVIOUS);
  KIWI_VT_LOCAL_ACTION("open_hyperlink", KIWI_VT_LOCAL_ACTION_OPEN_HYPERLINK);
  KIWI_VT_LOCAL_ACTION("scroll_up", KIWI_VT_LOCAL_ACTION_SCROLL_UP);
  KIWI_VT_LOCAL_ACTION("scroll_down", KIWI_VT_LOCAL_ACTION_SCROLL_DOWN);
  KIWI_VT_LOCAL_ACTION("region_previous_prompt", KIWI_VT_LOCAL_ACTION_REGION_PREVIOUS_PROMPT);
  KIWI_VT_LOCAL_ACTION("region_previous_command", KIWI_VT_LOCAL_ACTION_REGION_PREVIOUS_COMMAND);
  KIWI_VT_LOCAL_ACTION("region_previous_output", KIWI_VT_LOCAL_ACTION_REGION_PREVIOUS_OUTPUT);
  KIWI_VT_LOCAL_ACTION("region_next_prompt", KIWI_VT_LOCAL_ACTION_REGION_NEXT_PROMPT);
  KIWI_VT_LOCAL_ACTION("region_next_command", KIWI_VT_LOCAL_ACTION_REGION_NEXT_COMMAND);
  KIWI_VT_LOCAL_ACTION("region_next_output", KIWI_VT_LOCAL_ACTION_REGION_NEXT_OUTPUT);
#undef KIWI_VT_LOCAL_ACTION
  return KIWI_VT_LOCAL_ACTION_NONE;
}

static uint32_t kiwi_vt_effect_kind(const char *value, size_t length) {
#define KIWI_VT_EFFECT_KIND(name, constant) \
  if (length == sizeof(name) - 1 && memcmp(value, name, sizeof(name) - 1) == 0) return constant
  KIWI_VT_EFFECT_KIND("write_pty", KIWI_VT_EFFECT_WRITE_PTY);
  KIWI_VT_EFFECT_KIND("bell", KIWI_VT_EFFECT_BELL);
  KIWI_VT_EFFECT_KIND("title_changed", KIWI_VT_EFFECT_TITLE_CHANGED);
  KIWI_VT_EFFECT_KIND("pwd_changed", KIWI_VT_EFFECT_PWD_CHANGED);
  KIWI_VT_EFFECT_KIND("shell_marker", KIWI_VT_EFFECT_SHELL_MARKER);
  KIWI_VT_EFFECT_KIND("unknown_sequence", KIWI_VT_EFFECT_UNKNOWN_SEQUENCE);
  KIWI_VT_EFFECT_KIND("palette_changed", KIWI_VT_EFFECT_PALETTE_CHANGED);
  KIWI_VT_EFFECT_KIND("cursor_color_changed", KIWI_VT_EFFECT_CURSOR_COLOR_CHANGED);
  KIWI_VT_EFFECT_KIND("clipboard_write_denied", KIWI_VT_EFFECT_CLIPBOARD_WRITE_DENIED);
  KIWI_VT_EFFECT_KIND("clipboard_write_requested", KIWI_VT_EFFECT_CLIPBOARD_WRITE_REQUESTED);
  KIWI_VT_EFFECT_KIND("progress_changed", KIWI_VT_EFFECT_PROGRESS_CHANGED);
  KIWI_VT_EFFECT_KIND("notification_requested", KIWI_VT_EFFECT_NOTIFICATION_REQUESTED);
  KIWI_VT_EFFECT_KIND("clipboard_read_denied", KIWI_VT_EFFECT_CLIPBOARD_READ_DENIED);
  KIWI_VT_EFFECT_KIND("clipboard_read_requested", KIWI_VT_EFFECT_CLIPBOARD_READ_REQUESTED);
  KIWI_VT_EFFECT_KIND("pointer_shape_changed", KIWI_VT_EFFECT_POINTER_SHAPE_CHANGED);
#undef KIWI_VT_EFFECT_KIND
  return KIWI_VT_EFFECT_OTHER;
}

static kiwi_vt_status kiwi_vt_cache_response(kiwi_vt_terminal *terminal) {
  kiwi_lua_api *lua = &terminal->lua;
  if (lua->lua_type(terminal->state, -1) == KIWI_LUA_TNIL) {
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_NOT_FOUND;
  }
  size_t length = 0;
  const char *value = lua->lua_tolstring(terminal->state, -1, &length);
  if (value == NULL || length == SIZE_MAX) {
    kiwi_vt_set_error(terminal, "libkiwi-vt returned a non-string terminal response");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  char *copy = malloc(length + 1);
  if (copy == NULL) {
    kiwi_vt_set_error(terminal, "out of memory while copying a terminal response");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_OUT_OF_MEMORY;
  }
  memcpy(copy, value, length);
  copy[length] = '\0';
  terminal->response = copy;
  terminal->response_length = length;
  kiwi_vt_reset_stack(terminal);
  return KIWI_VT_OK;
}

static kiwi_vt_status kiwi_vt_cache_effect(kiwi_vt_terminal *terminal) {
  kiwi_lua_api *lua = &terminal->lua;
  if (lua->lua_type(terminal->state, -2) == KIWI_LUA_TNIL) {
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_NOT_FOUND;
  }
  if (lua->lua_type(terminal->state, -2) != KIWI_LUA_TSTRING || lua->lua_type(terminal->state, -1) != KIWI_LUA_TSTRING) {
    kiwi_vt_set_error(terminal, "libkiwi-vt returned an invalid terminal effect");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  size_t kind_length = 0;
  size_t payload_length = 0;
  const char *kind = lua->lua_tolstring(terminal->state, -2, &kind_length);
  const char *payload = lua->lua_tolstring(terminal->state, -1, &payload_length);
  if (kind == NULL || payload == NULL || payload_length == SIZE_MAX) {
    kiwi_vt_set_error(terminal, "libkiwi-vt returned an invalid terminal effect payload");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  char *copy = malloc(payload_length + 1);
  if (copy == NULL) {
    kiwi_vt_set_error(terminal, "out of memory while copying a terminal effect");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_OUT_OF_MEMORY;
  }
  memcpy(copy, payload, payload_length);
  copy[payload_length] = '\0';
  terminal->effect = copy;
  terminal->effect_length = payload_length;
  terminal->effect_kind = kiwi_vt_effect_kind(kind, kind_length);
  kiwi_vt_reset_stack(terminal);
  return KIWI_VT_OK;
}

uint32_t kiwi_vt_api_version(void) {
  return KIWI_VT_API_VERSION;
}

const char *kiwi_vt_version(void) {
  return KIWI_VT_VERSION;
}

const char *kiwi_vt_last_error(void) {
  return kiwi_vt_global_error;
}

kiwi_vt_status kiwi_vt_terminal_new(const kiwi_vt_options *options, kiwi_vt_terminal **out_terminal) {
  if (out_terminal == NULL || options == NULL || options->struct_size < sizeof(*options)) {
    kiwi_vt_set_error(NULL, "terminal options or output pointer are invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  *out_terminal = NULL;
  if (options->api_version != KIWI_VT_API_VERSION) {
    kiwi_vt_set_error(NULL, "unsupported libkiwi-vt API version %u", options->api_version);
    return KIWI_VT_UNSUPPORTED_VERSION;
  }
  if (options->columns == 0 || options->columns > KIWI_VT_MAX_COLUMNS || options->rows == 0 || options->rows > KIWI_VT_MAX_ROWS || options->scrollback_limit > KIWI_VT_MAX_SCROLLBACK || options->keyboard_supported_flags > 31u || options->osc52_read > 1u) {
    kiwi_vt_set_error(NULL, "terminal options exceed the C API bounds");
    return KIWI_VT_INVALID_ARGUMENT;
  }

  kiwi_vt_terminal *terminal = calloc(1, sizeof(*terminal));
  if (terminal == NULL) {
    kiwi_vt_set_error(NULL, "out of memory while allocating a terminal handle");
    return KIWI_VT_OUT_OF_MEMORY;
  }
  if (!kiwi_vt_load_lua(terminal)) {
    kiwi_vt_set_error(NULL, "%s", terminal->error);
    kiwi_vt_terminal_free(terminal);
    return KIWI_VT_LUA_UNAVAILABLE;
  }
  terminal->state = terminal->lua.luaL_newstate();
  if (terminal->state == NULL) {
    kiwi_vt_set_error(terminal, "LuaJIT could not allocate a state");
    kiwi_vt_set_error(NULL, "%s", terminal->error);
    kiwi_vt_terminal_free(terminal);
    return KIWI_VT_OUT_OF_MEMORY;
  }
  terminal->lua.luaL_openlibs(terminal->state);
  if (!kiwi_vt_configure_package_path(terminal)) {
    kiwi_vt_set_error(NULL, "%s", terminal->error);
    kiwi_vt_terminal_free(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  if (terminal->lua.luaL_loadstring(terminal->state, kiwi_vt_bootstrap) != KIWI_LUA_OK || kiwi_vt_pcall(terminal, 0, 0) != KIWI_VT_OK) {
    if (terminal->error[0] == '\0') kiwi_vt_copy_lua_error(terminal, "libkiwi-vt bootstrap failed");
    kiwi_vt_set_error(NULL, "%s", terminal->error);
    kiwi_vt_terminal_free(terminal);
    return KIWI_VT_LUA_ERROR;
  }

  kiwi_vt_status status = kiwi_vt_push_method(terminal, "new");
  if (status == KIWI_VT_OK) {
    terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)options->columns);
    terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)options->rows);
    terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)(options->scrollback_limit == 0 ? KIWI_VT_DEFAULT_SCROLLBACK : options->scrollback_limit));
    terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)options->keyboard_supported_flags);
    terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)options->osc52_read);
    status = kiwi_vt_pcall(terminal, 5, 1);
  }
  if (status != KIWI_VT_OK || terminal->lua.lua_type(terminal->state, -1) != KIWI_LUA_TTABLE) {
    if (status == KIWI_VT_OK) kiwi_vt_set_error(terminal, "libkiwi-vt constructor returned an invalid terminal");
    kiwi_vt_set_error(NULL, "%s", terminal->error);
    kiwi_vt_terminal_free(terminal);
    return status == KIWI_VT_OK ? KIWI_VT_LUA_ERROR : status;
  }
  terminal->reference = terminal->lua.luaL_ref(terminal->state, KIWI_LUA_REGISTRYINDEX);
  kiwi_vt_reset_stack(terminal);
  *out_terminal = terminal;
  return KIWI_VT_OK;
}

void kiwi_vt_terminal_free(kiwi_vt_terminal *terminal) {
  if (terminal == NULL) return;
  if (terminal->active_update != NULL) (void)kiwi_vt_render_update_end_internal(terminal->active_update, 0);
  while (terminal->mice != NULL) kiwi_vt_mouse_free(terminal->mice);
  if (terminal->state != NULL) {
    if (terminal->reference != 0) {
      if (kiwi_vt_push_terminal_method(terminal, "close") == KIWI_VT_OK) (void)kiwi_vt_pcall(terminal, 1, 0);
      terminal->lua.luaL_unref(terminal->state, KIWI_LUA_REGISTRYINDEX, terminal->reference);
    }
    terminal->lua.lua_close(terminal->state);
  }
  if (terminal->lua.library != NULL) dlclose(terminal->lua.library);
  free(terminal->effect);
  free(terminal->response);
  free(terminal);
}

kiwi_vt_status kiwi_vt_terminal_write(kiwi_vt_terminal *terminal, const void *bytes, size_t byte_count, size_t *consumed) {
  if (consumed != NULL) *consumed = 0;
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  if (bytes == NULL && byte_count != 0) {
    kiwi_vt_set_error(terminal, "terminal input bytes are invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_terminal_method(terminal, "write");
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushlstring(terminal->state, bytes == NULL ? "" : bytes, byte_count);
  status = kiwi_vt_pcall(terminal, 2, 1);
  if (status != KIWI_VT_OK) return status;
  if (terminal->lua.lua_type(terminal->state, -1) != KIWI_LUA_TNUMBER) {
    kiwi_vt_set_error(terminal, "libkiwi-vt write returned an invalid byte count");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  if (consumed != NULL) *consumed = byte_count;
  kiwi_vt_reset_stack(terminal);
  return KIWI_VT_OK;
}

kiwi_vt_status kiwi_vt_terminal_finish(kiwi_vt_terminal *terminal) {
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_push_terminal_method(terminal, "finish");
  if (status != KIWI_VT_OK) return status;
  return kiwi_vt_pcall(terminal, 1, 0);
}

kiwi_vt_status kiwi_vt_terminal_resize(kiwi_vt_terminal *terminal, uint32_t columns, uint32_t rows) {
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  if (columns == 0 || columns > KIWI_VT_MAX_COLUMNS || rows == 0 || rows > KIWI_VT_MAX_ROWS) {
    kiwi_vt_set_error(terminal, "terminal dimensions exceed the C API bounds");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_terminal_method(terminal, "resize");
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)columns);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)rows);
  return kiwi_vt_pcall(terminal, 3, 0);
}

kiwi_vt_status kiwi_vt_terminal_set_cell_metrics(kiwi_vt_terminal *terminal, uint32_t width, uint32_t height) {
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  if (width == 0 || width > UINT16_MAX || height == 0 || height > UINT16_MAX) {
    kiwi_vt_set_error(terminal, "terminal cell metrics must be positive and no greater than 65535");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_terminal_method(terminal, "set_cell_metrics");
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)width);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)height);
  return kiwi_vt_pcall(terminal, 3, 0);
}

kiwi_vt_status kiwi_vt_terminal_input_modes(kiwi_vt_terminal *terminal, kiwi_vt_input_modes *modes) {
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  if (modes == NULL || modes->struct_size < sizeof(*modes)) {
    kiwi_vt_set_error(terminal, "input mode output is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_terminal_method(terminal, "input_modes");
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_pcall(terminal, 1, 11);
  if (status != KIWI_VT_OK) return status;
  for (int index = -11; index <= -1; ++index) {
    if (terminal->lua.lua_type(terminal->state, index) != KIWI_LUA_TNUMBER) {
      kiwi_vt_set_error(terminal, "libkiwi-vt input mode query returned an invalid field");
      kiwi_vt_reset_stack(terminal);
      return KIWI_VT_LUA_ERROR;
    }
  }
  modes->application_cursor = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -11);
  modes->bracketed_paste = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -10);
  modes->focus_reporting = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -9);
  modes->keyboard_flags = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -8);
  modes->mouse_protocol = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -7);
  modes->mouse_tracking = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -6);
  modes->alternate_screen = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -5);
  modes->alternate_scroll = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -4);
  modes->application_keypad = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -3);
  modes->backarrow = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -2);
  modes->mouse_shift_escape = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -1);
  kiwi_vt_reset_stack(terminal);
  return KIWI_VT_OK;
}

kiwi_vt_status kiwi_vt_terminal_text(kiwi_vt_terminal *terminal, char *buffer, size_t buffer_size, size_t *required) {
  if (required != NULL) *required = 0;
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_push_terminal_method(terminal, "text");
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_pcall(terminal, 1, 1);
  if (status != KIWI_VT_OK) return status;
  return kiwi_vt_copy_top_string(terminal, buffer, buffer_size, required);
}

kiwi_vt_status kiwi_vt_terminal_take_response(kiwi_vt_terminal *terminal, char *buffer, size_t buffer_size, size_t *required) {
  if (required != NULL) *required = 0;
  kiwi_vt_status idle_status = kiwi_vt_require_idle(terminal);
  if (idle_status != KIWI_VT_OK) return idle_status;
  if (terminal->response == NULL) {
    kiwi_vt_status status = kiwi_vt_push_terminal_method(terminal, "response");
    if (status != KIWI_VT_OK) return status;
    status = kiwi_vt_pcall(terminal, 1, 1);
    if (status != KIWI_VT_OK) return status;
    status = kiwi_vt_cache_response(terminal);
    if (status != KIWI_VT_OK) {
      if (buffer != NULL && buffer_size > 0) buffer[0] = '\0';
      return status;
    }
  }
  size_t needed = terminal->response_length + 1;
  if (required != NULL) *required = needed;
  if (buffer == NULL || buffer_size < needed) {
    if (buffer != NULL && buffer_size > 0) buffer[0] = '\0';
    return KIWI_VT_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, terminal->response, needed);
  free(terminal->response);
  terminal->response = NULL;
  terminal->response_length = 0;
  return KIWI_VT_OK;
}

kiwi_vt_status kiwi_vt_terminal_take_effect(kiwi_vt_terminal *terminal, kiwi_vt_effect *effect, char *payload, size_t payload_size, size_t *payload_required) {
  if (payload_required != NULL) *payload_required = 0;
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  if (effect == NULL || effect->struct_size < sizeof(*effect)) {
    kiwi_vt_set_error(terminal, "terminal effect output is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  if (terminal->effect == NULL) {
    status = kiwi_vt_push_terminal_method(terminal, "effect");
    if (status != KIWI_VT_OK) return status;
    status = kiwi_vt_pcall(terminal, 1, 2);
    if (status != KIWI_VT_OK) return status;
    status = kiwi_vt_cache_effect(terminal);
    if (status != KIWI_VT_OK) {
      if (payload != NULL && payload_size > 0) payload[0] = '\0';
      return status;
    }
  }
  effect->kind = terminal->effect_kind;
  size_t needed = terminal->effect_length + 1;
  if (payload_required != NULL) *payload_required = needed;
  if (payload == NULL || payload_size < needed) {
    if (payload != NULL && payload_size > 0) payload[0] = '\0';
    return KIWI_VT_BUFFER_TOO_SMALL;
  }
  memcpy(payload, terminal->effect, needed);
  free(terminal->effect);
  terminal->effect = NULL;
  terminal->effect_length = 0;
  terminal->effect_kind = 0;
  return KIWI_VT_OK;
}

kiwi_vt_status kiwi_vt_terminal_encode_text(kiwi_vt_terminal *terminal, uint32_t codepoint, char *buffer, size_t buffer_size, size_t *required) {
  if (required != NULL) *required = 0;
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  if (codepoint > 0x10ffffu) {
    kiwi_vt_set_error(terminal, "input codepoint exceeds the Unicode range");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_terminal_method(terminal, "input_text");
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)codepoint);
  status = kiwi_vt_pcall(terminal, 2, 1);
  if (status != KIWI_VT_OK) return status;
  return kiwi_vt_copy_top_optional_string(terminal, buffer, buffer_size, required);
}

kiwi_vt_status kiwi_vt_terminal_encode_paste(kiwi_vt_terminal *terminal, const void *bytes, size_t byte_count, char *buffer, size_t buffer_size, size_t *required) {
  if (required != NULL) *required = 0;
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  if (bytes == NULL && byte_count != 0) {
    kiwi_vt_set_error(terminal, "paste input bytes are invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_terminal_method(terminal, "input_paste");
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushlstring(terminal->state, bytes == NULL ? "" : bytes, byte_count);
  status = kiwi_vt_pcall(terminal, 2, 1);
  if (status != KIWI_VT_OK) return status;
  return kiwi_vt_copy_top_string(terminal, buffer, buffer_size, required);
}

static const char *kiwi_vt_key_action_name(uint32_t action) {
  switch (action) {
    case KIWI_VT_KEY_ACTION_RELEASE: return "release";
    case KIWI_VT_KEY_ACTION_PRESS: return "press";
    case KIWI_VT_KEY_ACTION_REPEAT: return "repeat";
    default: return NULL;
  }
}

static bool kiwi_vt_key_variant_is_valid(uint32_t codepoint) {
  return codepoint == 0 || (codepoint >= 0x20u && codepoint <= 0x10ffffu && (codepoint < 0x7fu || codepoint > 0x9fu) && (codepoint < 0xd800u || codepoint > 0xdfffu));
}

static bool kiwi_vt_key_event_has(const kiwi_vt_key_event *event, size_t offset, size_t field_size) {
  return event->struct_size >= offset + field_size;
}

kiwi_vt_status kiwi_vt_terminal_encode_key(kiwi_vt_terminal *terminal, const kiwi_vt_key_event *event, kiwi_vt_input_result *result, char *buffer, size_t buffer_size, size_t *required) {
  if (required != NULL) *required = 0;
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  if (event == NULL || event->struct_size < offsetof(kiwi_vt_key_event, associated_text) || result == NULL || result->struct_size < sizeof(*result)) {
    kiwi_vt_set_error(terminal, "key event or input result is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  const char *action = kiwi_vt_key_action_name(event->action);
  if (action == NULL) {
    kiwi_vt_set_error(terminal, "key action is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  result->local_action = KIWI_VT_LOCAL_ACTION_NONE;
  result->suppress_text = 0;
  const uint32_t *associated_text = NULL;
  uint32_t associated_text_count = 0;
  if (kiwi_vt_key_event_has(event, offsetof(kiwi_vt_key_event, associated_text_count), sizeof(event->associated_text_count))) {
    associated_text = event->associated_text;
    associated_text_count = event->associated_text_count;
  }
  if ((associated_text == NULL && associated_text_count != 0) || associated_text_count > 64) {
    kiwi_vt_set_error(terminal, "associated key text is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  for (uint32_t index = 0; index < associated_text_count; ++index) {
    uint32_t codepoint = associated_text[index];
    if (codepoint < 0x20u || codepoint > 0x10ffffu || (codepoint >= 0xd800u && codepoint <= 0xdfffu) || (codepoint >= 0x7fu && codepoint <= 0x9fu)) {
      kiwi_vt_set_error(terminal, "associated key text contains an invalid Unicode scalar");
      return KIWI_VT_INVALID_ARGUMENT;
    }
  }
  uint32_t layout_key = 0;
  uint32_t shifted_key = 0;
  uint32_t base_key = 0;
  uint32_t unicode_key = 0;
  if (kiwi_vt_key_event_has(event, offsetof(kiwi_vt_key_event, base_key), sizeof(event->base_key))) {
    layout_key = event->layout_key;
    shifted_key = event->shifted_key;
    base_key = event->base_key;
  }
  if (kiwi_vt_key_event_has(event, offsetof(kiwi_vt_key_event, unicode_key), sizeof(event->unicode_key))) {
    unicode_key = event->unicode_key;
  }
  if (!kiwi_vt_key_variant_is_valid(layout_key) || !kiwi_vt_key_variant_is_valid(shifted_key) || !kiwi_vt_key_variant_is_valid(base_key) || !kiwi_vt_key_variant_is_valid(unicode_key)) {
    kiwi_vt_set_error(terminal, "key Unicode scalars must be non-control Unicode scalars or zero");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_terminal_method(terminal, "input_key");
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->key);
  terminal->lua.lua_pushlstring(terminal->state, action, strlen(action));
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->modifiers);
  if (associated_text_count != 0) {
    terminal->lua.lua_createtable(terminal->state, (int)associated_text_count, 0);
    for (uint32_t index = 0; index < associated_text_count; ++index) {
      terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)associated_text[index]);
      terminal->lua.lua_rawseti(terminal->state, -2, (int)index + 1);
    }
  } else {
    terminal->lua.lua_pushnil(terminal->state);
  }
  if (layout_key == 0) terminal->lua.lua_pushnil(terminal->state); else terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)layout_key);
  if (shifted_key == 0) terminal->lua.lua_pushnil(terminal->state); else terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)shifted_key);
  if (base_key == 0) terminal->lua.lua_pushnil(terminal->state); else terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)base_key);
  if (unicode_key == 0) terminal->lua.lua_pushnil(terminal->state); else terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)unicode_key);
  status = kiwi_vt_pcall(terminal, 9, 3);
  if (status != KIWI_VT_OK) return status;
  if (terminal->lua.lua_type(terminal->state, -3) != KIWI_LUA_TSTRING || terminal->lua.lua_type(terminal->state, -2) != KIWI_LUA_TNUMBER) {
    kiwi_vt_set_error(terminal, "libkiwi-vt key encoder returned an invalid result");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  size_t action_length = 0;
  const char *action_value = terminal->lua.lua_tolstring(terminal->state, -3, &action_length);
  uint32_t local_action = kiwi_vt_local_action(action_value, action_length);
  if (action_length != 0 && local_action == KIWI_VT_LOCAL_ACTION_NONE) {
    kiwi_vt_set_error(terminal, "libkiwi-vt key encoder returned an unknown local action");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  result->local_action = local_action;
  result->suppress_text = (uint32_t)(terminal->lua.lua_tointeger(terminal->state, -2) != 0);
  status = kiwi_vt_copy_top_optional_string(terminal, buffer, buffer_size, required);
  if (status == KIWI_VT_NOT_FOUND && (result->local_action != KIWI_VT_LOCAL_ACTION_NONE || result->suppress_text != 0)) return KIWI_VT_OK;
  return status;
}

kiwi_vt_status kiwi_vt_mouse_new(kiwi_vt_terminal *terminal, kiwi_vt_mouse **out_mouse) {
  if (out_mouse == NULL) {
    kiwi_vt_set_error(NULL, "mouse output pointer is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  *out_mouse = NULL;
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_push_method(terminal, "new_mouse");
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_pcall(terminal, 0, 1);
  if (status != KIWI_VT_OK) return status;
  if (terminal->lua.lua_type(terminal->state, -1) != KIWI_LUA_TTABLE) {
    kiwi_vt_set_error(terminal, "libkiwi-vt mouse constructor returned an invalid mouse");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  kiwi_vt_mouse *mouse = calloc(1, sizeof(*mouse));
  if (mouse == NULL) {
    kiwi_vt_set_error(terminal, "out of memory while allocating a mouse handle");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_OUT_OF_MEMORY;
  }
  mouse->reference = terminal->lua.luaL_ref(terminal->state, KIWI_LUA_REGISTRYINDEX);
  kiwi_vt_reset_stack(terminal);
  mouse->terminal = terminal;
  mouse->next = terminal->mice;
  terminal->mice = mouse;
  *out_mouse = mouse;
  return KIWI_VT_OK;
}

void kiwi_vt_mouse_free(kiwi_vt_mouse *mouse) {
  if (mouse == NULL) return;
  kiwi_vt_terminal *terminal = mouse->terminal;
  if (terminal != NULL) {
    kiwi_vt_mouse **current = &terminal->mice;
    while (*current != NULL && *current != mouse) current = &(*current)->next;
    if (*current == mouse) *current = mouse->next;
    if (terminal->state != NULL && mouse->reference != 0) terminal->lua.luaL_unref(terminal->state, KIWI_LUA_REGISTRYINDEX, mouse->reference);
  }
  mouse->terminal = NULL;
  free(mouse);
}

static const char *kiwi_vt_mouse_action_name(uint32_t action) {
  switch (action) {
    case KIWI_VT_MOUSE_ACTION_RELEASE: return "release";
    case KIWI_VT_MOUSE_ACTION_PRESS: return "press";
    default: return NULL;
  }
}

kiwi_vt_status kiwi_vt_mouse_encode_button(kiwi_vt_mouse *mouse, const kiwi_vt_mouse_button_event *event, char *buffer, size_t buffer_size, size_t *required) {
  if (required != NULL) *required = 0;
  kiwi_vt_terminal *terminal = NULL;
  kiwi_vt_status status = kiwi_vt_require_mouse(mouse, &terminal);
  if (status != KIWI_VT_OK) return status;
  if (event == NULL || event->struct_size < offsetof(kiwi_vt_mouse_button_event, pixel_x) || event->button > 2) {
    kiwi_vt_set_error(terminal, "mouse button event is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  const char *action = kiwi_vt_mouse_action_name(event->action);
  if (action == NULL) {
    kiwi_vt_set_error(terminal, "mouse button action is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  uint32_t pixel_x = event->struct_size >= sizeof(*event) ? event->pixel_x : 0;
  uint32_t pixel_y = event->struct_size >= sizeof(*event) ? event->pixel_y : 0;
  if ((pixel_x == 0) != (pixel_y == 0)) {
    kiwi_vt_set_error(terminal, "mouse pixel coordinates must be both present or both absent");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_mouse_method(mouse, "input_mouse_button", &terminal);
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->button);
  terminal->lua.lua_pushlstring(terminal->state, action, strlen(action));
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->column);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->row);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->modifiers);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)pixel_x);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)pixel_y);
  status = kiwi_vt_pcall(terminal, 9, 1);
  if (status != KIWI_VT_OK) return status;
  return kiwi_vt_copy_top_optional_string(terminal, buffer, buffer_size, required);
}

kiwi_vt_status kiwi_vt_mouse_encode_motion(kiwi_vt_mouse *mouse, const kiwi_vt_mouse_motion_event *event, char *buffer, size_t buffer_size, size_t *required) {
  if (required != NULL) *required = 0;
  kiwi_vt_terminal *terminal = NULL;
  kiwi_vt_status status = kiwi_vt_require_mouse(mouse, &terminal);
  if (status != KIWI_VT_OK) return status;
  if (event == NULL || event->struct_size < offsetof(kiwi_vt_mouse_motion_event, pixel_x)) {
    kiwi_vt_set_error(terminal, "mouse motion event is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  uint32_t pixel_x = event->struct_size >= sizeof(*event) ? event->pixel_x : 0;
  uint32_t pixel_y = event->struct_size >= sizeof(*event) ? event->pixel_y : 0;
  if ((pixel_x == 0) != (pixel_y == 0)) {
    kiwi_vt_set_error(terminal, "mouse pixel coordinates must be both present or both absent");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_mouse_method(mouse, "input_mouse_motion", &terminal);
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->column);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->row);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->modifiers);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)pixel_x);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)pixel_y);
  status = kiwi_vt_pcall(terminal, 7, 1);
  if (status != KIWI_VT_OK) return status;
  return kiwi_vt_copy_top_optional_string(terminal, buffer, buffer_size, required);
}

kiwi_vt_status kiwi_vt_mouse_encode_wheel(kiwi_vt_mouse *mouse, const kiwi_vt_mouse_wheel_event *event, char *buffer, size_t buffer_size, size_t *required) {
  if (required != NULL) *required = 0;
  kiwi_vt_terminal *terminal = NULL;
  kiwi_vt_status status = kiwi_vt_require_mouse(mouse, &terminal);
  if (status != KIWI_VT_OK) return status;
  if (event == NULL || event->struct_size < offsetof(kiwi_vt_mouse_wheel_event, pixel_x) || !isfinite(event->delta)) {
    kiwi_vt_set_error(terminal, "mouse wheel event is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  uint32_t pixel_x = event->struct_size >= offsetof(kiwi_vt_mouse_wheel_event, horizontal_delta) ? event->pixel_x : 0;
  uint32_t pixel_y = event->struct_size >= offsetof(kiwi_vt_mouse_wheel_event, horizontal_delta) ? event->pixel_y : 0;
  double horizontal_delta = event->struct_size >= sizeof(*event) ? event->horizontal_delta : 0;
  if ((pixel_x == 0) != (pixel_y == 0)) {
    kiwi_vt_set_error(terminal, "mouse pixel coordinates must be both present or both absent");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  if (!isfinite(horizontal_delta)) {
    kiwi_vt_set_error(terminal, "mouse horizontal scroll offset is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  status = kiwi_vt_push_mouse_method(mouse, "input_mouse_wheel", &terminal);
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->column);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->row);
  terminal->lua.lua_pushnumber(terminal->state, event->delta);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)event->modifiers);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)pixel_x);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)pixel_y);
  terminal->lua.lua_pushnumber(terminal->state, horizontal_delta);
  status = kiwi_vt_pcall(terminal, 9, 1);
  if (status != KIWI_VT_OK) return status;
  return kiwi_vt_copy_top_optional_string(terminal, buffer, buffer_size, required);
}

kiwi_vt_status kiwi_vt_mouse_encode_focus(kiwi_vt_mouse *mouse, uint32_t focused, char *buffer, size_t buffer_size, size_t *required) {
  if (required != NULL) *required = 0;
  kiwi_vt_terminal *terminal = NULL;
  kiwi_vt_status status = kiwi_vt_require_mouse(mouse, &terminal);
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_push_mouse_method(mouse, "input_mouse_focus", &terminal);
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushboolean(terminal->state, focused != 0);
  status = kiwi_vt_pcall(terminal, 3, 1);
  if (status != KIWI_VT_OK) return status;
  return kiwi_vt_copy_top_optional_string(terminal, buffer, buffer_size, required);
}

kiwi_vt_status kiwi_vt_terminal_begin_render_update(kiwi_vt_terminal *terminal, kiwi_vt_render_update **out_update) {
  if (out_update == NULL) {
    kiwi_vt_set_error(NULL, "render update output pointer is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }
  *out_update = NULL;
  kiwi_vt_status status = kiwi_vt_require_idle(terminal);
  if (status != KIWI_VT_OK) return status;

  kiwi_vt_render_update *update = calloc(1, sizeof(*update));
  if (update == NULL) {
    kiwi_vt_set_error(terminal, "out of memory while allocating a render update");
    return KIWI_VT_OUT_OF_MEMORY;
  }

  status = kiwi_vt_push_terminal_method(terminal, "begin_render");
  if (status != KIWI_VT_OK) {
    free(update);
    return status;
  }
  status = kiwi_vt_pcall(terminal, 1, 1);
  if (status != KIWI_VT_OK) {
    free(update);
    return status;
  }
  if (terminal->lua.lua_type(terminal->state, -1) != KIWI_LUA_TTABLE) {
    kiwi_vt_set_error(terminal, "libkiwi-vt render update returned an invalid view");
    kiwi_vt_reset_stack(terminal);
    free(update);
    return KIWI_VT_LUA_ERROR;
  }
  update->reference = terminal->lua.luaL_ref(terminal->state, KIWI_LUA_REGISTRYINDEX);
  kiwi_vt_reset_stack(terminal);
  update->terminal = terminal;
  terminal->active_update = update;
  *out_update = update;
  return KIWI_VT_OK;
}

static bool kiwi_vt_render_result_is_number(kiwi_vt_terminal *terminal, int index) {
  return terminal->lua.lua_type(terminal->state, index) == KIWI_LUA_TNUMBER;
}

kiwi_vt_status kiwi_vt_render_update_info(const kiwi_vt_render_update *update, kiwi_vt_render_state *state) {
  kiwi_vt_terminal *terminal = NULL;
  kiwi_vt_status status = kiwi_vt_require_render_update(update, &terminal);
  if (status != KIWI_VT_OK) return status;
  if (state == NULL || state->struct_size < sizeof(*state)) {
    kiwi_vt_set_error(terminal, "render state output is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }

  status = kiwi_vt_push_render_update_method(update, "render_info", &terminal);
  if (status != KIWI_VT_OK) return status;
  status = kiwi_vt_pcall(terminal, 1, 10);
  if (status != KIWI_VT_OK) return status;
  for (int index = -10; index <= -1; ++index) {
    if (!kiwi_vt_render_result_is_number(terminal, index)) {
      kiwi_vt_set_error(terminal, "libkiwi-vt render state returned an invalid field");
      kiwi_vt_reset_stack(terminal);
      return KIWI_VT_LUA_ERROR;
    }
  }
  state->columns = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -10);
  state->rows = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -9);
  state->active_screen = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -8);
  state->cursor_column = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -7);
  state->cursor_row = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -6);
  state->cursor_visible = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -5);
  state->cursor_pending_wrap = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -4);
  state->damage_cells = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -3);
  state->damage_full = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -2);
  state->generation = (uint64_t)terminal->lua.lua_tointeger(terminal->state, -1);
  kiwi_vt_reset_stack(terminal);
  return KIWI_VT_OK;
}

kiwi_vt_status kiwi_vt_render_update_cell(const kiwi_vt_render_update *update, uint32_t column, uint32_t row, kiwi_vt_render_cell *cell, char *display_text, size_t display_text_size, size_t *display_text_required) {
  if (display_text_required != NULL) *display_text_required = 0;
  kiwi_vt_terminal *terminal = NULL;
  kiwi_vt_status status = kiwi_vt_require_render_update(update, &terminal);
  if (status != KIWI_VT_OK) return status;
  if (cell == NULL || cell->struct_size < sizeof(*cell)) {
    kiwi_vt_set_error(terminal, "render cell output is invalid");
    return KIWI_VT_INVALID_ARGUMENT;
  }

  status = kiwi_vt_push_render_update_method(update, "render_cell", &terminal);
  if (status != KIWI_VT_OK) return status;
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)column);
  terminal->lua.lua_pushinteger(terminal->state, (ptrdiff_t)row);
  status = kiwi_vt_pcall(terminal, 3, 7);
  if (status != KIWI_VT_OK) return status;
  for (int index = -7; index <= -2; ++index) {
    if (!kiwi_vt_render_result_is_number(terminal, index)) {
      kiwi_vt_set_error(terminal, "libkiwi-vt render cell returned an invalid field");
      kiwi_vt_reset_stack(terminal);
      return KIWI_VT_LUA_ERROR;
    }
  }
  if (terminal->lua.lua_type(terminal->state, -1) != KIWI_LUA_TSTRING) {
    kiwi_vt_set_error(terminal, "libkiwi-vt render cell returned invalid display text");
    kiwi_vt_reset_stack(terminal);
    return KIWI_VT_LUA_ERROR;
  }
  cell->column = column;
  cell->row = row;
  cell->anchor_column = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -7);
  cell->width = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -6);
  cell->flags = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -5);
  cell->foreground = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -4);
  cell->background = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -3);
  cell->continuation = (uint32_t)terminal->lua.lua_tointeger(terminal->state, -2);
  return kiwi_vt_copy_top_string(terminal, display_text, display_text_size, display_text_required);
}

static kiwi_vt_status kiwi_vt_render_update_end_internal(kiwi_vt_render_update *update, uint32_t consume_damage) {
  kiwi_vt_terminal *terminal = NULL;
  kiwi_vt_status status = kiwi_vt_require_render_update(update, &terminal);
  if (status != KIWI_VT_OK) return status;

  status = kiwi_vt_push_terminal_method(terminal, "end_render");
  if (status == KIWI_VT_OK) {
    terminal->lua.lua_pushboolean(terminal->state, consume_damage != 0);
    status = kiwi_vt_pcall(terminal, 2, 0);
  }
  terminal->lua.luaL_unref(terminal->state, KIWI_LUA_REGISTRYINDEX, update->reference);
  kiwi_vt_reset_stack(terminal);
  terminal->active_update = NULL;
  update->terminal = NULL;
  free(update);
  return status;
}

kiwi_vt_status kiwi_vt_render_update_end(kiwi_vt_render_update *update, uint32_t consume_damage) {
  return kiwi_vt_render_update_end_internal(update, consume_damage);
}

const char *kiwi_vt_terminal_last_error(const kiwi_vt_terminal *terminal) {
  return terminal == NULL ? "invalid libkiwi-vt terminal" : terminal->error;
}
