local ffi = require("ffi")

ffi.cdef[[
typedef struct KiwiGtkHost KiwiGtkHost;
typedef uint32_t (*KiwiGtkKeyCallback)(void* userdata, uint32_t keyval, uint32_t modifiers, int action);
typedef void (*KiwiGtkTextCallback)(void* userdata, const char* text, size_t text_bytes);
typedef void (*KiwiGtkPreeditCallback)(void* userdata, const char* text, size_t text_bytes, uint32_t cursor_begin, uint32_t cursor_end);
typedef void (*KiwiGtkPointerCallback)(void* userdata, int kind, double x, double y, double dx, double dy, uint32_t button, int action, uint32_t modifiers);
typedef void (*KiwiGtkFocusCallback)(void* userdata, int focused);
typedef void (*KiwiGtkResizeCallback)(void* userdata, int width, int height, double scale);
typedef void (*KiwiGtkProductActionCallback)(void* userdata, uint32_t action);
typedef struct KiwiGtkCommandPaletteEntry { uint32_t action; const char* title; const char* description; } KiwiGtkCommandPaletteEntry;
typedef struct KiwiGtkCallbacks {
  KiwiGtkFocusCallback focus;
  KiwiGtkKeyCallback key;
  KiwiGtkPointerCallback pointer;
  KiwiGtkResizeCallback resize;
  KiwiGtkTextCallback text;
  KiwiGtkPreeditCallback preedit;
  void* userdata;
} KiwiGtkCallbacks;
KiwiGtkHost* kiwi_gtk_host_new(const char* application_id, int width, int height, const char* title, const KiwiGtkCallbacks* callbacks);
void kiwi_gtk_host_destroy(KiwiGtkHost* host);
int kiwi_gtk_host_set_product_action_handler(KiwiGtkHost* host, KiwiGtkProductActionCallback callback, void* userdata);
int kiwi_gtk_host_product_action_invoke_smoke(KiwiGtkHost* host, uint32_t action);
int kiwi_gtk_host_command_palette_show(KiwiGtkHost* host, const KiwiGtkCommandPaletteEntry* entries, size_t count, KiwiGtkProductActionCallback callback, void* userdata);
void kiwi_gtk_host_command_palette_remove(KiwiGtkHost* host);
int kiwi_gtk_host_command_palette_invoke_smoke(KiwiGtkHost* host);
void kiwi_gtk_host_pump(KiwiGtkHost* host, uint32_t timeout_milliseconds);
int kiwi_gtk_host_should_close(const KiwiGtkHost* host);
double kiwi_gtk_host_time(void);
void kiwi_gtk_host_request_close(KiwiGtkHost* host);
void kiwi_gtk_host_set_title(KiwiGtkHost* host, const char* title);
void kiwi_gtk_host_drawable_size(const KiwiGtkHost* host, int* width, int* height);
double kiwi_gtk_host_content_scale(const KiwiGtkHost* host);
void kiwi_gtk_host_set_size(KiwiGtkHost* host, int width, int height);
int kiwi_gtk_host_clipboard_write(KiwiGtkHost* host, const char* text);
int kiwi_gtk_host_clipboard_read(KiwiGtkHost* host, char* destination, size_t capacity, size_t* text_bytes);
int kiwi_gtk_host_notify(KiwiGtkHost* host, const char* title, const char* body);
int kiwi_gtk_host_open_uri(KiwiGtkHost* host, const char* uri);
int kiwi_gtk_host_open_text_file(KiwiGtkHost* host, const char* path);
void* kiwi_gtk_host_create_surface(void* instance, KiwiGtkHost* host);
int kiwi_gtk_host_set_drawable_size(KiwiGtkHost* host, uint32_t width, uint32_t height);
int kiwi_gtk_host_set_text_input_caret(KiwiGtkHost* host, int x, int y, int width, int height);
int kiwi_gtk_host_system_appearance(const KiwiGtkHost* host);
int kiwi_gtk_host_text_input_inject_smoke(KiwiGtkHost* host);
int kiwi_gtk_host_key_text_inject_smoke(KiwiGtkHost* host);
int kiwi_gtk_host_accessibility_update(KiwiGtkHost* host, const char* text, size_t text_bytes, uint32_t character_count, int32_t caret_offset, int32_t selection_start, int32_t selection_end, int focused, const char* title);
const char* kiwi_gtk_host_last_error(void);
]]

