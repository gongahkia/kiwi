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
  pty:shutdown()
  pty = Pty.spawn({ "/usr/bin/env", "python3", "-c", [[
import os, time, tty
tty.setraw(0)
os.write(1, b"ready")
time.sleep(0.2)
count = 0
while count < 262144:
    data = os.read(0, min(4096, 262144 - count))
    assert data and data == b"x" * len(data)
    count += len(data)
os.write(1, b"received:262144")
]] }, 40, 10, { TERM = "xterm-kiwi" })
  output, started = "", window:time()
  repeat
    window:watch_ptys({ pty })
    window:wait_events(2)
    output = output .. pty:read_available(4096)
    assert(window:time() - started < 1.5, "backpressure child did not become ready")
  until output == "ready"
  pty:enqueue(string.rep("x", 262144))
  pty:flush()
  assert(pty.pending_offset <= #pty.pending, "fixture failed to saturate the PTY input buffer")
  output, started = "", window:time()
  repeat
    window:watch_ptys({ pty })
    window:wait_events(2)
    pty:flush()
    output = output .. pty:read_available(4096)
    assert(window:time() - started < 1.5, "buffered input waited for the host's two-second fallback timeout")
  until output == "received:262144"
  assert(pty.bytes_written == 262144, "input readiness lost or duplicated bytes")
  print(string.format("PTY input wake smoke passed: 256 KiB delivered in %.1f ms under backpressure with a 2000 ms host timeout.", (window:time() - started) * 1000))
end, debug.traceback)
if pty then pty:shutdown() end
window:destroy()
assert(ok, message)
