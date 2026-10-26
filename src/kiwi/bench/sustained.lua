-- Bounded post-warmup resource observations. No forced GC or extra wake timer.
local Stats = require("kiwi.bench.stats")
local Sustained = {}
Sustained.__index = Sustained
Sustained.maximum_samples = 256

local function finite(value)
  return type(value) == "number" and value >= 0 and value < math.huge
end

function Sustained.new(timeout)
  assert(finite(timeout) and timeout >= 30 and timeout <= 3600, "invalid sustained deadline")
  return setmetatable({ interval = timeout / (Sustained.maximum_samples - 2), values = {} }, Sustained)
end

function Sustained:observe(now, rss, heap, cpu, final)
  assert(finite(now) and finite(rss) and finite(heap) and finite(cpu), "invalid resource observation")
  local previous = self.values[#self.values]
  if previous then
    assert(now >= previous.at and cpu >= previous.cpu_seconds, "resource clock moved backwards")
    if not final and now - previous.at < self.interval then return false end
    if now == previous.at then return false end
  end
  assert(#self.values < Sustained.maximum_samples, "sustained sample limit exceeded")
  self.values[#self.values + 1] = { at = now, rss_kib = rss, heap_kib = heap, cpu_seconds = cpu }
  return true
end

function Sustained:snapshot()
  assert(#self.values >= 5, "sustained measurement needs at least five resource observations")
  local first, last = self.values[1], self.values[#self.values]
  local elapsed = last.at - first.at
  assert(elapsed > 0, "sustained measurement has no elapsed time")
  local result = { samples = {}, duration_seconds = elapsed,
    cpu_seconds = last.cpu_seconds - first.cpu_seconds,
    cpu_percent = (last.cpu_seconds - first.cpu_seconds) / elapsed * 100,
    window_samples = math.max(1, math.floor(#self.values / 4)) }
  for _, name in ipairs({ "rss_kib", "heap_kib" }) do
    local initial, final, peak = {}, {}, 0
    for index, value in ipairs(self.values) do
      peak = math.max(peak, value[name])
      if index <= result.window_samples then initial[#initial + 1] = value[name] end
      if index > #self.values - result.window_samples then final[#final + 1] = value[name] end
    end
    result[name] = { initial_median = Stats.summary(initial).p50, final_median = Stats.summary(final).p50, peak = peak }
    result[name].growth = result[name].final_median - result[name].initial_median
  end
  for index, value in ipairs(self.values) do
    result.samples[index] = { elapsed_seconds = value.at - first.at, rss_kib = value.rss_kib,
      heap_kib = value.heap_kib, cpu_seconds = value.cpu_seconds - first.cpu_seconds }
  end
  return result
end

return Sustained
