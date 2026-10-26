assert(os.getenv("KIWI_PRIMARY_SMOKE_ISOLATED") == "1" and os.getenv("GDK_BACKEND") == "wayland",
  "GTK primary smoke requires its private Wayland compositor")
local Window = require("kiwi.platform.gtk_window")
local root = assert(os.getenv("KIWI_PRIMARY_SMOKE_DIRECTORY"))
local window = Window.new(320, 200, "Kiwi Wayland PRIMARY probe")
local function write(name, text)
  local file = assert(io.open(root .. "/" .. name .. ".new", "wb"))
  assert(file:write(text)); assert(file:close())
  assert(os.rename(root .. "/" .. name .. ".new", root .. "/" .. name))
end
local function read(name)
  local file = io.open(root .. "/" .. name, "rb")
  if not file then return nil end
  local value = file:read("*a"); file:close(); return value
end
local started = window:time()
local pending
local ok, message = xpcall(function()
  assert(window:primary_supported(), "compositor does not advertise supported PRIMARY protocol")
  write("ready", "ready")
  while true do
    Window.pump(window, 0.01)
    assert(window:time() - started < 25, "Wayland PRIMARY probe timed out")
    local command = read("command")
    if command then
      os.remove(root .. "/command")
      assert(not pending, "one request at a time")
      if command == "publish" then
        assert(window:primary_write("Kiwi primary 中"))
        write("reply", "published")
      elseif command == "read" then
        pending = assert(window:primary_read(1024))
      elseif command == "limit" then
        pending = assert(window:primary_read(5))
      elseif command == "cancel" then
        local requests = {}
        for i = 1, 16 do requests[i] = assert(window:primary_read(1024)) end
        local overflow, reason = window:primary_read(1024)
        assert(overflow == nil and reason == "busy")
        for _, request in ipairs(requests) do
          request:destroy()
          local _, status = request:poll()
          assert(status == "cancelled")
        end
        write("reply", "cancelled")
      elseif command == "close" then
        local closing = assert(window:primary_read(1024))
        closing:retire()
        window:destroy()
        -- Native cancellation callbacks must survive destruction of the window.
        for _ = 1, 10 do Window.pump(window, 0.01) end
        write("reply", "closed")
        break
      else error("unknown probe command") end
    end
    if pending then
      local text, status = pending:poll()
      if status ~= "pending" then
        pending = nil
        write("reply", text ~= nil and "success:" .. text or status)
      end
    end
  end
end, debug.traceback)
if pending then pending:destroy() end
window:destroy()
assert(ok, message)
print("GTK Wayland PRIMARY passed: external owner/requester, Unicode, clipboard isolation, bounds, replacement, cancellation and window destruction.")
