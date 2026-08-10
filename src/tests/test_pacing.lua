local Assert = require("tests.assert")
local Pacing = require("kiwi.bench.pacing")

return {
  pacing_separates_warmup_frame_pacing_and_terminal_event_latency = function()
    local pacing = Pacing.new({ sample_limit = 2, warmup_frames = 1, pty_read_budget = 1024 })
    pacing:input(0)
    pacing:output(0.010)
    pacing:present(0.012, 0.020, { "terminal" })
    pacing:input(0.025)
    pacing:output(0.030)
    pacing:present(0.035, 0.040, { "terminal", "cursor" })
    pacing:output(0.050)
    pacing:present(0.055, 0.060, { "terminal" })
    local snapshot = pacing:snapshot()
    Assert.equal(snapshot.measurement.frame_cpu_ms.count, 2)
    Assert.near(snapshot.measurement.frame_cpu_ms.mean, 5, 0.0001)
    Assert.equal(snapshot.measurement.frame_interval_ms.count, 2)
    Assert.near(snapshot.measurement.frame_interval_ms.mean, 20, 0.0001)
    Assert.equal(snapshot.measurement.input_to_present_ms.count, 1)
    Assert.near(snapshot.measurement.input_to_present_ms.mean, 15, 0.0001)
    Assert.equal(snapshot.measurement.output_to_present_ms.count, 2)
    Assert.near(snapshot.measurement.output_to_present_ms.mean, 10, 0.0001)
    Assert.equal(snapshot.measurement.present_reasons.terminal, 3)
    Assert.equal(snapshot.measurement.present_reasons.cursor, 1)
    Assert.equal(snapshot.measurement.pty_read_budget, 1024)
    Assert.equal(snapshot.measurement.maximum_report_bytes, 65536)
  end,
  pacing_bounds_retained_samples_and_reports_unavailable_fields = function()
    local pacing = Pacing.new({ sample_limit = 2, warmup_frames = 0 })
    for index = 1, 3 do
      local time = index * 0.100
      pacing:output(time)
      pacing:present(time + 0.010, time + 0.020, { "terminal" })
    end
    local snapshot = pacing:snapshot()
    Assert.equal(snapshot.measurement.output_to_present_ms.count, 2)
    Assert.equal(snapshot.measurement.output_to_present_ms.dropped_samples, 1)
    Assert.equal(snapshot.measurement.input_to_present_ms.status, "unavailable")
    Assert.equal(snapshot.unavailable.display_scanout_latency:sub(1, 11), "unavailable")
  end,
}
