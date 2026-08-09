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
    debug_dirty = false,
    debug_boundaries = false,
    callbacks = {},
  }, Window)
  self.callbacks.resize = ffi.cast("GLFWframebuffersizefun", function(_, drawable_width, drawable_height)
    self.resized = drawable_width > 0 and drawable_height > 0
  end)
  self.callbacks.key = ffi.cast("GLFWkeyfun", function(_, key, _, action)
    if action ~= glfw.constants.press then
      return
    end
    if key == glfw.constants.key_escape then
      glfw.lib.glfwSetWindowShouldClose(self.handle, 1)
    elseif key == glfw.constants.key_f2 then
      self.debug_dirty = not self.debug_dirty
    elseif key == glfw.constants.key_f3 then
      self.debug_boundaries = not self.debug_boundaries
    end
  end)
  glfw.lib.glfwSetFramebufferSizeCallback(handle, self.callbacks.resize)
  glfw.lib.glfwSetKeyCallback(handle, self.callbacks.key)
  return self
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
