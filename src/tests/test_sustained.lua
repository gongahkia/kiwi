local Assert = require("tests.assert")
local Sustained = require("kiwi.bench.sustained")

return {
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
