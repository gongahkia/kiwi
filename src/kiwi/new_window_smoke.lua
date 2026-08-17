local Window = require("kiwi.platform.window")

local marker = assert(os.getenv("KIWI_NEW_WINDOW_SMOKE_MARKER"), "new-window smoke needs KIWI_NEW_WINDOW_SMOKE_MARKER")

if os.getenv("KIWI_NEW_WINDOW_CHILD") == "1" then
  local file = assert(io.open(marker, "wb"))
  assert(file:write("child\n"))
  assert(file:close())
  return
end

local window
local ok, message = xpcall(function()
  window = Window.new(320, 240, "Kiwi new-window smoke")
  local opened, reason = window:open_new_window(nil)
  assert(opened, "new-window action failed: " .. tostring(reason))
  for _ = 1, 100 do
    local file = io.open(marker, "rb")
    if file ~= nil then
      local value = file:read("*a")
      file:close()
      assert(value == "child\n", "new-window child wrote an unexpected marker")
      print("Native new-window smoke passed: a detached Kiwi process received the launch request.")
      return
    end
    window:wait_events(0.01)
  end
  error("new-window action did not start a child process")
end, debug.traceback)

if window then window:destroy() end
assert(ok, message)