local root = os.getenv("KIWI_ROOT") or "."
local loaded, native = pcall(ffi.load, os.getenv("KIWI_GTK_HOST_LIB") or root .. "/.build/native/libkiwi_gtk_host.so")
if not loaded then error("Unable to load the Kiwi GTK host bridge; run make gtk-host: " .. tostring(native)) end

local glfw = require("kiwi.ffi.glfw").constants
local Correlation = require("kiwi.input.correlation")
local Utf8 = require("kiwi.terminal.utf8")
local Window = {}
Window.__index = Window
Window.bridge = native
local live_windows = 0

local product_actions = {
  [1] = "new-tab",
  [2] = "new-window",
  [3] = "next-tab",
  [4] = "close-pane",
  [5] = "split-right",
  [6] = "split-down",
  [7] = "reload-config",
  [8] = "move-session-new-window",
  [9] = "move-session-next-window",
  [10] = "duplicate-session-new-window",
  [11] = "duplicate-session-next-window",
  [12] = "command-palette",
  [13] = "open-configuration",
}
local product_action_ids = {}
for identifier, name in pairs(product_actions) do product_action_ids[name] = identifier end

local special_keys = {
  [0xff08] = glfw.key_backspace,
  [0xff09] = glfw.key_tab,
  [0xff0d] = glfw.key_enter,
  [0xff1b] = glfw.key_escape,
  [0xff50] = glfw.key_home,
  [0xff51] = glfw.key_left,
  [0xff52] = glfw.key_up,
  [0xff53] = glfw.key_right,
  [0xff54] = glfw.key_down,
  [0xff55] = glfw.key_page_up,
  [0xff56] = glfw.key_page_down,
  [0xff57] = glfw.key_end,
  [0xff63] = glfw.key_insert,
  [0xffff] = glfw.key_delete,
}
for offset = 0, 11 do special_keys[0xffbe + offset] = glfw.key_f1 + offset end

local function key_from_gdk(keyval)
  return special_keys[keyval] or keyval
end

local function callback_flags(result)
  if type(result) ~= "table" then return 0 end
  local flags = result.handled and not result.defer_text and 1 or 0
  if result.suppress_text then flags = flags + 2 end
  if result.defer_text then flags = flags + 4 end
  return flags
end

