-- Explicit endpoint diagnostic. Call only with no outstanding timed input,
-- after warmup and before native application teardown. Never collect inside
-- the measured interval or change the collector's settings.
local RetainedHeap = {}
RetainedHeap.__index = RetainedHeap

local function finite(value)
  return type(value) == "number" and value >= 0 and value < math.huge
end

local function copy_history(history)
  if not history then return nil end
  local copy = {}
  for _, name in ipairs({ "limit", "retained", "pushed", "evicted" }) do
    local value = history[name]
    assert(finite(value) and value % 1 == 0, "invalid retention history observation")
    copy[name] = value
  end
  assert(copy.limit > 0 and copy.retained == copy.limit, "retained-heap baseline requires full history; increase warmup")
  assert(copy.pushed == copy.retained + copy.evicted, "inconsistent retention history observation")
  return copy
end

local function copy_checkpoint(value)
  if not value then return nil end
  local copy = {}
  for key, item in pairs(value) do copy[key] = key == "history" and copy_history(item) or item end
  return copy
end

function RetainedHeap.new(clock, collector)
  assert(type(clock) == "function", "retained-heap measurement needs a monotonic clock")
  return setmetatable({ clock = clock, collector = collector or collectgarbage }, RetainedHeap)
end

function RetainedHeap:capture(label, history)
  assert(label == "initial" or label == "final", "unknown retention checkpoint")
  assert(not self[label] and (label == "initial" or self.initial), "retention checkpoints are out of order")
  history = copy_history(history)
  local started = self.clock()
  assert(finite(started) and (not self.initial or started >= self.initial.finished_at), "retention clock moved backwards")
  local before = self.collector("count")
  assert(finite(before), "invalid heap observation")
  self.collector("collect")
  local after, finished = self.collector("count"), self.clock()
  assert(finite(after) and finite(finished) and finished >= started, "invalid retention observation")
  self[label] = { started_at = started, finished_at = finished,
    collection_seconds = finished - started, before_kib = before, after_kib = after, history = history }
end

function RetainedHeap:observations()
  local result = { method = "full collection at initial/final boundaries while application remains live",
    initial = copy_checkpoint(self.initial), final = copy_checkpoint(self.final) }
  if self.initial and self.final then
    result.growth_kib = self.final.after_kib - self.initial.after_kib
    result.duration_seconds = self.final.started_at - self.initial.finished_at
  end
  return result
end

return RetainedHeap
