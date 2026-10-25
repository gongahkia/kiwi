local Assert = require("tests.assert")
local Bench = require("kiwi.bench.configuration_reload")
local Metrics = require("kiwi.bench.process_metrics")

return {
  configuration_benchmark_samples_both_staging_paths_and_rejects_without_retention = function()
    local result = Bench.run({ history_lines = 8, iterations = 2 })
    Assert.equal(#result.cases, 2)
    Assert.equal(result.cases[1].mode, "palette")
    Assert.equal(result.cases[2].mode, "font_resize")
    for _, sample in ipairs(result.cases) do
      Assert.equal(sample.cpu_ms.count, 2)
      Assert.equal(sample.wall_ms.count, 2)
      Assert.truthy(sample.memory.sampled_peak_rss_kib > 0)
      Assert.truthy(sample.memory.retained_heap_kib_delta < 4 * 1024)
    end
    for _, phase in ipairs({ "activation", "first_history_viewport", "complete_history_read" }) do
      Assert.equal(result.palette_post_commit[phase].wall_ms.count, 2)
      Assert.equal(result.palette_post_commit[phase].cpu_ms.count, 2)
    end
    Assert.truthy(result.palette_post_commit.peak_heap_kib_delta_after_staging >= 0)
    Assert.truthy(Metrics.resident_kib() > 0)
  end,
  configuration_benchmark_rejects_unbounded_workloads = function()
    Assert.equal(pcall(Bench.run, { history_lines = 1000000 }), false)
    Assert.equal(pcall(Bench.run, { iterations = 0 }), false)
  end,
}
