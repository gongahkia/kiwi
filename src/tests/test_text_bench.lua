local Assert = require("tests.assert")
local TextBench = require("kiwi.bench.text")
local TextCorpus = require("kiwi.bench.text_corpus")
local TextStress = require("kiwi.bench.text_stress")

return {
  text_benchmark_reports_every_native_text_layer = function()
    local results = TextBench.run(1, 0)
    Assert.equal(#results.segmentation, 6)
    Assert.equal(#results.width, 6)
    Assert.equal(#results.shaping_cold, 6)
    Assert.equal(#results.shaping_hot, 6)
    Assert.equal(#results.fallback, 3)
    Assert.equal(#results.glyph_atlas, 3)
    Assert.equal(#results.layout_cold, 6)
    Assert.equal(#results.layout_cached, 6)
    Assert.equal(#results.layout_edit, 6)
    Assert.equal(#results.full_text_pipeline, 6)
    Assert.truthy(results.layout_cached[1].cpu_ms.count == 1)
  end,
  text_corpus_manifest_is_small_and_semantically_deterministic = function()
    local manifest = TextCorpus.manifest()
    Assert.equal(manifest.version, "kiwi-text-corpus-v1")
    Assert.equal(#manifest.scenarios, 6)
    Assert.equal(manifest.scenarios[5].id, "ligatures")
    Assert.equal(manifest.scenarios[6].id, "dense-ui")
    for _, scenario in ipairs(manifest.scenarios) do
      Assert.truthy(scenario.input_bytes <= 256, scenario.id .. " corpus fixture is not bounded")
      Assert.truthy(scenario.codepoints > 0, scenario.id .. " has no code points")
      Assert.truthy(scenario.clusters > 0, scenario.id .. " has no clusters")
      Assert.truthy(scenario.columns > 0, scenario.id .. " has no terminal columns")
    end
  end,
  text_benchmark_font_inventory_records_resolved_fallbacks = function()
    local inventory = TextBench.font_inventory()
    Assert.truthy(#inventory.primary_path > 0)
    Assert.truthy(inventory.pixel_height > 0)
    Assert.truthy(inventory.face_cache_limit > 0)
    Assert.truthy(inventory.fallback_cache_limit > 0)
  end,
  text_stress_bounds_atlas_fallback_and_grid_state = function()
    local result = TextStress.run({ rounds = 12, atlas_entries = 8, lifecycle_iterations = 2, rss_limit_kib = 96 * 1024 })
    Assert.truthy(result.atlas_entries <= result.atlas_entries_limit)
    Assert.truthy(result.fallback.fallback_misses >= 0)
    Assert.equal(result.lifecycle_text_systems, 2)
  end,
}
