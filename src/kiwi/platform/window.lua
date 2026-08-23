local ffi = require("ffi")
local glfw = require("kiwi.ffi.glfw")
local Correlation = require("kiwi.input.correlation")

ffi.cdef[[
size_t strnlen(const char* text, size_t maximum);
int kiwi_open_uri(const char* uri);
int kiwi_open_text_file(const char* path);
int kiwi_cocoa_private_pasteboard_round_trip(const char* text, size_t text_bytes);
int kiwi_cocoa_accessibility_round_trip(void* window);
typedef struct KiwiCocoaTextInput KiwiCocoaTextInput;
typedef void (*KiwiCocoaTextInputCallback)(void* userdata, const char* text, size_t text_bytes, int32_t selection_start, int32_t selection_end);
typedef void (*KiwiCocoaMenuCallback)(void* userdata, uint32_t action);
typedef int (*KiwiCocoaAutomationCallback)(void* userdata, uint32_t action);
typedef struct KiwiCocoaCommandPaletteEntry { uint32_t action; const char* title; const char* description; } KiwiCocoaCommandPaletteEntry;
KiwiCocoaTextInput* kiwi_cocoa_text_input_new(void* window, KiwiCocoaTextInputCallback preedit, KiwiCocoaTextInputCallback commit, void* userdata);
void kiwi_cocoa_text_input_destroy(KiwiCocoaTextInput* adapter);
void kiwi_cocoa_text_input_set_caret(KiwiCocoaTextInput* adapter, double x, double y, double width, double height);
int kiwi_cocoa_text_input_round_trip(void* window);
int kiwi_cocoa_text_input_inject_smoke(KiwiCocoaTextInput* adapter);
int kiwi_cocoa_system_appearance(void* window);
int kiwi_cocoa_menu_install(void* window, KiwiCocoaMenuCallback callback, void* userdata);
void kiwi_cocoa_menu_remove(void* window);
int kiwi_cocoa_menu_invoke_smoke(void* window, uint32_t action);
int kiwi_cocoa_toolbar_invoke_smoke(void* window, uint32_t action);
int kiwi_cocoa_automation_install(void* window, KiwiCocoaAutomationCallback callback, void* userdata);
void kiwi_cocoa_automation_remove(void* window);
int kiwi_cocoa_automation_invoke_smoke(void* window, uint32_t action);
int kiwi_cocoa_window_tabs_round_trip(void* first, void* second);
void kiwi_cocoa_window_tabs_remove_bridge(void* window);
int kiwi_cocoa_command_palette_show(void* window, const KiwiCocoaCommandPaletteEntry* entries, size_t count, KiwiCocoaMenuCallback callback, void* userdata);
void kiwi_cocoa_command_palette_remove(void* window);
int kiwi_cocoa_command_palette_invoke_smoke(void* window);
int kiwi_cocoa_progress_set(void* window, uint32_t progress, uint32_t state);
int kiwi_cocoa_progress_round_trip(void* window);
void kiwi_cocoa_progress_remove_bridge(void* window);
int kiwi_cocoa_key_variants(int scancode, uint32_t* layout_key, uint32_t* shifted_key);
const char* kiwi_surface_last_error(void);
]]

local root = os.getenv("KIWI_ROOT") or "."
local library_extension = ffi.os == "OSX" and ".dylib" or ".so"
local native_path = os.getenv("KIWI_SURFACE_LIB") or root .. "/.build/native/libkiwi_surface" .. library_extension
local native_ok, native = pcall(ffi.load, native_path)
if not native_ok then error("Unable to load Kiwi native bridge at " .. native_path .. "; run make native: " .. tostring(native)) end

local Window = {}
Window.__index = Window

