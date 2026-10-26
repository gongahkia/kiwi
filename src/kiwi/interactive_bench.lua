-- Test-process instrumentation of the real WGPU controller and presentation.
local Metrics = require("kiwi.bench.process_metrics")
local Interactive = require("kiwi.bench.interactive")
local Json = require("kiwi.bench.json")
local Terminal = require("kiwi.session.terminal")
local Pty = require("kiwi.process.pty")
local Compositor = require("kiwi.renderer.compositor")
local gtk = os.getenv("KIWI_HOST") == "gtk"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
local Window = require(gtk and "kiwi.platform.gtk_window" or "kiwi.platform.window")
assert(Host.presentation_backend ~= "gtk-gl", "interactive benchmark currently requires WGPU presentation")

local mode = assert(os.getenv("KIWI_INTERACTIVE_BENCH_MODE"))
assert(mode == "idle" or mode == "saturated", "invalid interactive workload")
local measurement = Interactive.new({ launched_at = tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_LAUNCHED_AT")),
  samples = tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_SAMPLES")),
  warmup = tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_WARMUP")) })
local interval = assert(tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_INTERVAL")))
assert(interval >= 0 and interval <= 1)
assert((measurement.samples + measurement.warmup - 1) * interval <= 20, "interactive intervals exceed the trial budget")
local originals = { new_terminal = Terminal.new, write = Terminal.write, read = Pty.read_available,
  new_window = Window.new, render = Compositor.render, await = Host.await_events }
local live, window, geometry, stable_geometry, font_path, next_input, report
local output_bytes, measured_output_bytes, peak_rss = 0, 0, 0
local deadline = measurement.launched_at + 30
assert(mode == "idle" or measurement.warmup >= 1, "saturated measurement requires warmup")

Terminal.new = function(...) live = originals.new_terminal(...); return live end
Window.new = function(_, _, title, options)
  window = originals.new_window(800, 480, title, options)
  return window
end
Pty.read_available = function(self, ...)
  local bytes = originals.read(self, ...)
  output_bytes = output_bytes + #bytes
  if measurement.ready_at then measured_output_bytes = measured_output_bytes + #bytes end
  return bytes
end
-- A PTY read may split the header/text. Only complete matching visible text
-- acknowledges input; the header precedes it so its last byte causes damage.
local sequence = Interactive.visible_sequence
Terminal.write = function(self, bytes)
  local result = originals.write(self, bytes)
  local acknowledged = sequence(Terminal.state(self))
  if acknowledged and acknowledged > 0 then measurement:parsed(acknowledged, Metrics.monotonic_seconds()) end
  return result
end
Compositor.render = function(self, entries, ...)
  local rendered, reason = originals.render(self, entries, ...)
  local now = Metrics.monotonic_seconds()
  if rendered then
    assert(#entries == 1, "interactive benchmark requires one pane")
    local state = entries[1].model
    local acknowledged = sequence(state)
    local completed = measurement:present(now, acknowledged)
    peak_rss = math.max(peak_rss, assert(Metrics.resident_kib()))
    geometry = { columns = state.columns, rows = state.rows, cell_width = state.cell_width, cell_height = state.cell_height }
    if measurement.ready_at then
      if stable_geometry then
        for name, value in pairs(stable_geometry) do assert(geometry[name] == value, "terminal geometry changed during measurement") end
      else stable_geometry = geometry end
    end
    font_path = entries[1].renderer.font.font_path
    if completed then next_input = now + interval end
    if measurement:done() then
      report = measurement:snapshot()
      report.output_bytes_observed = output_bytes
      report.output_bytes_after_ready = measured_output_bytes
      report.ready_to_last_present_seconds = now - measurement.ready_at
      report.sampled_peak_rss_kib = peak_rss
      report.process_cpu_seconds = os.clock()
      if mode == "saturated" then
        assert(measured_output_bytes > measurement.completed * 4096, "saturated workload produced insufficient background output")
      end
      window:request_close()
    end
  end
  return rendered, reason
end
Host.await_events = function(application, current_window, timeout)
  local now = Metrics.monotonic_seconds()
  if now >= deadline then
    error(string.format("interactive fixture exceeded its 30-second deadline: ready=%s sent=%d completed=%d output=%d title=%s",
      tostring(measurement.ready_at), measurement.sent, measurement.completed, output_bytes, tostring(Terminal.state(live).title)))
  end
  local pending = measurement.pending
  if pending then
    assert(now - pending.input_at < Interactive.maximum_response_seconds, "acknowledgment exceeded the two-second responsiveness ceiling")
    timeout = math.min(timeout, pending.input_at + Interactive.maximum_response_seconds - now)
  elseif measurement.ready_at and not measurement:done() then
    next_input = next_input or now
    if now >= next_input then
      measurement:input(now)
      assert(type(current_window.on_text) == "function")
      current_window.on_text({ string.byte("x") })
      -- Input was enqueued after the normal scheduler armed its PTY watch.
      -- Return immediately so the controller can flush/rearm it.
      timeout = 0
    else timeout = math.min(timeout, next_input - now) end
  end
  return originals.await(application, current_window, math.min(timeout, deadline - now))
end

arg = { "--config", assert(os.getenv("KIWI_INTERACTIVE_BENCH_CONFIG")), "--no-restore-layout", "--no-extensions",
  "--", assert(os.getenv("KIWI_INTERACTIVE_BENCH_PYTHON")), "script/interactive-bench-child", mode }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Terminal.new, Terminal.write, Pty.read_available = originals.new_terminal, originals.write, originals.read
Window.new, Compositor.render, Host.await_events = originals.new_window, originals.render, originals.await
assert(ok, message)
assert(report, "interactive benchmark closed before completion")
local metadata = require("kiwi.bench.environment").collect(os.date("!%Y%m%dT%H%M%SZ"), measurement.samples, measurement.warmup)
metadata.configuration = { samples = measurement.samples, warmup_inputs = measurement.warmup, interval_seconds = interval,
  pty_read_budget = tonumber(os.getenv("KIWI_PTY_READ_BUDGET")), requested_window_points = { width = 800, height = 480 },
  geometry = geometry, primary_font_path = font_path, host = gtk and "gtk" or "glfw", presenter = "wgpu", workload = mode,
  traffic = os.getenv("KIWI_INTERACTIVE_BENCH_TRAFFIC") or "ascii" }
metadata.methodology = nil -- The enclosing report specifies this fixture's clocks and boundaries.
local result = { schema_version = 1, metadata = metadata, measurement = report }
local encoded = Json.encode(result)
assert(#encoded <= 64 * 1024, "interactive trial report exceeded 64 KiB")
local file = assert(io.open(assert(os.getenv("KIWI_INTERACTIVE_BENCH_TRIAL_REPORT")), "wb"))
assert(file:write(encoded, "\n")); assert(file:close())
