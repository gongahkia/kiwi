local Environment = require("kiwi.bench.environment")
local Json = require("kiwi.bench.json")
local Stats = require("kiwi.bench.stats")

local Pacing = {}
Pacing.__index = Pacing
Pacing.maximum_report_bytes = 64 * 1024

local function append(recorder, name, value)
  local samples = recorder[name]
  if #samples == recorder.sample_limit then
    table.remove(samples, 1)
    recorder.dropped[name] = recorder.dropped[name] + 1
  end
  samples[#samples + 1] = value
end

local function summary(samples, dropped)
  if #samples == 0 then
    return { status = "unavailable", count = 0, dropped_samples = dropped }
  end
  local result = Stats.summary(samples)
  local minimum, maximum = samples[1], samples[1]
  local squared_difference = 0
  for _, value in ipairs(samples) do
    if value < minimum then minimum = value end
    if value > maximum then maximum = value end
    local difference = value - result.mean
    squared_difference = squared_difference + difference * difference
  end
  result.status = "measured"
  result.minimum = minimum
  result.maximum = maximum
  result.standard_deviation = math.sqrt(squared_difference / #samples)
  result.dropped_samples = dropped
  return result
end

local function reason_counts(reasons, target)
  for _, reason in ipairs(reasons or {}) do
    target[reason] = (target[reason] or 0) + 1
  end
end

function Pacing.new(options)
  options = options or {}
  local sample_limit = options.sample_limit or 240
  local warmup_frames = options.warmup_frames or 30
  local pty_read_budget = options.pty_read_budget or 4 * 1024
  assert(type(sample_limit) == "number" and sample_limit >= 1 and sample_limit % 1 == 0, "pacing sample_limit must be a positive integer")
  assert(type(warmup_frames) == "number" and warmup_frames >= 0 and warmup_frames % 1 == 0, "pacing warmup_frames must be a non-negative integer")
  assert(type(pty_read_budget) == "number" and pty_read_budget >= 1 and pty_read_budget % 1 == 0, "pacing pty_read_budget must be a positive integer")
  return setmetatable({
    frame_cpu_ms = {},
    frame_interval_ms = {},
    input_to_present_ms = {},
    output_to_present_ms = {},
    dropped = { frame_cpu_ms = 0, frame_interval_ms = 0, input_to_present_ms = 0, output_to_present_ms = 0 },
    input_events = 0,
    output_events = 0,
    pending_input = nil,
    pending_input_ready = nil,
    pending_output = nil,
    present_count = 0,
    present_reasons = {},
    previous_present = nil,
    sample_limit = sample_limit,
    warmup_frames = warmup_frames,
    pty_read_budget = pty_read_budget,
  }, Pacing)
end

function Pacing:input(time)
  assert(type(time) == "number", "pacing input time must be numeric")
  self.input_events = self.input_events + 1
  if self.pending_input == nil then self.pending_input = time end
end

function Pacing:output(time)
  assert(type(time) == "number", "pacing output time must be numeric")
  self.output_events = self.output_events + 1
  if self.pending_output == nil then self.pending_output = time end
  if self.pending_input ~= nil then self.pending_input_ready = self.pending_input end
end

function Pacing:present(frame_started, completed, reasons)
  assert(type(frame_started) == "number" and type(completed) == "number" and completed >= frame_started, "pacing present times must be monotonic")
  self.present_count = self.present_count + 1
  reason_counts(reasons, self.present_reasons)
  local measured = self.present_count > self.warmup_frames
  if measured then
    append(self, "frame_cpu_ms", (completed - frame_started) * 1000)
    if self.previous_present ~= nil then
      append(self, "frame_interval_ms", (completed - self.previous_present) * 1000)
    end
    if self.pending_input_ready ~= nil then
      append(self, "input_to_present_ms", (completed - self.pending_input_ready) * 1000)
    end
    if self.pending_output ~= nil then
      append(self, "output_to_present_ms", (completed - self.pending_output) * 1000)
    end
  end
  self.previous_present = completed
  if self.pending_input_ready ~= nil then
    self.pending_input = nil
    self.pending_input_ready = nil
  end
  self.pending_output = nil
end

function Pacing:snapshot()
  return {
    schema_version = 1,
    methodology = {
      clock = "GLFW monotonic time sampled at terminal event handling and after Renderer:render returns",
      frame_cpu_ms = "CPU time from renderer update start through the return after wgpuSurfacePresent; GPU execution, compositor scheduling, and panel scan-out are excluded",
      frame_interval_ms = "interval between successful Renderer:render returns; its standard deviation is pacing variance, not display refresh accuracy",
      input_to_present_ms = "earliest coalesced PTY input through the first later PTY output and successful Renderer:render return; local actions and input with no observed output are unavailable",
      output_to_present_ms = "earliest coalesced PTY output through successful Renderer:render return",
      privacy = "aggregates and invalidation-reason counts only; no key bytes, terminal output, clipboard, command, or display identifier is recorded",
    },
    measurement = {
      frame_cpu_ms = summary(self.frame_cpu_ms, self.dropped.frame_cpu_ms),
      frame_interval_ms = summary(self.frame_interval_ms, self.dropped.frame_interval_ms),
      input_to_present_ms = summary(self.input_to_present_ms, self.dropped.input_to_present_ms),
      output_to_present_ms = summary(self.output_to_present_ms, self.dropped.output_to_present_ms),
      present_count = self.present_count,
      warmup_frames = self.warmup_frames,
      sample_limit = self.sample_limit,
      pty_read_budget = self.pty_read_budget,
      maximum_report_bytes = Pacing.maximum_report_bytes,
      input_events = self.input_events,
      output_events = self.output_events,
      present_reasons = self.present_reasons,
    },
    unavailable = {
      display_scanout_latency = "unavailable: no photodiode or compositor presentation-feedback measurement",
      gpu_execution_latency = "unavailable: asynchronous GPU timestamps do not measure terminal event to display latency",
    },
  }
end

function Pacing.write_report(root, requested_path, recorder, renderer)
  assert(type(root) == "string" and #root > 0 and not root:find("\0", 1, true), "pacing root must be a non-empty NUL-free string")
  assert(type(requested_path) == "string" and #requested_path > 0 and not requested_path:find("\0", 1, true), "pacing report path must be a non-empty NUL-free string")
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local path = requested_path == "1" and root .. "/bench/results/" .. timestamp .. "-pacing.json" or requested_path
  local snapshot = recorder:snapshot()
  local gpu_timing = renderer and renderer.diagnostics and renderer.diagnostics.gpu_timing or nil
  local report = {
    schema_version = snapshot.schema_version,
    engine = "Kiwi frame pacing methodology",
    metadata = Environment.collect_pacing(timestamp, snapshot.measurement),
    methodology = snapshot.methodology,
    measurement = snapshot.measurement,
    unavailable = snapshot.unavailable,
    gpu_timing = gpu_timing and {
      enabled = gpu_timing.enabled == true,
      status = gpu_timing.status or "unavailable",
    } or { enabled = false, status = "unavailable" },
  }
  local encoded = Json.encode(report)
  if #encoded + 1 > Pacing.maximum_report_bytes then
    error("Pacing report exceeds " .. Pacing.maximum_report_bytes .. " bytes", 2)
  end
  local file, message = io.open(path, "wb")
  if not file then error("Unable to write pacing report " .. path .. ": " .. tostring(message), 2) end
  file:write(encoded, "\n")
  file:close()
  return path
end

return Pacing
