local Window = require("kiwi.platform.gtk_window")

local window
local ok, message = xpcall(function()
  window = Window.new(320, 200, "Kiwi GTK accessibility smoke")
  local accessibility = window:accessibility_new()
  local updated, reason = accessibility:update({
    caret_offset = 6,
    character_count = 6,
    selection_end = 4,
    selection_start = 0,
    text = "kiwi\n✓",
  }, "Kiwi GTK accessibility smoke", true)
  assert(updated, "GTK native accessibility update failed: " .. tostring(reason))
  accessibility:poll()
  for _ = 1, 10 do window:wait_events(0.01) end
end, debug.traceback)

if window then window:destroy() end
assert(ok, message)
print("GTK native accessibility smoke passed.")
