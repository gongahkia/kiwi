local Window = require(os.getenv("KIWI_HOST") == "gtk" and "kiwi.platform.gtk_window" or "kiwi.platform.window")
local Pty = require("kiwi.process.pty")

local window = Window.new(320, 240, "Kiwi PTY readiness smoke")
local pty
local ok, message = xpcall(function()
  window:poll_events()
  pty = Pty.spawn({ "/bin/sh", "-c", "sleep 0.05; printf kiwi-ready" }, 40, 10, { TERM = "xterm-kiwi" })
  local started, output = window:time(), ""
  repeat
    window:watch_ptys({ pty })
    window:wait_events(2)
    output = output .. pty:read_available(4096)
    assert(window:time() - started < 1.5, "PTY output waited for the host's two-second timeout")
  until output == "kiwi-ready"
  print(string.format("PTY host wake smoke passed: output observed in %.1f ms with a 2000 ms host timeout.", (window:time() - started) * 1000))
end, debug.traceback)
if pty then pty:shutdown() end
window:destroy()
assert(ok, message)
