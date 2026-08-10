local ffi = require("ffi")
local glfw = require("kiwi.ffi.glfw")

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

function Window.new(width, height, title)
  if glfw.lib.glfwInit() == 0 then
    error("Unable to initialize GLFW: " .. glfw_error())
  end

  glfw.lib.glfwWindowHint(glfw.constants.client_api, glfw.constants.no_api)
  glfw.lib.glfwWindowHint(glfw.constants.resizable, glfw.constants.yes)
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
    callbacks = {},
  }, Window)
  self.callbacks.resize = ffi.cast("GLFWframebuffersizefun", function(_, drawable_width, drawable_height)
    self.resized = true
    self.minimized = drawable_width <= 0 or drawable_height <= 0
  end)
  self.callbacks.key = ffi.cast("GLFWkeyfun", function(_, key, _, action, modifiers)
    self.modifiers = modifiers
    local input = self.on_key and self.on_key(key, action, modifiers)
    if input and input.suppress_text then self.suppress_text = true end
    if input and input.handled then return end
    if action == glfw.constants.release then self.suppress_text = false end
    if action == glfw.constants.press and key == glfw.constants.key_f2 then
      self.debug_dirty = not self.debug_dirty
    elseif action == glfw.constants.press and key == glfw.constants.key_f3 then
      self.debug_boundaries = not self.debug_boundaries
    elseif action == glfw.constants.press and key == glfw.constants.key_f4 then
      self.debug_metrics = not self.debug_metrics
    elseif action == glfw.constants.press and key == glfw.constants.key_f5 then
      self.shader_reload_requested = true
    elseif action == glfw.constants.press and key == glfw.constants.key_escape then
      glfw.lib.glfwSetWindowShouldClose(self.handle, 1)
    end
  end)
  self.callbacks.character = ffi.cast("GLFWcharfun", function(_, codepoint)
    if self.suppress_text then
      self.suppress_text = false
      return
    end
    if self.on_text then
      self.on_text(codepoint)
    end
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
  self.callbacks.scroll = ffi.cast("GLFWscrollfun", function(_, _, yoffset)
    if self.on_pointer then
      local x, y = self:cursor_position()
      self.on_pointer({ kind = "wheel", delta = yoffset, x = x, y = y, modifiers = self.modifiers })
    end
  end)
  self.callbacks.focus = ffi.cast("GLFWwindowfocusfun", function(_, focused)
    if self.on_focus then self.on_focus(focused ~= 0) end
  end)
  glfw.lib.glfwSetFramebufferSizeCallback(handle, self.callbacks.resize)
  glfw.lib.glfwSetKeyCallback(handle, self.callbacks.key)
  glfw.lib.glfwSetCharCallback(handle, self.callbacks.character)
  glfw.lib.glfwSetCursorPosCallback(handle, self.callbacks.cursor_position)
  glfw.lib.glfwSetMouseButtonCallback(handle, self.callbacks.mouse_button)
  glfw.lib.glfwSetScrollCallback(handle, self.callbacks.scroll)
  glfw.lib.glfwSetWindowFocusCallback(handle, self.callbacks.focus)
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

function Window:take_shader_reload_request()
  local requested = self.shader_reload_requested
  self.shader_reload_requested = false
  return requested
end

function Window:set_title(title)
  glfw.lib.glfwSetWindowTitle(self.handle, title)
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
end

function Window:wait_events(timeout)
  glfw.lib.glfwWaitEventsTimeout(timeout)
end

function Window:time()
  return glfw.lib.glfwGetTime()
end

function Window:destroy()
  if self.handle ~= nil then
    glfw.lib.glfwDestroyWindow(self.handle)
    self.handle = nil
  end
  glfw.lib.glfwTerminate()
end

return Window
