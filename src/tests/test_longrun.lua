local Assert = require("tests.assert")
local Longrun = require("kiwi.bench.longrun")

return {
  longrun_profiles_bounded_history_fragmentation_resize_and_cache_pressure = function()
    local result = Longrun.run({
      atlas_entries = 8,
      batch_lines = 4,
      history_limit = 8,
      history_lines = 32,
      lifecycle_iterations = 1,
      navigation_rounds = 3,
      rss_limit_kib = 128 * 1024,
      text_rounds = 4,
    })
    Assert.equal(result.history.scrollback_lines, 8)
    Assert.equal(result.history.scrollback_limit, 8)
    Assert.equal(result.history.batch_cpu_ms.count, 8)
    Assert.truthy(result.history.fragmented_cells > 0)
    Assert.truthy(result.history.resize_count > 0)
    Assert.truthy(result.history.layout.rows_reshaped > 0)
    Assert.equal(result.history.phases.input_parser_cpu_ms.count, result.history.batches)
    Assert.equal(result.history.phases.fragmented_update_cpu_ms.count, result.history.batches)
    Assert.equal(result.history.phases.resize_cpu_ms.count, result.history.batches)
    Assert.equal(result.history.phases.layout_cpu_ms.count, result.history.batches)
    Assert.equal(result.history.phases.damage_cpu_ms.count, result.history.batches)
    Assert.equal(result.history.navigation_rounds, 3)
    Assert.equal(result.history.history_navigation_cpu_ms.count, 6)
    Assert.equal(result.history.navigation_phases.scroll_cpu_ms.count, 6)
    Assert.equal(result.history.navigation_phases.layout_cpu_ms.count, 6)
    Assert.truthy(result.text_cache_pressure.atlas_entries <= result.text_cache_pressure.atlas_entries_limit)
    Assert.equal(result.unavailable.gpu_renderer:sub(1, 11), "unavailable")
  end,
}
