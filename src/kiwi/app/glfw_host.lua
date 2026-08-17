-- GLFW is a development host. Keep its construction and process-wide event
-- queue out of the terminal controller so native hosts can supply the same
-- window contract later.
local ffi = require("ffi")
local Window = require("kiwi.platform.window")
local glfw = require("kiwi.ffi.glfw").constants

local Host = {
  keymap = glfw,
  platform = ffi.os,
}

function Host.new(geometry, title, options)
  options = options or {}
  return Window.new(
    geometry and geometry.width or 1600,
    geometry and geometry.height or 960,
    title,
    { release_mode = options.release_mode }
  )
end

function Host.await_events(application, window, timeout)
  return application:await_events(window, timeout)
end

function Host.live_count()
  return Window.live_count()
end

function Host.run(options, title, controller)
  assert(type(controller) == "function", "GLFW host needs a controller")
  local window = Host.new(options.geometry, title, options)
  return controller(window, Host, options)
end

return Host
