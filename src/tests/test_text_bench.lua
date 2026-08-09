local Assert = require("tests.assert")
local TextBench = require("kiwi.bench.text")
local TextStress = require("kiwi.bench.text_stress")

return {
  text_benchmark_reports_every_native_text_layer = function()
    local results = TextBench.run(1, 0)
    Assert.equal(#results.segmentation, 5)
    Assert.equal(#results.width, 5)
    Assert.equal(#results.shaping_cold, 5)
    Assert.equal(#results.shaping_hot, 5)
    Assert.equal(#results.fallback, 3)
    Assert.equal(#results.glyph_atlas, 3)
    Assert.equal(#results.layout_cold, 5)
    Assert.equal(#results.layout_cached, 5)
    Assert.equal(#results.layout_edit, 5)
    Assert.equal(#results.full_text_pipeline, 5)
    Assert.truthy(results.layout_cached[1].cpu_ms.count == 1)
  end,
  text_stress_bounds_atlas_fallback_and_grid_state = function()
    local result = TextStress.run({ rounds = 12, atlas_entries = 8, lifecycle_iterations = 2, rss_limit_kib = 96 * 1024 })
    Assert.truthy(result.atlas_entries <= result.atlas_entries_limit)
    Assert.truthy(result.fallback.fallback_misses >= 0)
    Assert.equal(result.lifecycle_text_systems, 2)
  end,
}
