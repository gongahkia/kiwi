local Context = require("kiwi.gpu.context")
local Window = require("kiwi.platform.window")

local function require_result(result, message)
  assert(result, message)
end

local window
local context
local ok, message = xpcall(function()
  window = Window.new(320, 240, "Kiwi Cocoa smoke")
  context = Context.new(window)

  local clipboard_ok, clipboard_message = window:cocoa_private_clipboard_round_trip("kiwi-cocoa-private-pasteboard-✓")
  require_result(clipboard_ok, "Cocoa private pasteboard smoke failed: " .. tostring(clipboard_message))

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

  print(string.format("Cocoa native smoke passed: private-pasteboard and resize=%dx%d", resized_width, resized_height))
end, debug.traceback)

if context then context:destroy() end
if window then window:destroy() end
assert(ok, message)
