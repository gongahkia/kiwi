-- measure a quiet interval after native startup allocation has settled.
local gtk = os.getenv("KIWI_HOST") == "gtk"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
assert(Host.presentation_backend ~= "gtk-gl", "idle wake fixture requires WGPU")
local Power = require("kiwi.bench.power")
local Pty = require("kiwi.process.pty")
local Compositor = require("kiwi.renderer.compositor")
local power_new, observe, spawn, render, await = Power.new, Power.observe, Pty.spawn, Compositor.render, Host.await_events
local recorder, options, pty, geometry, geometry_at, ready, armed_at, started
Power.new = function(value)
  options, recorder = value, power_new(value)
  return recorder
end
Power.observe = function(self, now, state, timeout, wait_started)
  if not armed_at then return end
  if wait_started and wait_started < armed_at then wait_started, timeout = armed_at, 0 end
  return observe(self, now, state, timeout, wait_started)
end
Pty.spawn = function(...) pty = spawn(...); return pty end
Compositor.render = function(self, entries, ...)
  local rendered, reason = render(self, entries, ...)
  if rendered then
    assert(#entries == 1, "idle wake fixture requires one terminal")
    local state = entries[1].model
    local current = string.format("%d:%d:%d:%d", self.context.width, self.context.height, state.columns, state.rows)
    if armed_at then assert(current == geometry, "idle interval interrupted by a geometry change")
    elseif current ~= geometry then geometry, geometry_at = current, self.context.window:time() end
    ready = state.title == "kiwi-idle-ready" and not state.modes.cursor_visible
  end
  return rendered, reason
end
Host.await_events = function(application, window, timeout)
  local result = await(application, window, armed_at and timeout or math.min(timeout, .01))
  local now = window:time()
  started = started or now
  if not armed_at then
    assert(now - started < 15, "idle startup did not settle")
    if ready and geometry_at and now - geometry_at >= .3 then
      local fresh = power_new(options)
      for key in pairs(recorder) do recorder[key] = nil end
      for key, value in pairs(fresh) do recorder[key] = value end
      armed_at = now
      pty:enqueue("quiet\n")
      pty:flush()
    end
  end
  return result
end
arg = { "--config", assert(os.getenv("KIWI_IDLE_CONFIG")), "--no-restore-layout", "--no-extensions",
  "--", "/bin/sh", "-c", "read unused; printf '\\033[?25l\\033]2;kiwi-idle-ready\\007'; read quiet; sleep 3" }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Power.new, Power.observe, Pty.spawn, Compositor.render, Host.await_events = power_new, observe, spawn, render, await
assert(ok, message)
assert(armed_at, "idle fixture ended before its quiet interval")