local live_windows = 0
local cocoa_menu_actions = {
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
local cocoa_menu_action_ids = {}
for identifier, name in pairs(cocoa_menu_actions) do cocoa_menu_action_ids[name] = identifier end

local function glfw_error()
  local code = ffi.new("int[1]")
  local message = glfw.lib.glfwGetError(code)
  if message == nil then
    return string.format("GLFW error %d", code[0])
  end
  return string.format("GLFW error %d: %s", code[0], ffi.string(message))
end

local function pc101_base_key(key)
  if key >= string.byte("A") and key <= string.byte("Z") then return key + 0x20 end
  if key >= 0x20 and key <= 0x7e then return key end
end

function Window.new(width, height, title, options)
  options = options or {}
  assert(options.visible == nil or type(options.visible) == "boolean", "window visibility must be a boolean")
  if live_windows == 0 and glfw.lib.glfwInit() == 0 then
    error("Unable to initialize GLFW: " .. glfw_error())
  end

  glfw.lib.glfwWindowHint(glfw.constants.client_api, glfw.constants.no_api)
  glfw.lib.glfwWindowHint(glfw.constants.resizable, glfw.constants.yes)
  glfw.lib.glfwWindowHint(glfw.constants.visible, options.visible == false and glfw.constants.no or glfw.constants.yes)
  glfw.lib.glfwWindowHint(glfw.constants.scale_framebuffer, glfw.constants.yes)
  local handle = glfw.lib.glfwCreateWindow(width, height, title, nil, nil)
  if handle == nil then
    if live_windows == 0 then glfw.lib.glfwTerminate() end
    error("Unable to create a native GLFW window: " .. glfw_error())
  end
  live_windows = live_windows + 1

  local self = setmetatable({
    handle = handle,
    resized = true,
    minimized = false,
    debug_dirty = false,
    debug_boundaries = false,
    debug_metrics = false,
    shader_reload_requested = false,
    modifiers = 0,
    suppress_text = false,
    release_mode = options.release_mode == true,
    callbacks = {},
  }, Window)
  self.input_correlation = Correlation.new(function(codepoints, event)
    if self.on_text then self.on_text(codepoints, event) end
  end)
  self.callbacks.resize = ffi.cast("GLFWframebuffersizefun", function(_, drawable_width, drawable_height)
    self.resized = true
    self.minimized = drawable_width <= 0 or drawable_height <= 0
  end)
  self.callbacks.key = ffi.cast("GLFWkeyfun", function(_, key, scancode, action, modifiers)
    self.input_correlation:flush()
    self.modifiers = modifiers
    local variants = self:cocoa_key_variants(scancode, key)
    local input = self.on_key and self.on_key(key, action, modifiers, variants)
    if input and input.defer_text then
      self.input_correlation:defer({ key = key, scancode = scancode, action = action, modifiers = modifiers, variants = variants })
      return
    end
    if input and input.suppress_text then self.suppress_text = true end
    if input and input.handled then return end
    if action == glfw.constants.release then self.suppress_text = false end
    if not self.release_mode and action == glfw.constants.press and key == glfw.constants.key_f2 then
      self.debug_dirty = not self.debug_dirty
    elseif not self.release_mode and action == glfw.constants.press and key == glfw.constants.key_f3 then
      self.debug_boundaries = not self.debug_boundaries
    elseif not self.release_mode and action == glfw.constants.press and key == glfw.constants.key_f4 then
      self.debug_metrics = not self.debug_metrics
    elseif not self.release_mode and action == glfw.constants.press and key == glfw.constants.key_f5 then
      self.shader_reload_requested = true
    elseif action == glfw.constants.press and key == glfw.constants.key_escape then
      glfw.lib.glfwSetWindowShouldClose(self.handle, 1)
    end
  end)
  self.callbacks.character = ffi.cast("GLFWcharfun", function(_, codepoint)
    if self.input_correlation:text(codepoint) then return end
    if self.suppress_text then
      self.suppress_text = false
      return
    end
    if self.on_text then self.on_text({ codepoint }, nil) end
  end)
  self.callbacks.cursor_position = ffi.cast("GLFWcursorposfun", function(_, x, y)
    if self.on_pointer then self.on_pointer({ kind = "motion", x = x, y = y, modifiers = self.modifiers }) end
  end)
  self.callbacks.mouse_button = ffi.cast("GLFWmousebuttonfun", function(_, button, action, modifiers)
    self.modifiers = modifiers
    if self.on_pointer then
      local x, y = self:cursor_position()
      self.on_pointer({ kind = "button", button = button, action = action == glfw.constants.press and "press" or action == glfw.constants.release and "release" or "unknown", time = glfw.lib.glfwGetTime(), x = x, y = y, modifiers = modifiers })
    end
  end)
  self.callbacks.scroll = ffi.cast("GLFWscrollfun", function(_, xoffset, yoffset)
    if self.on_pointer then
      local x, y = self:cursor_position()
      self.on_pointer({ kind = "wheel", delta = yoffset, horizontal_delta = xoffset, x = x, y = y, modifiers = self.modifiers })
    end
  end)
  self.callbacks.focus = ffi.cast("GLFWwindowfocusfun", function(_, focused)
    if self.on_focus then self.on_focus(focused ~= 0) end
  end)
  self.callbacks.iconify = ffi.cast("GLFWwindowiconifyfun", function(_, iconified)
    self.minimized = iconified ~= 0
    self.resized = true
  end)
  self.callbacks.content_scale = ffi.cast("GLFWwindowcontentscalefun", function()
    self.resized = true
  end)
  glfw.lib.glfwSetFramebufferSizeCallback(handle, self.callbacks.resize)
  glfw.lib.glfwSetKeyCallback(handle, self.callbacks.key)
  glfw.lib.glfwSetCharCallback(handle, self.callbacks.character)
  glfw.lib.glfwSetCursorPosCallback(handle, self.callbacks.cursor_position)
  glfw.lib.glfwSetMouseButtonCallback(handle, self.callbacks.mouse_button)
  glfw.lib.glfwSetScrollCallback(handle, self.callbacks.scroll)
  glfw.lib.glfwSetWindowFocusCallback(handle, self.callbacks.focus)
  glfw.lib.glfwSetWindowIconifyCallback(handle, self.callbacks.iconify)
  glfw.lib.glfwSetWindowContentScaleCallback(handle, self.callbacks.content_scale)
  return self
end

function Window:set_input_handlers(on_text, on_key, on_pointer, on_focus)
  self.on_text = on_text
  self.on_key = on_key
  self.on_pointer = on_pointer
  self.on_focus = on_focus
end

function Window:cursor_position()
  local x = ffi.new("double[1]")
  local y = ffi.new("double[1]")
  glfw.lib.glfwGetCursorPos(self.handle, x, y)
  return x[0], y[0]
end

function Window:clipboard_read(maximum_bytes)
  assert(type(maximum_bytes) == "number" and maximum_bytes >= 1 and maximum_bytes % 1 == 0, "clipboard read limit must be a positive integer")
  local code = ffi.new("int[1]")
  glfw.lib.glfwGetError(code)
  local value = glfw.lib.glfwGetClipboardString(self.handle)
  local message = glfw.lib.glfwGetError(code)
  if value == nil then return nil, "unavailable" end
  if message ~= nil or code[0] ~= 0 then return nil, "platform-error" end
  local length = tonumber(ffi.C.strnlen(value, maximum_bytes + 1))
  if length > maximum_bytes then return nil, "over-limit" end
  return ffi.string(value, length)
end

function Window:clipboard_write(text)
  assert(type(text) == "string" and not text:find("\0", 1, true), "clipboard text must be a NUL-free string")
  local code = ffi.new("int[1]")
  glfw.lib.glfwGetError(code)
  glfw.lib.glfwSetClipboardString(self.handle, text)
  local message = glfw.lib.glfwGetError(code)
  if message ~= nil or code[0] ~= 0 then return false, "platform-error" end
  return true
end

function Window:cocoa_private_clipboard_round_trip(text)
  if ffi.os ~= "OSX" then return nil, "Cocoa pasteboard checks are unavailable on this platform" end
  assert(type(text) == "string" and #text > 0 and not text:find("\0", 1, true), "Cocoa pasteboard text must be a non-empty NUL-free string")
  if native.kiwi_cocoa_private_pasteboard_round_trip(text, #text) == 0 then
    return false, ffi.string(native.kiwi_surface_last_error())
  end
  return true
end

function Window:cocoa_accessibility_round_trip()
  if ffi.os ~= "OSX" then return nil, "Cocoa accessibility checks are unavailable on this platform" end
  if native.kiwi_cocoa_accessibility_round_trip(self.handle) == 0 then
    return false, ffi.string(native.kiwi_surface_last_error())
  end
  return true
end

function Window:cocoa_text_input_round_trip()
  if ffi.os ~= "OSX" then return nil, "Cocoa text-input checks are unavailable on this platform" end
  if native.kiwi_cocoa_text_input_round_trip(self.handle) == 0 then
    return false, ffi.string(native.kiwi_surface_last_error())
  end
  return true
end

function Window:enable_cocoa_text_input(on_preedit, on_commit)
  if ffi.os ~= "OSX" then return nil, "Cocoa text input is unavailable on this platform" end
  assert(type(on_preedit) == "function" and type(on_commit) == "function", "Cocoa text input needs preedit and commit callbacks")
  if self.cocoa_text_input ~= nil then return true end
  self.callbacks.cocoa_preedit = ffi.cast("KiwiCocoaTextInputCallback", function(_, text, text_bytes, selection_start, selection_end)
    local value = tonumber(text_bytes) == 0 and "" or ffi.string(text, tonumber(text_bytes))
    on_preedit(value, tonumber(selection_start), tonumber(selection_end))
  end)
  self.callbacks.cocoa_commit = ffi.cast("KiwiCocoaTextInputCallback", function(_, text, text_bytes)
    local value = tonumber(text_bytes) == 0 and "" or ffi.string(text, tonumber(text_bytes))
    on_commit(value)
  end)
  self.cocoa_text_input = native.kiwi_cocoa_text_input_new(self.handle, self.callbacks.cocoa_preedit, self.callbacks.cocoa_commit, nil)
  if self.cocoa_text_input == nil then
    self.callbacks.cocoa_preedit = nil
    self.callbacks.cocoa_commit = nil
    return nil, ffi.string(native.kiwi_surface_last_error())
  end
  return true
end

function Window:set_cocoa_text_input_caret(x, y, width, height)
  if self.cocoa_text_input == nil then return false end
  for _, value in ipairs({ x, y, width, height }) do
    assert(type(value) == "number" and value == value and value > -math.huge and value < math.huge, "Cocoa text-input caret coordinates must be finite")
  end
  native.kiwi_cocoa_text_input_set_caret(self.cocoa_text_input, x, y, width, height)
  return true
end

function Window:cocoa_text_input_inject_smoke()
  if self.cocoa_text_input == nil then return nil, "Cocoa text input is not enabled" end
  if native.kiwi_cocoa_text_input_inject_smoke(self.cocoa_text_input) == 0 then
    return false, ffi.string(native.kiwi_surface_last_error())
  end
  return true
end

function Window:system_appearance()
  if ffi.os ~= "OSX" then return nil end
  local value = native.kiwi_cocoa_system_appearance(self.handle)
  if value == 1 then return "dark" end
  if value == 0 then return "light" end
  return nil
end

function Window:cocoa_key_variants(scancode, key)
  if ffi.os ~= "OSX" or scancode < 0 then return nil end
  local base_key = pc101_base_key(key)
  if base_key == nil then return nil end
  local layout_key = ffi.new("uint32_t[1]")
  local shifted_key = ffi.new("uint32_t[1]")
  if native.kiwi_cocoa_key_variants(scancode, layout_key, shifted_key) == 0 then return nil end
  return {
    layout_key = tonumber(layout_key[0]),
    shifted_key = tonumber(shifted_key[0]),
    base_key = base_key,
  }
end

function Window:enable_cocoa_menu(handler)
  if ffi.os ~= "OSX" then return nil, "Cocoa menus are unavailable on this platform" end
  assert(type(handler) == "function", "Cocoa menu needs an action handler")
  self.callbacks.cocoa_menu = ffi.cast("KiwiCocoaMenuCallback", function(_, action)
    local name = cocoa_menu_actions[tonumber(action)]
    if name == nil then return end
    local ok, message = pcall(handler, name)
    if not ok then io.stderr:write("Kiwi Cocoa menu action failed: ", tostring(message), "\n") end
  end)
  if native.kiwi_cocoa_menu_install(self.handle, self.callbacks.cocoa_menu, nil) ~= 0 then return true end
  self.callbacks.cocoa_menu:free()
  self.callbacks.cocoa_menu = nil
  return false, ffi.string(native.kiwi_surface_last_error())
end

function Window:cocoa_menu_invoke_smoke(action)
  if ffi.os ~= "OSX" then return nil, "Cocoa menus are unavailable on this platform" end
  local identifier = cocoa_menu_action_ids[action]
  if identifier == nil then return nil, "Cocoa menu smoke names an unknown action" end
  if native.kiwi_cocoa_menu_invoke_smoke(self.handle, identifier) ~= 0 then return true end
  return false, ffi.string(native.kiwi_surface_last_error())
end

function Window:cocoa_toolbar_invoke_smoke(action)
  if ffi.os ~= "OSX" then return nil, "Cocoa toolbars are unavailable on this platform" end
  local identifier = cocoa_menu_action_ids[action]
  if identifier == nil then return nil, "Cocoa toolbar smoke names an unknown action" end
  if native.kiwi_cocoa_toolbar_invoke_smoke(self.handle, identifier) ~= 0 then return true end
  return false, ffi.string(native.kiwi_surface_last_error())
end

function Window:enable_cocoa_automation(handler)
  if ffi.os ~= "OSX" then return nil, "Cocoa automation is unavailable on this platform" end
  assert(type(handler) == "function", "Cocoa automation needs an action handler")
  self:disable_cocoa_automation()
  local callback = ffi.cast("KiwiCocoaAutomationCallback", function(_, action)
    local name = cocoa_menu_actions[tonumber(action)]
    if name == nil then return 0 end
    local ok, handled = pcall(handler, name)
    if not ok then
      io.stderr:write("Kiwi Cocoa automation action failed: ", tostring(handled), "\n")
      return 0
    end
    return handled == true and 1 or 0
  end)
  if native.kiwi_cocoa_automation_install(self.handle, callback, nil) ~= 0 then
    self.callbacks.cocoa_automation = callback
    return true
  end
  callback:free()
  return false, ffi.string(native.kiwi_surface_last_error())
end

function Window:disable_cocoa_automation()
  if ffi.os ~= "OSX" then return end
  if self.handle ~= nil then native.kiwi_cocoa_automation_remove(self.handle) end
  if self.callbacks.cocoa_automation ~= nil then
    self.callbacks.cocoa_automation:free()
    self.callbacks.cocoa_automation = nil
  end
end

function Window:cocoa_automation_invoke_smoke(action)
  if ffi.os ~= "OSX" then return nil, "Cocoa automation is unavailable on this platform" end
  local identifier = cocoa_menu_action_ids[action]
  if identifier == nil then return nil, "Cocoa automation smoke names an unknown action" end
  if native.kiwi_cocoa_automation_invoke_smoke(self.handle, identifier) ~= 0 then return true end
  return false, ffi.string(native.kiwi_surface_last_error())
end

function Window:cocoa_window_tabs_round_trip(peer)
  if ffi.os ~= "OSX" then return nil, "Cocoa window tabs are unavailable on this platform" end
  if type(peer) ~= "table" or peer.handle == nil then return nil, "Cocoa window-tab smoke needs a live peer window" end
  if native.kiwi_cocoa_window_tabs_round_trip(self.handle, peer.handle) ~= 0 then return true end
  return false, ffi.string(native.kiwi_surface_last_error())
end

local function command_palette_entries(entries)
  assert(type(entries) == "table" and #entries > 0 and #entries <= 32, "Cocoa command palette needs one through 32 entries")
  local values = ffi.new("KiwiCocoaCommandPaletteEntry[?]", #entries)
  for index, entry in ipairs(entries) do
    assert(type(entry) == "table", "Cocoa command palette entry must be a table")
    local action = cocoa_menu_action_ids[entry.action]
    assert(action ~= nil and entry.action ~= "command-palette", "Cocoa command palette entry names an unavailable action")
    assert(type(entry.title) == "string" and #entry.title > 0 and #entry.title <= 128 and not entry.title:find("\0", 1, true), "Cocoa command palette title is invalid")
    assert(type(entry.description) == "string" and #entry.description <= 256 and not entry.description:find("\0", 1, true), "Cocoa command palette description is invalid")
    values[index - 1].action = action
    values[index - 1].title = entry.title
    values[index - 1].description = entry.description
  end
  return values
end

function Window:show_cocoa_command_palette(entries, handler)
  if ffi.os ~= "OSX" then return nil, "Cocoa command palettes are unavailable on this platform" end
  assert(type(handler) == "function", "Cocoa command palette needs an action handler")
  local values = command_palette_entries(entries)
  if self.callbacks.cocoa_command_palette ~= nil then
    native.kiwi_cocoa_command_palette_remove(self.handle)
    self.callbacks.cocoa_command_palette:free()
    self.callbacks.cocoa_command_palette = nil
  end
  local callback = ffi.cast("KiwiCocoaMenuCallback", function(_, action)
    local name = cocoa_menu_actions[tonumber(action)]
    if name == nil or name == "command-palette" then return end
    local ok, message = pcall(handler, name)
    if not ok then io.stderr:write("Kiwi Cocoa command palette action failed: ", tostring(message), "\n") end
  end)
  if native.kiwi_cocoa_command_palette_show(self.handle, values, #entries, callback, nil) ~= 0 then
    self.callbacks.cocoa_command_palette = callback
    return true
  end
  callback:free()
  return false, ffi.string(native.kiwi_surface_last_error())
end

function Window:cocoa_command_palette_invoke_smoke()
  if ffi.os ~= "OSX" then return nil, "Cocoa command palettes are unavailable on this platform" end
  if native.kiwi_cocoa_command_palette_invoke_smoke(self.handle) ~= 0 then return true end
  return false, ffi.string(native.kiwi_surface_last_error())
end

function Window:cocoa_set_progress(progress, state)
  if ffi.os ~= "OSX" then return nil, "Cocoa progress is unavailable on this platform" end
  assert(type(progress) == "number" and progress % 1 == 0 and progress >= 0 and progress <= 100, "Cocoa progress must be an integer from 0 through 100")
  assert(type(state) == "number" and state % 1 == 0 and state >= 0 and state <= 4, "Cocoa progress state must be an integer from 0 through 4")
  if native.kiwi_cocoa_progress_set(self.handle, progress, state) ~= 0 then return true end
  return false, ffi.string(native.kiwi_surface_last_error())
end

function Window:cocoa_progress_round_trip()
  if ffi.os ~= "OSX" then return nil, "Cocoa progress is unavailable on this platform" end
  if native.kiwi_cocoa_progress_round_trip(self.handle) ~= 0 then return true end
  return false, ffi.string(native.kiwi_surface_last_error())
end

function Window:open_uri(uri)
  assert(type(uri) == "string" and #uri > 0 and not uri:find("\0", 1, true), "URI opener needs a non-empty NUL-free URI")
  if native.kiwi_open_uri(uri) ~= 0 then return false, "platform-error" end
  return true
end

function Window:open_text_file(path)
  assert(type(path) == "string" and #path > 0 and not path:find("\0", 1, true), "text-file opener needs a non-empty NUL-free path")
  if native.kiwi_open_text_file(path) ~= 0 then return false, "platform-error" end
  return true
end

function Window:take_shader_reload_request()
  local requested = self.shader_reload_requested
  self.shader_reload_requested = false
  return requested
end

function Window:set_title(title)
  glfw.lib.glfwSetWindowTitle(self.handle, title)
end

function Window:set_size(width, height)
  assert(type(width) == "number" and width >= 1 and width % 1 == 0, "window width must be a positive integer")
  assert(type(height) == "number" and height >= 1 and height % 1 == 0, "window height must be a positive integer")
  glfw.lib.glfwSetWindowSize(self.handle, width, height)
end

function Window:set_position(x, y)
  assert(type(x) == "number" and x % 1 == 0, "window x position must be an integer")
  assert(type(y) == "number" and y % 1 == 0, "window y position must be an integer")
  glfw.lib.glfwSetWindowPos(self.handle, x, y)
end

function Window:geometry()
  local x = ffi.new("int[1]")
  local y = ffi.new("int[1]")
  local width = ffi.new("int[1]")
  local height = ffi.new("int[1]")
  glfw.lib.glfwGetWindowPos(self.handle, x, y)
  glfw.lib.glfwGetWindowSize(self.handle, width, height)
  return { height = height[0], width = width[0], x = x[0], y = y[0] }
end

function Window:iconify()
  glfw.lib.glfwIconifyWindow(self.handle)
end

function Window:restore()
  glfw.lib.glfwRestoreWindow(self.handle)
end

function Window:drawable_size()
  local width = ffi.new("int[1]")
  local height = ffi.new("int[1]")
  glfw.lib.glfwGetFramebufferSize(self.handle, width, height)
  return width[0], height[0]
end

function Window:content_scale()
  local xscale = ffi.new("float[1]")
  local yscale = ffi.new("float[1]")
  glfw.lib.glfwGetWindowContentScale(self.handle, xscale, yscale)
  return xscale[0], yscale[0]
end

function Window:should_close()
  return glfw.lib.glfwWindowShouldClose(self.handle) ~= 0
end

function Window:request_close()
  glfw.lib.glfwSetWindowShouldClose(self.handle, 1)
end

local function flush_input_correlations(windows)
  for _, window in ipairs(windows) do
    if window.handle ~= nil then window.input_correlation:flush() end
  end
end

function Window.poll_events_for(windows)
  assert(type(windows) == "table", "event polling needs a window list")
  glfw.lib.glfwPollEvents()
  flush_input_correlations(windows)
end

function Window.wait_events_for(timeout, windows)
  assert(type(timeout) == "number" and timeout >= 0, "event wait timeout must be non-negative")
  assert(type(windows) == "table", "event waiting needs a window list")
  glfw.lib.glfwWaitEventsTimeout(timeout)
  flush_input_correlations(windows)
end

function Window:poll_events()
  Window.poll_events_for({ self })
end

function Window:wait_events(timeout)
  Window.wait_events_for(timeout, { self })
end

function Window:time()
  return glfw.lib.glfwGetTime()
end

function Window:destroy()
  self.input_correlation:flush()
  if self.cocoa_text_input ~= nil then
    native.kiwi_cocoa_text_input_destroy(self.cocoa_text_input)
    self.cocoa_text_input = nil
    if self.callbacks.cocoa_preedit ~= nil then self.callbacks.cocoa_preedit:free(); self.callbacks.cocoa_preedit = nil end
    if self.callbacks.cocoa_commit ~= nil then self.callbacks.cocoa_commit:free(); self.callbacks.cocoa_commit = nil end
  end
  if self.handle ~= nil then
    if ffi.os == "OSX" then native.kiwi_cocoa_window_tabs_remove_bridge(self.handle) end
    if ffi.os == "OSX" then native.kiwi_cocoa_progress_remove_bridge(self.handle) end
    if ffi.os == "OSX" then native.kiwi_cocoa_command_palette_remove(self.handle) end
    if ffi.os == "OSX" then native.kiwi_cocoa_menu_remove(self.handle) end
    if ffi.os == "OSX" then self:disable_cocoa_automation() end
    glfw.lib.glfwDestroyWindow(self.handle)
    self.handle = nil
    live_windows = live_windows - 1
    assert(live_windows >= 0, "GLFW window lifetime underflow")
    if live_windows == 0 then glfw.lib.glfwTerminate() end
  end
  local callback_names = {}
  for name in pairs(self.callbacks) do callback_names[#callback_names + 1] = name end
  for _, name in ipairs(callback_names) do
    local callback = self.callbacks[name]
    if callback ~= nil then callback:free(); self.callbacks[name] = nil end
  end
end

function Window.live_count()
  return live_windows
end

return Window
