local ffi = require("ffi")
local glfw = require("kiwi.ffi.glfw")
local Correlation = require("kiwi.input.correlation")

ffi.cdef[[
size_t strnlen(const char* text, size_t maximum);
int kiwi_open_uri(const char* uri);
int kiwi_cocoa_private_pasteboard_round_trip(const char* text, size_t text_bytes);
const char* kiwi_surface_last_error(void);
]]

local root = os.getenv("KIWI_ROOT") or "."
local library_extension = ffi.os == "OSX" and ".dylib" or ".so"
local native_path = os.getenv("KIWI_SURFACE_LIB") or root .. "/.build/native/libkiwi_surface" .. library_extension
local native_ok, native = pcall(ffi.load, native_path)
if not native_ok then error("Unable to load Kiwi native bridge at " .. native_path .. "; run make native: " .. tostring(native)) end

local Window = {}
Window.__index = Window

local function glfw_error()
  local code = ffi.new("int[1]")
  local message = glfw.lib.glfwGetError(code)
  if message == nil then
    return string.format("GLFW error %d", code[0])
  end
  return string.format("GLFW error %d: %s", code[0], ffi.string(message))
end

function Window.new(width, height, title, options)
  options = options or {}
  assert(options.visible == nil or type(options.visible) == "boolean", "window visibility must be a boolean")
  if glfw.lib.glfwInit() == 0 then
    error("Unable to initialize GLFW: " .. glfw_error())
  end

  glfw.lib.glfwWindowHint(glfw.constants.client_api, glfw.constants.no_api)
  glfw.lib.glfwWindowHint(glfw.constants.resizable, glfw.constants.yes)
  glfw.lib.glfwWindowHint(glfw.constants.visible, options.visible == false and glfw.constants.no or glfw.constants.yes)
  glfw.lib.glfwWindowHint(glfw.constants.scale_framebuffer, glfw.constants.yes)
  local handle = glfw.lib.glfwCreateWindow(width, height, title, nil, nil)
  if handle == nil then
    glfw.lib.glfwTerminate()
    error("Unable to create a native GLFW window: " .. glfw_error())
  end

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
    local input = self.on_key and self.on_key(key, action, modifiers)
    if input and input.defer_text then
      self.input_correlation:defer({ key = key, scancode = scancode, action = action, modifiers = modifiers })
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

function Window:open_uri(uri)
  assert(type(uri) == "string" and #uri > 0 and not uri:find("\0", 1, true), "URI opener needs a non-empty NUL-free URI")
  if native.kiwi_open_uri(uri) ~= 0 then return false, "platform-error" end
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

function Window:poll_events()
  glfw.lib.glfwPollEvents()
  self.input_correlation:flush()
end

function Window:wait_events(timeout)
  glfw.lib.glfwWaitEventsTimeout(timeout)
  self.input_correlation:flush()
end

function Window:time()
  return glfw.lib.glfwGetTime()
end

function Window:destroy()
  self.input_correlation:flush()
  if self.handle ~= nil then
    glfw.lib.glfwDestroyWindow(self.handle)
    self.handle = nil
  end
  glfw.lib.glfwTerminate()
end

return Window
