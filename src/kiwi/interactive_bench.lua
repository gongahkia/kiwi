-- Test-process instrumentation of the real WGPU controller and presentation.
local Metrics = require("kiwi.bench.process_metrics")
local Interactive = require("kiwi.bench.interactive")
local Json = require("kiwi.bench.json")
local Sustained = require("kiwi.bench.sustained")
local Terminal = require("kiwi.session.terminal")
local Scrollback = require("kiwi.terminal.scrollback")
local Pty = require("kiwi.process.pty")
local OutputService = require("kiwi.process.output_service")
local Compositor = require("kiwi.renderer.compositor")
local gtk = os.getenv("KIWI_HOST") == "gtk"
local scroll_mode = os.getenv("KIWI_INTERACTIVE_BENCH_SCROLL_MODE") or "region"
assert(scroll_mode == "region" or scroll_mode == "history")
local history = { pushed = 0, evicted = 0, peak_retained = 0 }
local keep_visible = os.getenv("KIWI_INTERACTIVE_BENCH_KEEP_VISIBLE") == "1"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
local Window = require(gtk and "kiwi.platform.gtk_window" or "kiwi.platform.window")
assert(Host.presentation_backend ~= "gtk-gl", "interactive benchmark currently requires WGPU presentation")

local mode = assert(os.getenv("KIWI_INTERACTIVE_BENCH_MODE"))
assert(mode == "idle" or mode == "saturated", "invalid interactive workload")
local measurement = Interactive.new({ launched_at = tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_LAUNCHED_AT")),
  samples = tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_SAMPLES")),
  warmup = tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_WARMUP")) })
local interval = assert(tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_INTERVAL")))
local trial_timeout = tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_TIMEOUT")) or 30
local soak_seconds = tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_SOAK")) or 0
assert(trial_timeout >= 30 and trial_timeout <= 3600 and interval >= 0 and interval <= 120)
assert((measurement.samples + measurement.warmup - 1) * interval <= trial_timeout - 10, "interactive intervals exceed the trial budget")
local sustained = soak_seconds > 0 and Sustained.new(trial_timeout) or nil
local originals = { history_push = Scrollback.push, new_terminal = Terminal.new, write = Terminal.write, read = Pty.read_available,
  new_window = Window.new, render = Compositor.render, await = Host.await_events }
local live, window, geometry, stable_geometry, font_path, adapter, next_input, report
local output_bytes, measured_output_bytes, peak_rss = 0, 0, 0
local failure_state
local invalid_measurement
local presentation = { attempts = 0, successful = 0, failures = {} }
local last_compositor, last_entries
local deadline = measurement.launched_at + trial_timeout
assert(mode == "idle" or measurement.warmup >= 1, "saturated measurement requires warmup")

if scroll_mode == "history" then
  Scrollback.push = function(self, row)
    local evicted = originals.history_push(self, row)
    if live and self == Terminal.state(live).scrollback then
      history.pushed = history.pushed + 1
      if evicted then history.evicted = history.evicted + 1 end
      history.limit, history.retained = self.limit, self:size()
      history.peak_retained = math.max(history.peak_retained, history.retained)
      assert(history.retained <= self.limit, "scrollback exceeded its configured capacity")
    end
    return evicted
  end
end

Terminal.new = function(...) live = originals.new_terminal(...); return live end
Window.new = function(_, _, title, options)
  window = originals.new_window(800, 480, title, options)
  if keep_visible then
    local ffi = require("ffi")
    assert(not gtk and ffi.os == "OSX", "floating benchmark requires macOS GLFW")
    ffi.cdef[[void glfwSetWindowAttrib(GLFWwindow* window, int attrib, int value);]]
    local glfw = require("kiwi.ffi.glfw")
    local floating = 0x00020007 -- GLFW_FLOATING, GLFW 3.4 public header.
    glfw.lib.glfwSetWindowAttrib(window.handle, floating, 1)
    assert(glfw.lib.glfwGetWindowAttrib(window.handle, floating) == 1, "benchmark window did not become floating")
  end
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
local function sequence(state)
  return Interactive.visible_sequence(state, scroll_mode == "history" and state.columns - 9 or 0)
end
Terminal.write = function(self, bytes)
  local result = originals.write(self, bytes)
  local acknowledged = sequence(Terminal.state(self))
  if acknowledged and acknowledged > 0 then measurement:parsed(acknowledged, Metrics.monotonic_seconds()) end
  return result
end
Compositor.render = function(self, entries, ...)
  last_compositor, last_entries = self, entries
  presentation.attempts = presentation.attempts + 1
  local rendered, reason = originals.render(self, entries, ...)
  local now = Metrics.monotonic_seconds()
  presentation.last_attempt_at = now
  if not rendered then
    local label = tostring(reason or "unspecified"):sub(1, 128)
    presentation.failures[label] = (presentation.failures[label] or 0) + 1
    presentation.last_failure_reason, presentation.last_failure_at = label, now
    if measurement.ready_at and (reason == "surface occluded" or reason == "zero-sized drawable") then
      invalid_measurement = "visible-window measurement interrupted: " .. reason
      error(invalid_measurement)
    end
  end
  if rendered then
    presentation.successful = presentation.successful + 1
    assert(#entries == 1, "interactive benchmark requires one pane")
    local state = entries[1].model
    if state.history_offset ~= 0 then
      invalid_measurement = "visible-window measurement interrupted: viewport left live output"
      error(invalid_measurement)
    end
    local acknowledged = sequence(state)
    local completed = measurement:present(now, acknowledged)
    local rss = assert(Metrics.resident_kib())
    peak_rss = math.max(peak_rss, rss)
    if sustained and measurement.ready_at and measurement.completed >= measurement.warmup then
      sustained:observe(now, rss, collectgarbage("count"), os.clock(), measurement:done(),
        scroll_mode == "history" and history.limit and history or nil)
    end
    geometry = { columns = state.columns, rows = state.rows, cell_width = state.cell_width, cell_height = state.cell_height }
    if measurement.ready_at then
      if stable_geometry then
        for name, value in pairs(stable_geometry) do assert(geometry[name] == value, "terminal geometry changed during measurement") end
      else stable_geometry = geometry end
    end
    font_path = entries[1].renderer.font.font_path
    adapter = self.context.adapter_info
    if completed then next_input = now + interval end
    if measurement:done() then
      report = measurement:snapshot()
      report.output_bytes_observed = output_bytes
      report.output_bytes_after_ready = measured_output_bytes
      report.ready_to_last_present_seconds = now - measurement.ready_at
      report.sampled_peak_rss_kib = peak_rss
      report.process_cpu_seconds = os.clock()
      if sustained then report.sustained = sustained:snapshot() end
      if mode == "saturated" then
        -- Reserve more than each acknowledgment's maximum protocol overhead,
        -- then require an additional 4 KiB of real background traffic. Requiring
        -- 4 KiB per input would reject a faster acknowledgment on the same load.
        assert(measured_output_bytes > measurement.completed * 256 + 4096,
          "saturated workload produced insufficient background output")
      end
      window:request_close()
    end
  end
  return rendered, reason
end
Host.await_events = function(application, current_window, timeout)
  local now = Metrics.monotonic_seconds()
  if measurement.ready_at and current_window.minimized then
    invalid_measurement = "visible-window measurement interrupted: window minimized"
    error(invalid_measurement)
  end
  if now >= deadline then
    error(string.format("interactive fixture exceeded its %.0f-second deadline: ready=%s sent=%d completed=%d output=%d title=%s",
      trial_timeout, tostring(measurement.ready_at), measurement.sent, measurement.completed, output_bytes, tostring(Terminal.state(live).title)))
  end
  local pending = measurement.pending
  if pending then
    failure_state = { sequence = pending.sequence, elapsed_seconds = now - pending.input_at,
      parsed = pending.parsed_at ~= nil, minimized = current_window.minimized == true,
      present_age_seconds = measurement.last_present and now - measurement.last_present,
      visible_sequence = sequence(Terminal.state(live)), output_bytes = output_bytes }
    if now - pending.input_at >= Interactive.maximum_response_seconds then
      if last_compositor then
        failure_state.can_present = last_compositor:can_present(last_entries)
        failure_state.needs_render = last_compositor:needs_render(last_entries, current_window:time())
        failure_state.retry_delay_seconds = last_compositor.retry_at and last_compositor.retry_at - current_window:time()
      end
      error("acknowledgment exceeded the two-second responsiveness ceiling")
    end
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
Scrollback.push = originals.history_push
Window.new, Compositor.render, Host.await_events = originals.new_window, originals.render, originals.await
if not ok or not report then
  report = measurement:observations()
  report.output_bytes_observed = output_bytes
  report.sampled_peak_rss_kib = peak_rss
  report.failure_state = failure_state
  if sustained and #sustained.values >= 5 then report.sustained = sustained:snapshot() end
end
if scroll_mode == "history" then report.history = history end
local metadata = require("kiwi.bench.environment").collect(os.date("!%Y%m%dT%H%M%SZ"), measurement.samples, measurement.warmup)
metadata.configuration = { samples = measurement.samples, warmup_inputs = measurement.warmup, interval_seconds = interval,
  pty_read_budget = tonumber(os.getenv("KIWI_PTY_READ_BUDGET")),
  pty_read_chunk_bytes = OutputService.chunk_bytes, output_service_target_seconds = OutputService.max_seconds,
  requested_window_points = { width = 800, height = 480 },
  geometry = geometry, primary_font_path = font_path, host = gtk and "gtk" or "glfw", presenter = "wgpu", workload = mode,
  traffic = os.getenv("KIWI_INTERACTIVE_BENCH_TRAFFIC") or "ascii", soak_seconds = soak_seconds, trial_timeout_seconds = trial_timeout,
  floating_window = keep_visible, scroll_mode = scroll_mode,
  scrollback_limit = tonumber(os.getenv("KIWI_INTERACTIVE_BENCH_SCROLLBACK_LIMIT")) or 2000 }
metadata.methodology = nil -- The enclosing report specifies this fixture's clocks and boundaries.
metadata.native_adapter = adapter
local result = { schema_version = 1, metadata = metadata, measurement = report,
  status = invalid_measurement and "invalid" or ok and measurement:done() and "complete" or "failed",
  failure = invalid_measurement or not ok and tostring(message):sub(1, 4096) or nil }
result.presentation = presentation
local encoded = Json.encode(result)
assert(#encoded <= 128 * 1024, "interactive trial report exceeded 128 KiB")
local file = assert(io.open(assert(os.getenv("KIWI_INTERACTIVE_BENCH_TRIAL_REPORT")), "wb"))
assert(file:write(encoded, "\n")); assert(file:close())
assert(ok, message)
assert(measurement:done(), "interactive benchmark closed before completion")
