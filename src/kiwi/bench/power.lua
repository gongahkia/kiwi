local Environment = require("kiwi.bench.environment")
local Json = require("kiwi.bench.json")

local Power = {}
Power.__index = Power
Power.maximum_report_bytes = 64 * 1024

local function increment(values, name)
  values[name] = (values[name] or 0) + 1
end

function Power.new(options)
  options = options or {}
  local active_poll_seconds = options.active_poll_seconds or 0.050
  local minimized_poll_seconds = options.minimized_poll_seconds or 0.250
  assert(type(active_poll_seconds) == "number" and active_poll_seconds > 0, "power active poll interval must be positive")
  assert(type(minimized_poll_seconds) == "number" and minimized_poll_seconds >= active_poll_seconds, "power minimized poll interval must not be below the active interval")
  return setmetatable({
    active_poll_seconds = active_poll_seconds,
    deferred = {},
    extension_animation_frames = 0,
    input_events = 0,
    synthetic_input_events = 0,
    output_events = 0,
    presented = 0,
    present_reasons = {},
    requested_wait_seconds = 0,
    state_seconds = { active = 0, idle = 0, minimized = 0 },
    state_wakes = { active = 0, idle = 0, minimized = 0 },
    last_state = nil,
    last_time = nil,
    minimized_poll_seconds = minimized_poll_seconds,
    wakes = 0,
  }, Power)
end

function Power:observe(now, state, requested_wait)
  assert(type(now) == "number", "power observation time must be numeric")
  assert(self.state_seconds[state] ~= nil, "unknown power state " .. tostring(state))
  if self.last_time ~= nil then
    self.state_seconds[self.last_state] = self.state_seconds[self.last_state] + math.max(0, now - self.last_time)
  end
  self.last_state = state
  self.last_time = now
  self.wakes = self.wakes + 1
  self.state_wakes[state] = self.state_wakes[state] + 1
  self.requested_wait_seconds = self.requested_wait_seconds + math.max(0, requested_wait or 0)
end

function Power:input(synthetic)
  self.input_events = self.input_events + 1
  if synthetic then self.synthetic_input_events = self.synthetic_input_events + 1 end
end

function Power:output()
  self.output_events = self.output_events + 1
end

function Power:defer(reason)
  increment(self.deferred, reason)
end

function Power:present(reasons, extensions)
  self.presented = self.presented + 1
  for _, reason in ipairs(reasons or {}) do increment(self.present_reasons, reason) end
  if extensions and next(extensions.animations or {}) then self.extension_animation_frames = self.extension_animation_frames + 1 end
end

function Power:finish(now)
  if self.finished or self.last_time == nil or now == nil then return end
  self.state_seconds[self.last_state] = self.state_seconds[self.last_state] + math.max(0, now - self.last_time)
  self.last_time = now
  self.finished = true
end

function Power:snapshot(now)
  self:finish(now)
  local elapsed = 0
  for _, seconds in pairs(self.state_seconds) do elapsed = elapsed + seconds end
  return {
    schema_version = 1,
    methodology = {
      power = "not measured: the report counts Kiwi loop wakeups and successful renderer returns, not battery discharge, package energy, GPU energy, compositor work, or scan-out",
      privacy = "counts and reason categories only; no terminal output, input bytes, clipboard, command, window title, or display identifier is retained",
      wakeup = "a wakeup is one return from Kiwi's GLFW wait loop; it is not an operating-system wakeup attribution",
    },
    policy = {
      active_poll_seconds = self.active_poll_seconds,
      minimized_poll_seconds = self.minimized_poll_seconds,
      extension_animation_hz = "bounded by KIWI_EXTENSION_MAX_ANIMATION_HZ from 1/60 through 60",
    },
    measurement = {
      deferred = self.deferred,
      elapsed_seconds = elapsed,
      extension_animation_frames = self.extension_animation_frames,
      input_events = self.input_events,
      output_events = self.output_events,
      presented = self.presented,
      present_reasons = self.present_reasons,
      requested_wait_seconds = self.requested_wait_seconds,
      state_seconds = self.state_seconds,
      state_wakes = self.state_wakes,
      synthetic_input_events = self.synthetic_input_events,
      wakes = self.wakes,
      wake_frequency_hz = elapsed > 0 and self.wakes / elapsed or 0,
    },
    unavailable = {
      battery_energy = "unavailable: Kiwi does not query battery or system energy counters",
      compositor_occlusion = "unavailable: GLFW exposes iconification but no portable occlusion callback",
      gpu_energy = "unavailable: WGPU timing does not provide energy or compositor accounting",
    },
  }
end

function Power.write_report(root, requested_path, recorder, now)
  assert(type(root) == "string" and #root > 0 and not root:find("\0", 1, true), "power root must be a non-empty NUL-free string")
  assert(type(requested_path) == "string" and #requested_path > 0 and not requested_path:find("\0", 1, true), "power report path must be a non-empty NUL-free string")
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local path = requested_path == "1" and root .. "/bench/results/" .. timestamp .. "-power.json" or requested_path
  local snapshot = recorder:snapshot(now)
  local report = {
    schema_version = snapshot.schema_version,
    benchmark = "Kiwi redraw scheduling observation",
    metadata = Environment.collect_pacing(timestamp, snapshot.measurement),
    methodology = snapshot.methodology,
    policy = snapshot.policy,
    measurement = snapshot.measurement,
    unavailable = snapshot.unavailable,
  }
  local encoded = Json.encode(report)
  assert(#encoded + 1 <= Power.maximum_report_bytes, "power report exceeds 65536 bytes")
  local file, message = io.open(path, "wb")
  if not file then error("Unable to write power report " .. path .. ": " .. tostring(message), 2) end
  file:write(encoded, "\n")
  file:close()
  return path
end

return Power
