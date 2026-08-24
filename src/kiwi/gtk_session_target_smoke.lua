local Host = require("kiwi.app.gtk_host")

local window
local ok, message = xpcall(function()
  window = Host.new(nil, "Kiwi GTK session target smoke")
  local selected
  assert(window:show_command_palette({
    {
      action = "session-target-1",
      description = "Move the active live terminal session here.",
      title = "Window 2",
    },
  }, function(action)
    selected = action
  end))
  assert(window:command_palette_invoke_smoke())
  assert(selected == "session-target-1", "GTK destination chooser did not retain the selected bounded action")
  print("GTK session target smoke passed: the bounded native chooser returned its selected destination slot.")
end, debug.traceback)

if window then window:destroy() end
assert(ok, message)
