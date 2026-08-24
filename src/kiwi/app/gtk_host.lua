local ffi = require("ffi")
local Window = require("kiwi.platform.gtk_window")

local Host = {
  keymap = require("kiwi.ffi.glfw").constants,
  keyboard_supported_flags = 0x1f,
  platform = "GTK",
  presentation_backend = os.getenv("KIWI_GTK_PRESENTER") == "gl" and "gtk-gl" or "wgpu",
  window_api = Window,
}

function Host.new(geometry, title)
  return Window.new(geometry and geometry.width or 1600, geometry and geometry.height or 960, title)
end

function Host.keyboard_supported_flags_for(window)
  return window.keyboard_supported_flags
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

function Host.enable_text_input(window, on_preedit, on_commit)
  return window:enable_text_input(on_preedit, on_commit)
end

function Host.set_text_input_caret(window, x, y, width, height)
  return window:set_text_input_caret(x, y, width, height)
end

function Host.set_pointer_shape(window, shape)
  return window:set_pointer_shape(shape)
end

function Host.accessibility_new(window)
  return window:accessibility_new()
end

function Host.surface_error()
  return ffi.string(require("kiwi.platform.gtk_window").bridge.kiwi_gtk_host_last_error())
end

function Host.live_count()
  return Window.live_count()
end

function Host.system_appearance(window)
  return window:system_appearance()
end

function Host.open_text_file(window, path)
  return window:open_text_file(path)
end

function Host.notify(window, title, body)
  return window:notify(title, body)
end

function Host.set_progress(window, progress, state)
  return window:set_progress(progress, state)
end

function Host.set_product_action_handler(window, handler)
  return window:enable_product_action_handler(handler)
end

function Host.invoke_product_action_smoke(window, action)
  return window:product_action_invoke_smoke(action)
end

function Host.show_command_palette(window, entries, handler)
  return window:show_command_palette(entries, handler)
end

function Host.invoke_command_palette_smoke(window)
  return window:command_palette_invoke_smoke()
end

return Host
