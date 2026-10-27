local Assert = require("tests.assert")
local Sustained = require("kiwi.bench.sustained")

return {
  sustained_history_samples_distinguish_capacity_fill_from_eviction = function()
    local recording = Sustained.new(30)
    local history = { limit = 2, retained = 0, pushed = 0, evicted = 0 }
    for index = 0, 4 do
      history.pushed, history.retained, history.evicted = index, math.min(index, 2), math.max(0, index - 2)
      recording:observe(index, 100 + index, 20 + index, index, false, history)
    end
    history.retained = 0
    local report = recording:snapshot()
    Assert.equal(report.samples[1].history.retained, 0)
    Assert.equal(report.samples[3].history.retained, 2)
    Assert.equal(report.samples[3].history.evicted, 0)
    Assert.equal(report.samples[5].history.evicted, 2)
    report.samples[3].history.retained = 99
    Assert.equal(recording:snapshot().samples[3].history.retained, 2)
    Assert.equal(report.rss_kib.growth, 4) -- Occupancy does not alter resource budgets.
    local function invalid(value)
      Assert.equal(pcall(recording.observe, recording, 5, 100, 20, 5, false, value), false)
      Assert.equal(#recording.values, 5)
    end
    invalid({ limit = 2, retained = 3, pushed = 3, evicted = 0 })
    invalid({ limit = 2, retained = 2, pushed = 4, evicted = 1 })
    invalid({ limit = 2, retained = 1.5, pushed = 1.5, evicted = 0 })
  end,
  sustained_distinguishes_growth_from_a_transient_peak = function()
    local recording = Sustained.new(30)
    for index = 0, 19 do
      recording:observe(index, index == 10 and 900 or (index < 15 and 100 or 140),
        index < 15 and 20 or 30, index * 2)
    end
    local result = recording:snapshot()
    Assert.equal(result.window_samples, 5)
    Assert.equal(result.rss_kib.growth, 40)
    Assert.equal(result.rss_kib.peak, 900)
    Assert.equal(result.heap_kib.growth, 10)
    Assert.equal(result.cpu_percent, 200)
    Assert.equal(result.duration_seconds, 19)
    Assert.equal(result.samples[1].elapsed_seconds, 0)
  end,
  sustained_sampling_is_bounded_and_keeps_the_final_observation = function()
    local recording = Sustained.new(3600)
    for index = 0, 3599 do recording:observe(index, 100, 20, index) end
    recording:observe(3599.5, 120, 25, 3599.5, true)
    Assert.truthy(#recording.values <= Sustained.maximum_samples)
    Assert.equal(recording.values[#recording.values].rss_kib, 120)
    Assert.equal(recording:observe(3599.5, 120, 25, 3599.5, true), false)
    Assert.equal(pcall(recording.observe, recording, 3598, 100, 20, 3600), false)
    Assert.equal(pcall(recording.observe, recording, 3600, 100, 20, 3500), false)
  end,
  sustained_rejects_invalid_and_insufficient_evidence = function()
    for _, timeout in ipairs({ 0, 29, 3601, math.huge }) do
      Assert.equal(pcall(Sustained.new, timeout), false)
    end
    local recording = Sustained.new(30)
    Assert.equal(pcall(recording.snapshot, recording), false)
    Assert.equal(pcall(recording.observe, recording, 0, 0/0, 10, 0), false)
    recording:observe(1, 100, 20, 1)
    Assert.equal(pcall(recording.snapshot, recording), false)
  end,
}
