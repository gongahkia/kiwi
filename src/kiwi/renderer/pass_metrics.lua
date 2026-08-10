local Metrics = {}
Metrics.__index = Metrics

local function default_clock()
  return os.clock()
end

local function copy_sample(sample)
  return {
    name = sample.name,
    prepare_ms = sample.prepare_seconds * 1000,
    encode_ms = sample.encode_seconds * 1000,
    prepare_calls = sample.prepare_calls,
    encode_calls = sample.encode_calls,
  }
end

function Metrics.new(options)
  options = options or {}
  local history_limit = options.history_limit or 120
  assert(type(history_limit) == "number" and history_limit >= 1 and history_limit % 1 == 0, "pass metric history limit must be a positive integer")
  return setmetatable({
    enabled = options.enabled == true,
    clock = options.clock or default_clock,
    history_limit = history_limit,
    frame = 0,
    active = {},
    current = nil,
    history = {},
  }, Metrics)
end

function Metrics:begin_frame()
  if not self.enabled then return end
  self.frame = self.frame + 1
  self.current = {}
end

function Metrics:measure(name, stage, callback)
  if not self.enabled then return callback() end
  local started = self.clock()
  local result = { callback() }
  local elapsed = math.max(0, self.clock() - started)
  local sample = self.current[name]
  if sample == nil then
    sample = { name = name, prepare_seconds = 0, encode_seconds = 0, prepare_calls = 0, encode_calls = 0 }
    self.current[name] = sample
  end
  self.active[name] = true
  if stage == "prepare" then
    sample.prepare_seconds = sample.prepare_seconds + elapsed
    sample.prepare_calls = sample.prepare_calls + 1
  elseif stage == "encode" then
    sample.encode_seconds = sample.encode_seconds + elapsed
    sample.encode_calls = sample.encode_calls + 1
  else
    error("unknown pass metric stage " .. tostring(stage))
  end
  return unpack(result)
end

function Metrics:end_frame()
  if not self.enabled then return end
  local samples = {}
  for _, sample in pairs(self.current) do samples[#samples + 1] = copy_sample(sample) end
  table.sort(samples, function(left, right) return left.name < right.name end)
  self.history[#self.history + 1] = { frame = self.frame, passes = samples }
  while #self.history > self.history_limit do table.remove(self.history, 1) end
  self.current = nil
end

function Metrics:remove(name)
  if not self.enabled then return end
  self.active[name] = nil
  if self.current then self.current[name] = nil end
end

function Metrics:reset()
  if not self.enabled then return end
  self.frame = 0
  self.active = {}
  self.current = nil
  self.history = {}
end

function Metrics:snapshot()
  if not self.enabled then return { enabled = false, frame = 0, samples = {}, history = {} } end
  local history = {}
  for index, frame in ipairs(self.history) do
    local passes = {}
    for pass_index, sample in ipairs(frame.passes) do passes[pass_index] = copy_sample({
      name = sample.name,
      prepare_seconds = sample.prepare_ms / 1000,
      encode_seconds = sample.encode_ms / 1000,
      prepare_calls = sample.prepare_calls,
      encode_calls = sample.encode_calls,
    }) end
    history[index] = { frame = frame.frame, passes = passes }
  end
  local latest = history[#history]
  return { enabled = true, frame = self.frame, samples = latest and latest.passes or {}, history = history }
end

return Metrics
