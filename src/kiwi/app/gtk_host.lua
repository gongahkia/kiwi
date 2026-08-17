local ffi = require("ffi")
local Window = require("kiwi.platform.gtk_window")

local Host = {
  keymap = require("kiwi.ffi.glfw").constants,
  platform = "GTK",
  window_api = Window,
}

function Host.new(geometry, title)
  return Window.new(geometry and geometry.width or 1600, geometry and geometry.height or 960, title)
end

function Host.run(options, title, controller)
  local window = Host.new(options.geometry, title)
  for _ = 1, 100 do
    local width, height = window:drawable_size()
    if width > 0 and height > 0 then return controller(window, Host, options) end
    window:wait_events(0.01)
  end
  window:destroy()
  error("GTK host did not receive a nonzero drawable size")
end

function Host.await_events(application, window, timeout)
  return application:await_events(window, timeout)
end

function Host.create_surface(instance, window)
  local native = require("kiwi.platform.gtk_window")
  local bridge = native.bridge
  return ffi.cast("WGPUSurface", bridge.kiwi_gtk_host_create_surface(instance, window.handle))
end

function Host.set_drawable_size(window, width, height)
  return require("kiwi.platform.gtk_window").bridge.kiwi_gtk_host_set_drawable_size(window.handle, width, height) ~= 0
end

function Host.surface_error()
  return ffi.string(require("kiwi.platform.gtk_window").bridge.kiwi_gtk_host_last_error())
end

function Host.live_count()
  return Window.live_count()
end

return Host
