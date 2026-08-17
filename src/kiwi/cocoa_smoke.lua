local Context = require("kiwi.gpu.context")
local Window = require("kiwi.platform.window")

local function require_result(result, message)
  assert(result, message)
end

local window
local context
local second_window
local second_context
local ok, message = xpcall(function()
  window = Window.new(320, 240, "Kiwi Cocoa smoke")
  context = Context.new(window)
  second_window = Window.new(240, 180, "Kiwi Cocoa second-window smoke")
  second_context = Context.new(second_window)
  require_result(Window.live_count() == 2, "Cocoa multi-window smoke did not retain both GLFW windows")

  local clipboard_ok, clipboard_message = window:cocoa_private_clipboard_round_trip("kiwi-cocoa-private-pasteboard-✓")
  require_result(clipboard_ok, "Cocoa private pasteboard smoke failed: " .. tostring(clipboard_message))
  local accessibility_ok, accessibility_message = window:cocoa_accessibility_round_trip()
  require_result(accessibility_ok, "Cocoa accessibility smoke failed: " .. tostring(accessibility_message))

  local initial_width, initial_height = window:drawable_size()
  window:set_size(640, 480)
  local resized_width, resized_height = initial_width, initial_height
  for _ = 1, 100 do
    window:wait_events(0.01)
    resized_width, resized_height = window:drawable_size()
    if window.resized and (resized_width ~= initial_width or resized_height ~= initial_height) then break end
  end
  require_result(window.resized and (resized_width ~= initial_width or resized_height ~= initial_height), "Cocoa resize smoke did not receive a changed framebuffer size")
  require_result(context:configure_surface(), "Cocoa resize smoke could not configure the resized Metal surface")
  require_result(context.width == resized_width and context.height == resized_height, "Cocoa resize smoke configured a stale drawable size")
  require_result(second_context:configure_surface(), "Cocoa multi-window smoke could not configure the second Metal surface")
  second_context:destroy()
  second_context = nil
  second_window:destroy()
  second_window = nil
  require_result(Window.live_count() == 1, "Cocoa multi-window smoke terminated GLFW while the primary window remained live")
  require_result(context:configure_surface(), "Cocoa primary surface stopped working after the second window closed")

  print(string.format("Cocoa native smoke passed: private-pasteboard, NSAccessibility projection, resize=%dx%d, and two independent Metal windows", resized_width, resized_height))
end, debug.traceback)

if second_context then second_context:destroy() end
if second_window then second_window:destroy() end
if context then context:destroy() end
if window then window:destroy() end
assert(ok, message)
