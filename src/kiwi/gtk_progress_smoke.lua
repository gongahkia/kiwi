local Effects = require("kiwi.app.host_effects")
local Host = require("kiwi.app.gtk_host")

local window
local ok, message = xpcall(function()
  window = Host.new(nil, "Kiwi GTK progress smoke")
  local effects = Effects.new({
    notify_on_command_finish = "never",
    notify_on_command_finish_after = 5,
    osc9_notifications = "off",
    osc9_progress = "system",
  }, Host, window)
  local handled, status = effects:consume({
    kind = "progress_changed",
    value = { progress = 73, state = 1 },
  })
  assert(handled and status == "submitted", "GTK host policy did not submit terminal progress")
  local progress_ok, progress_message = window:progress_round_trip()
  assert(progress_ok, "GTK terminal progress smoke failed: " .. tostring(progress_message))
  print("GTK native progress smoke passed: determinate, error, indeterminate, paused, and clear states.")
end, debug.traceback)

if window then window:destroy() end
assert(ok, message)
