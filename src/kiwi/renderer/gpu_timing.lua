local GpuTiming = {}
GpuTiming.__index = GpuTiming

local function copy_sample(sample)
  return {
    frame = sample.frame,
    name = sample.name,
    gpu_ticks = sample.gpu_ticks,
    map_latency_ms = sample.map_latency_ms,
  }
end

local function status_for(context)
  if context.timestamp_status then return context:timestamp_status() end
  return { requested = false, supported = false, enabled = false, reason = "context does not expose timestamp status" }
end

local function native_backend(context)
  local surface = context.native.surface
  local ffi = context.native.ffi
  return {
    create = function(pass_count)
      surface.kiwi_surface_clear_error()
      local tracker = surface.kiwi_timestamp_tracker_new(context.instance, context.device, pass_count)
      if tracker == nil then return nil, ffi.string(surface.kiwi_surface_last_error()) end
      return tracker
    end,
    destroy = function(tracker)
      surface.kiwi_timestamp_tracker_destroy(tracker)
    end,
    begin = function(tracker, frame)
      return surface.kiwi_timestamp_tracker_begin(tracker, frame) ~= 0
    end,
    writes = function(tracker, pass_index)
      return surface.kiwi_timestamp_tracker_writes(tracker, pass_index)
    end,
    resolve = function(tracker, encoder)
      surface.kiwi_timestamp_tracker_resolve(tracker, encoder)
    end,
    submit = function(tracker)
      surface.kiwi_timestamp_tracker_submit(tracker)
    end,
    poll = function(tracker, pass_count)
      local samples = ffi.new("KiwiTimestampSample[?]", pass_count)
      local count = surface.kiwi_timestamp_tracker_poll(tracker, samples, pass_count)
      if count < 0 then return nil, ffi.string(surface.kiwi_surface_last_error()) end
      local result = {}
      for index = 0, count - 1 do
        result[#result + 1] = {
          frame = tonumber(samples[index].frame),
          pass_index = tonumber(samples[index].pass_index),
          begin_ticks = tonumber(samples[index].begin_ticks),
          end_ticks = tonumber(samples[index].end_ticks),
          map_latency_ms = tonumber(samples[index].map_latency_ns) / 1000000,
        }
      end
      return result
    end,
    pending = function(tracker)
      return tonumber(surface.kiwi_timestamp_tracker_pending(tracker))
    end,
    dropped = function(tracker)
      return tonumber(surface.kiwi_timestamp_tracker_dropped(tracker))
    end,
  }
end

function GpuTiming.new(context, passes, options)
  options = options or {}
  local status = status_for(context)
  local history_limit = options.history_limit or 120
  assert(type(history_limit) == "number" and history_limit >= 1 and history_limit % 1 == 0, "GPU timing history limit must be a positive integer")
  local names = {}
  for _, pass in ipairs(passes) do
    if pass.pipeline ~= nil then names[#names + 1] = pass.name end
  end
  if not status.enabled then
    return setmetatable({ enabled = false, status = status.reason or "unsupported", names = names, history_limit = history_limit, history = {} }, GpuTiming)
  end
  if #names == 0 then
    return setmetatable({ enabled = false, status = "renderer has no GPU passes", names = names, history_limit = history_limit, history = {} }, GpuTiming)
  end
  local backend = options.backend or native_backend(context)
  local tracker, message = backend.create(#names)
  if tracker == nil then
    return setmetatable({ enabled = false, status = message or "timestamp tracker allocation failed", names = names, history_limit = history_limit, history = {} }, GpuTiming)
  end
  return setmetatable({
    enabled = true,
    status = "pending",
    names = names,
    name_indexes = {},
    backend = backend,
    tracker = tracker,
    history_limit = history_limit,
    history = {},
    frame = 0,
    active = false,
    errors = 0,
  }, GpuTiming)
end

function GpuTiming:begin_frame()
  if not self.enabled then return false end
  self.frame = self.frame + 1
  self.active = self.backend.begin(self.tracker, self.frame)
  return self.active
end

function GpuTiming:writes(name)
  if not self.active then return nil end
  local index = self.name_indexes[name]
  if index == nil then
    for candidate, value in ipairs(self.names) do
      if value == name then
        index = candidate - 1
        self.name_indexes[name] = index
        break
      end
    end
  end
  if index == nil then return nil end
  return self.backend.writes(self.tracker, index)
end

function GpuTiming:resolve(encoder)
  if self.active then self.backend.resolve(self.tracker, encoder) end
end

function GpuTiming:submit()
  if self.active then self.backend.submit(self.tracker) end
  self.active = false
end

function GpuTiming:poll()
  if not self.enabled then return end
  local samples, message = self.backend.poll(self.tracker, #self.names)
  if samples == nil then
    self.status = "error: " .. tostring(message)
    self.errors = self.errors + 1
    return
  end
  if #samples == 0 then return end
  local frame = { frame = samples[1].frame, passes = {} }
  for _, sample in ipairs(samples) do
    local name = self.names[sample.pass_index + 1]
    if name then
      frame.passes[#frame.passes + 1] = {
        frame = sample.frame,
        name = name,
        gpu_ticks = math.max(0, sample.end_ticks - sample.begin_ticks),
        map_latency_ms = sample.map_latency_ms,
      }
    end
  end
  table.sort(frame.passes, function(left, right) return left.name < right.name end)
  self.history[#self.history + 1] = frame
  while #self.history > self.history_limit do table.remove(self.history, 1) end
  self.status = "supported"
end

function GpuTiming:snapshot()
  local history = {}
  for index, frame in ipairs(self.history) do
    local passes = {}
    for pass_index, sample in ipairs(frame.passes) do passes[pass_index] = copy_sample(sample) end
    history[index] = { frame = frame.frame, passes = passes }
  end
  local latest = history[#history]
  return {
    enabled = self.enabled,
    status = self.status,
    frame = self.frame,
    pending = self.enabled and self.backend.pending(self.tracker) or 0,
    dropped = self.enabled and self.backend.dropped(self.tracker) or 0,
    errors = self.errors or 0,
    samples = latest and latest.passes or {},
    history = history,
  }
end

function GpuTiming:destroy()
  if self.tracker then
    self.backend.destroy(self.tracker)
    self.tracker = nil
  end
end

return GpuTiming
