local ffi = require("ffi")

ffi.cdef[[
typedef struct KiwiGtkHost KiwiGtkHost;
typedef uint32_t (*KiwiGtkKeyCallback)(void* userdata, uint32_t keyval, uint32_t modifiers, int action);
typedef void (*KiwiGtkTextCallback)(void* userdata, uint32_t codepoint);
typedef void (*KiwiGtkPointerCallback)(void* userdata, int kind, double x, double y, double dx, double dy, uint32_t button, int action, uint32_t modifiers);
typedef void (*KiwiGtkFocusCallback)(void* userdata, int focused);
typedef void (*KiwiGtkResizeCallback)(void* userdata, int width, int height, double scale);
typedef struct KiwiGtkCallbacks {
  KiwiGtkFocusCallback focus;
  KiwiGtkKeyCallback key;
  KiwiGtkPointerCallback pointer;
  KiwiGtkResizeCallback resize;
  KiwiGtkTextCallback text;
  void* userdata;
} KiwiGtkCallbacks;
KiwiGtkHost* kiwi_gtk_host_new(const char* application_id, int width, int height, const char* title, const KiwiGtkCallbacks* callbacks);
void kiwi_gtk_host_destroy(KiwiGtkHost* host);
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
int kiwi_gtk_host_open_uri(KiwiGtkHost* host, const char* uri);
void* kiwi_gtk_host_create_surface(void* instance, KiwiGtkHost* host);
int kiwi_gtk_host_set_drawable_size(KiwiGtkHost* host, uint32_t width, uint32_t height);
const char* kiwi_gtk_host_last_error(void);
]]

local root = os.getenv("KIWI_ROOT") or "."
local loaded, native = pcall(ffi.load, os.getenv("KIWI_GTK_HOST_LIB") or root .. "/.build/native/libkiwi_gtk_host.so")
if not loaded then error("Unable to load the Kiwi GTK host bridge; run make gtk-host: " .. tostring(native)) end

local glfw = require("kiwi.ffi.glfw").constants
local Window = {}
Window.__index = Window
Window.bridge = native

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
  local flags = result.handled and 1 or 0
  if result.suppress_text then flags = flags + 2 end
  return flags
end

function Window.new(width, height, title)
  assert(type(width) == "number" and width >= 1 and width % 1 == 0, "GTK window width must be a positive integer")
  assert(type(height) == "number" and height >= 1 and height % 1 == 0, "GTK window height must be a positive integer")
  local self = setmetatable({ callbacks = {}, height = height, minimized = false, resized = true, width = width }, Window)
  self.callbacks.key = ffi.cast("KiwiGtkKeyCallback", function(_, keyval, modifiers, action)
    if self.on_key == nil then return 0 end
    return callback_flags(self.on_key(key_from_gdk(tonumber(keyval)), tonumber(action) == 1 and glfw.press or glfw.release, tonumber(modifiers)))
  end)
  self.callbacks.text = ffi.cast("KiwiGtkTextCallback", function(_, codepoint)
    if self.on_text then self.on_text({ tonumber(codepoint) }, nil) end
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
  self.handle = native.kiwi_gtk_host_new("org.gongahkia.kiwi", width, height, title, callbacks)
  if self.handle == nil then
    self:destroy()
    error("Unable to create GTK window: " .. ffi.string(native.kiwi_gtk_host_last_error()))
  end
  return self
end

function Window:set_input_handlers(on_text, on_key, on_pointer, on_focus)
  self.on_text, self.on_key, self.on_pointer, self.on_focus = on_text, on_key, on_pointer, on_focus
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

function Window:open_uri(uri)
  return native.kiwi_gtk_host_open_uri(self.handle, uri) ~= 0 and true or false, "platform-error"
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
  if self.handle ~= nil then native.kiwi_gtk_host_destroy(self.handle); self.handle = nil end
  for _, callback in pairs(self.callbacks or {}) do callback:free() end
end

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
