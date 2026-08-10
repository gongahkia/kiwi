local Assert = require("tests.assert")
local Metrics = require("kiwi.renderer.pass_metrics")

local function clock(values)
  local index = 0
  return function()
    index = index + 1
    return values[index]
  end
end

return {
  pass_metrics_aggregate_prepare_and_encode_by_stable_pass_name = function()
    local metrics = Metrics.new({ enabled = true, history_limit = 2, clock = clock({ 0, 0.001, 0.001, 0.004 }) })
    metrics:begin_frame()
    metrics:measure("terminal/glyph", "prepare", function() end)
    metrics:measure("terminal/glyph", "encode", function() end)
    metrics:end_frame()
    local snapshot = metrics:snapshot()
    Assert.equal(snapshot.enabled, true)
    Assert.equal(snapshot.frame, 1)
    Assert.equal(#snapshot.samples, 1)
    Assert.equal(snapshot.samples[1].name, "terminal/glyph")
    Assert.near(snapshot.samples[1].prepare_ms, 1, 0.0001)
    Assert.near(snapshot.samples[1].encode_ms, 3, 0.0001)
  end,
  pass_metrics_bound_history_and_remove_reset_lifecycle_state = function()
    local metrics = Metrics.new({ enabled = true, history_limit = 1, clock = clock({ 0, 0.001, 0.001, 0.002 }) })
    metrics:begin_frame()
    metrics:measure("extension/example/observer", "encode", function() end)
    metrics:end_frame()
    metrics:remove("extension/example/observer")
    metrics:begin_frame()
    metrics:end_frame()
    local snapshot = metrics:snapshot()
    Assert.equal(#snapshot.history, 1)
    Assert.equal(#snapshot.samples, 0)
    metrics:reset()
    snapshot = metrics:snapshot()
    Assert.equal(snapshot.frame, 0)
    Assert.equal(#snapshot.history, 0)
  end,
  disabled_pass_metrics_do_not_collect_history = function()
    local metrics = Metrics.new({ enabled = false })
    metrics:begin_frame()
    metrics:measure("terminal/background", "encode", function() end)
    metrics:end_frame()
    local snapshot = metrics:snapshot()
    Assert.equal(snapshot.enabled, false)
    Assert.equal(#snapshot.history, 0)
  end,
}