local function codepoints_from_utf8(text)
  local codepoints = {}
  local invalid = false
  local decoder = Utf8.Decoder.new(function(codepoint, _, replaced)
    if replaced then invalid = true else codepoints[#codepoints + 1] = codepoint end
  end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  return invalid and nil or codepoints
end

local function callback_text(pointer, bytes)
  if pointer == nil then return "" end
  return ffi.string(pointer, tonumber(bytes))
end

function Window.new(width, height, title)
  assert(type(width) == "number" and width >= 1 and width % 1 == 0, "GTK window width must be a positive integer")
  assert(type(height) == "number" and height >= 1 and height % 1 == 0, "GTK window height must be a positive integer")
  local self = setmetatable({ callbacks = {}, height = height, minimized = false, resized = true, width = width }, Window)
  self.input_correlation = Correlation.new(function(codepoints, event)
    if self.on_text then self.on_text(codepoints, event) end
  end)
  self.callbacks.key = ffi.cast("KiwiGtkKeyCallback", function(_, keyval, modifiers, action)
    self.input_correlation:flush()
    if self.on_key == nil then return 0 end
    local key = key_from_gdk(tonumber(keyval))
    local key_action = tonumber(action) == 1 and glfw.press or glfw.release
    local input = self.on_key(key, key_action, tonumber(modifiers))
    if input and input.defer_text then
      self.input_correlation:defer({ key = key, action = key_action, modifiers = tonumber(modifiers) })
    end
    return callback_flags(input)
  end)
  self.callbacks.text = ffi.cast("KiwiGtkTextCallback", function(_, text, text_bytes)
    local committed = callback_text(text, text_bytes)
    local codepoints = codepoints_from_utf8(committed)
    local correlated = codepoints ~= nil and #codepoints > 0
    if correlated then
      for _, codepoint in ipairs(codepoints) do
        if not self.input_correlation:text(codepoint) then
          correlated = false
          break
        end
      end
    end
    if correlated then return end
    if self.on_commit then
      self.on_commit(committed)
    elseif self.on_text then
      if codepoints then self.on_text(codepoints, nil) end
    end
  end)
  self.callbacks.preedit = ffi.cast("KiwiGtkPreeditCallback", function(_, text, text_bytes, cursor_begin, cursor_end)
    if self.on_preedit then
      self.on_preedit(callback_text(text, text_bytes), tonumber(cursor_begin), tonumber(cursor_end))
    end
  end)
  self.callbacks.pointer = ffi.cast("KiwiGtkPointerCallback", function(_, kind, x, y, dx, dy, button, action, modifiers)
    if self.on_pointer == nil then return end
    kind = tonumber(kind)
    if kind == 1 then
      self.on_pointer({ kind = "motion", x = x, y = y, modifiers = tonumber(modifiers) })
    elseif kind == 2 then
      self.on_pointer({ kind = "button", x = x, y = y, button = math.max(0, tonumber(button) - 1), action = tonumber(action) == 1 and "press" or "release", modifiers = tonumber(modifiers) })
    elseif kind == 3 then
      self.on_pointer({ kind = "wheel", x = x, y = y, horizontal_delta = dx, delta = dy, modifiers = tonumber(modifiers) })
    end
  end)
  self.callbacks.focus = ffi.cast("KiwiGtkFocusCallback", function(_, focused)
    if self.on_focus then self.on_focus(focused ~= 0) end
  end)
  self.callbacks.resize = ffi.cast("KiwiGtkResizeCallback", function(_, resized_width, resized_height, scale)
    self.width, self.height = tonumber(resized_width), tonumber(resized_height)
    self.scale = tonumber(scale)
    self.resized = true
  end)
  local callbacks = ffi.new("KiwiGtkCallbacks")
  callbacks.focus = self.callbacks.focus
  callbacks.key = self.callbacks.key
  callbacks.pointer = self.callbacks.pointer
  callbacks.resize = self.callbacks.resize
  callbacks.text = self.callbacks.text
  callbacks.preedit = self.callbacks.preedit
  self.handle = native.kiwi_gtk_host_new("org.gongahkia.kiwi", width, height, title, callbacks)
  if self.handle == nil then
    self:destroy()
    error("Unable to create GTK window: " .. ffi.string(native.kiwi_gtk_host_last_error()))
  end
  live_windows = live_windows + 1
  return self
end

function Window:set_input_handlers(on_text, on_key, on_pointer, on_focus)
  self.on_text, self.on_key, self.on_pointer, self.on_focus = on_text, on_key, on_pointer, on_focus
end

function Window:enable_text_input(on_preedit, on_commit)
  assert(type(on_preedit) == "function" and type(on_commit) == "function", "GTK text input needs preedit and commit callbacks")
  self.on_preedit, self.on_commit = on_preedit, on_commit
  return true
end

function Window:enable_product_action_handler(handler)
  assert(type(handler) == "function", "GTK product actions need an action handler")
  if self.callbacks.product_action ~= nil then return true end
  self.callbacks.product_action = ffi.cast("KiwiGtkProductActionCallback", function(_, action)
    local name = product_actions[tonumber(action)]
    if name == nil then return end
    local ok, message = pcall(handler, name)
    if not ok then io.stderr:write("Kiwi GTK product action failed: ", tostring(message), "\n") end
  end)
  if native.kiwi_gtk_host_set_product_action_handler(self.handle, self.callbacks.product_action, nil) ~= 0 then return true end
  self.callbacks.product_action:free()
  self.callbacks.product_action = nil
  return false, ffi.string(native.kiwi_gtk_host_last_error())
end

function Window:product_action_invoke_smoke(action)
  local identifier = product_action_ids[action]
  if identifier == nil then return nil, "GTK product-menu smoke names an unknown action" end
  if native.kiwi_gtk_host_product_action_invoke_smoke(self.handle, identifier) ~= 0 then return true end
  return false, ffi.string(native.kiwi_gtk_host_last_error())
end

local function command_palette_entries(entries)
  assert(type(entries) == "table" and #entries > 0 and #entries <= 32, "GTK command palette needs one through 32 entries")
  local values = ffi.new("KiwiGtkCommandPaletteEntry[?]", #entries)
  for index, entry in ipairs(entries) do
    assert(type(entry) == "table", "GTK command palette entry must be a table")
    local action = product_action_ids[entry.action]
    assert(action ~= nil and entry.action ~= "command-palette", "GTK command palette entry names an unavailable action")
    assert(type(entry.title) == "string" and #entry.title > 0 and #entry.title <= 128 and not entry.title:find("\0", 1, true), "GTK command palette title is invalid")
    assert(type(entry.description) == "string" and #entry.description <= 256 and not entry.description:find("\0", 1, true), "GTK command palette description is invalid")
    values[index - 1].action = action
    values[index - 1].title = entry.title
    values[index - 1].description = entry.description
  end
  return values
end

function Window:show_command_palette(entries, handler)
  assert(type(handler) == "function", "GTK command palette needs an action handler")
  local values = command_palette_entries(entries)
  if self.callbacks.command_palette ~= nil then
    native.kiwi_gtk_host_command_palette_remove(self.handle)
    self.callbacks.command_palette:free()
    self.callbacks.command_palette = nil
  end
  local callback = ffi.cast("KiwiGtkProductActionCallback", function(_, action)
    local name = product_actions[tonumber(action)]
    if name == nil or name == "command-palette" then return end
    local ok, message = pcall(handler, name)
    if not ok then io.stderr:write("Kiwi GTK command palette action failed: ", tostring(message), "\n") end
  end)
  if native.kiwi_gtk_host_command_palette_show(self.handle, values, #entries, callback, nil) ~= 0 then
    self.callbacks.command_palette = callback
    return true
  end
  callback:free()
  return false, ffi.string(native.kiwi_gtk_host_last_error())
end

function Window:command_palette_invoke_smoke()
  if native.kiwi_gtk_host_command_palette_invoke_smoke(self.handle) ~= 0 then return true end
  return false, ffi.string(native.kiwi_gtk_host_last_error())
end

function Window:set_text_input_caret(x, y, width, height)
  local result = native.kiwi_gtk_host_set_text_input_caret(self.handle,
    math.floor(x), math.floor(y), math.max(1, math.floor(width)), math.max(1, math.floor(height)))
  if result ~= 0 then return true end
  return false, ffi.string(native.kiwi_gtk_host_last_error())
end

function Window:system_appearance()
  local value = native.kiwi_gtk_host_system_appearance(self.handle)
  if value == 1 then return "dark" end
  if value == 0 then return "light" end
  return nil
end

function Window:text_input_inject_smoke()
  if native.kiwi_gtk_host_text_input_inject_smoke(self.handle) ~= 0 then return true end
  return false, ffi.string(native.kiwi_gtk_host_last_error())
end

function Window:key_text_inject_smoke()
  if native.kiwi_gtk_host_key_text_inject_smoke(self.handle) ~= 0 then return true end
  return false, ffi.string(native.kiwi_gtk_host_last_error())
end

function Window:accessibility_new()
  local window = self
  return {
    update = function(_, projection, title, focused)
      local result = native.kiwi_gtk_host_accessibility_update(window.handle,
        projection.text, #projection.text, projection.character_count,
        projection.caret_offset, projection.selection_start, projection.selection_end,
        focused and 1 or 0, title)
      if result ~= 0 then return true end
      return false, ffi.string(native.kiwi_gtk_host_last_error())
    end,
    poll = function() end,
    destroy = function() end,
  }
end

function Window:clipboard_read(maximum_bytes)
  local buffer = ffi.new("char[?]", maximum_bytes + 1)
  local bytes = ffi.new("size_t[1]")
  local result = native.kiwi_gtk_host_clipboard_read(self.handle, buffer, maximum_bytes, bytes)
  if result == 1 then return ffi.string(buffer, bytes[0]) end
  return nil, result == -1 and "over-limit" or "unavailable"
end

function Window:clipboard_write(text)
  return native.kiwi_gtk_host_clipboard_write(self.handle, text) ~= 0 and true or false, "platform-error"
end

function Window:notify(title, body)
  assert(type(title) == "string" and type(body) == "string", "GTK notification needs strings")
  if native.kiwi_gtk_host_notify(self.handle, title, body) ~= 0 then return true end
  return false, "platform-error"
end

function Window:open_uri(uri)
  return native.kiwi_gtk_host_open_uri(self.handle, uri) ~= 0 and true or false, "platform-error"
end

function Window:open_text_file(path)
  assert(type(path) == "string" and #path > 0 and not path:find("\0", 1, true), "GTK text-file opener needs a non-empty NUL-free path")
  return native.kiwi_gtk_host_open_text_file(self.handle, path) ~= 0 and true or false, "platform-error"
end

function Window:set_title(title) native.kiwi_gtk_host_set_title(self.handle, title) end

function Window:set_size(width, height) native.kiwi_gtk_host_set_size(self.handle, width, height) end

function Window:set_position() end

function Window:geometry() return { height = self.height, width = self.width, x = 0, y = 0 } end

function Window:iconify() self.minimized = true end

function Window:restore() self.minimized = false; self.resized = true end

function Window:drawable_size()
  local width, height = ffi.new("int[1]"), ffi.new("int[1]")
  native.kiwi_gtk_host_drawable_size(self.handle, width, height)
  return width[0], height[0]
end

function Window:content_scale()
  local scale = native.kiwi_gtk_host_content_scale(self.handle)
  return scale, scale
end

function Window:should_close() return native.kiwi_gtk_host_should_close(self.handle) ~= 0 end

function Window:request_close() native.kiwi_gtk_host_request_close(self.handle) end

function Window:take_shader_reload_request() return false end

function Window:time() return native.kiwi_gtk_host_time() end

function Window:poll_events() Window.pump(self, 0) end

function Window:wait_events(timeout) Window.pump(self, timeout) end

function Window:destroy()
  if self.handle ~= nil then
    native.kiwi_gtk_host_destroy(self.handle)
    self.handle = nil
    live_windows = live_windows - 1
  end
  for _, callback in pairs(self.callbacks or {}) do callback:free() end
end

function Window.live_count() return live_windows end

function Window.pump(window, timeout)
  native.kiwi_gtk_host_pump(window.handle, math.max(0, math.floor(timeout * 1000 + 0.5)))
end

function Window.poll_events_for(windows)
  for _, window in ipairs(windows) do Window.pump(window, 0) end
end

function Window.wait_events_for(timeout, windows)
  if windows[1] then Window.pump(windows[1], timeout) end
end

return Window
