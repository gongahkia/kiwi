-- GLFW is a development host. Keep its construction and process-wide event
-- queue out of the terminal controller so native hosts can supply the same
-- window contract later.
local ffi = require("ffi")
local Window = require("kiwi.platform.window")
local glfw = require("kiwi.ffi.glfw").constants

local Host = {
  keymap = glfw,
  keyboard_supported_flags = ffi.os == "OSX" and 0x1f or 0x1b,
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

function Host.create_surface(instance, window)
  return require("kiwi.ffi.wgpu").surface.kiwi_surface_from_glfw(instance, window.handle)
end

function Host.set_drawable_size(window, width, height)
  return require("kiwi.ffi.wgpu").surface.kiwi_surface_set_drawable_size(window.handle, width, height) ~= 0
end

function Host.surface_error()
  return require("ffi").string(require("kiwi.ffi.wgpu").surface.kiwi_surface_last_error())
end

if ffi.os == "OSX" then
  function Host.enable_text_input(window, on_preedit, on_commit)
    return window:enable_cocoa_text_input(on_preedit, on_commit)
  end

  function Host.set_text_input_caret(window, x, y, width, height)
    return window:set_cocoa_text_input_caret(x, y, width, height)
  end
end

function Host.accessibility_new(window)
  return require("kiwi.ffi.accessibility").new(window)
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

if ffi.os == "OSX" then
  function Host.set_progress(window, progress, state)
    return window:cocoa_set_progress(progress, state)
  end

  function Host.set_product_action_handler(window, handler)
    return window:enable_cocoa_menu(handler)
  end

  function Host.invoke_product_action_smoke(window, action)
    return window:cocoa_menu_invoke_smoke(action)
  end

  function Host.set_automation_action_handler(window, handler)
    return window:enable_cocoa_automation(handler)
  end

  function Host.remove_automation_action_handler(window)
    return window:disable_cocoa_automation()
  end

  function Host.invoke_automation_action_smoke(window, action)
    return window:cocoa_automation_invoke_smoke(action)
  end

  function Host.show_command_palette(window, entries, handler)
    return window:show_cocoa_command_palette(entries, handler)
  end

  function Host.invoke_command_palette_smoke(window)
    return window:cocoa_command_palette_invoke_smoke()
  end
end

function Host.run(options, title, controller)
  assert(type(controller) == "function", "GLFW host needs a controller")
  local window = Host.new(options.geometry, title, options)
  return controller(window, Host, options)
end

return Host
