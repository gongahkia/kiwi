local Assert = require("tests.assert")
local Stats = require("kiwi.bench.stats")

return {
  statistics_report_linear_percentiles = function()
    local summary = Stats.summary({ 1, 2, 3, 4, 5 })
    Assert.equal(summary.count, 5)
    Assert.equal(summary.mean, 3)
    Assert.equal(summary.p50, 3)
    Assert.equal(summary.p95, 4.8)
    Assert.equal(summary.p99, 4.96)
  end,
}
