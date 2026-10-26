local Window = require("kiwi.platform.window")
local Accessibility = require("kiwi.ffi.accessibility")
local Pty = require("kiwi.process.pty")
assert(os.getenv("KIWI_MAIN_CONTEXT_ISOLATED") == "1", "run the isolated main-context-wake-smoke script")
local address = assert(os.getenv("KIWI_TEST_ATSPI_ADDRESS"), "private AT-SPI bus address is required")
local window, adapter, child
local ok, message = xpcall(function()
  window = Window.new(320, 240, "Kiwi idle accessibility readiness")
  adapter = assert(Accessibility.new(window))
  local text = "kiwi-idle-accessibility"
  assert(adapter:update({ text = text, character_count = #text, caret_offset = 0,
    selection_start = -1, selection_end = -1 }, "Kiwi readiness fixture", true))
  local bus = adapter:bus_name()
  assert(#bus > 0)
  local maximum_ms = 0
  for request = 1, 5 do
    -- Do not call adapter:poll(): only the GLFW event bridge may dispatch
    -- these real D-Bus method calls while the host waits for two seconds.
    window:poll_events()
    child = Pty.spawn({ "/usr/bin/gdbus", "call", "--address", address, "--dest", bus,
      "--object-path", "/org/a11y/atspi/accessible/terminal", "--method", "org.a11y.atspi.Text.GetText",
      "0", "--", "-1" }, 40, 10, { TERM = "xterm-kiwi" })
    local started, output = window:time(), ""
    repeat
      window:watch_ptys({ child })
      window:wait_events(2)
      output = output .. child:read_available(4096)
      assert(#output <= 4096, "unexpected unbounded accessibility consumer output")
      assert(window:time() - started < 1.5, "AT-SPI request waited for the two-second host timeout")
      assert(not child.eof or output:find(text, 1, true), "AT-SPI consumer failed: " .. output)
    until output:find(text, 1, true)
    maximum_ms = math.max(maximum_ms, (window:time() - started) * 1000)
    window:watch_ptys({})
    child:shutdown(); child = nil
  end
  local quiet = false
  for _ = 1, 10 do
    local started = window:time()
    window:wait_events(0.1)
    if window:time() - started >= 0.08 then quiet = true; break end
  end
  assert(quiet, "GLib readiness created a self-sustaining idle wake loop")
  print(string.format("GLFW accessibility readiness smoke passed: five native AT-SPI text queries, maximum %.1f ms with a 2000 ms host timeout and no provider polling.", maximum_ms))
end, debug.traceback)
if child then child:shutdown() end
if adapter then adapter:destroy() end
if window then window:destroy() end
assert(ok, message)
