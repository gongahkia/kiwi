local Assert = require("tests.assert")
local WriteBench = require("kiwi.bench.write")

return {
  write_benchmark_reports_stage_attribution_and_static_invalidation = function()
    local results = WriteBench.run(1, 0)
    Assert.equal(#results, 17)
    local stages = {}
    for _, item in ipairs(results) do
      stages[item.stage] = (stages[item.stage] or 0) + 1
      Assert.equal(item.cpu_ms.count, item.stage == "ascii-cell-mutation-control" and 2 or 1)
      Assert.truthy(item.scope:find("GPU", 1, true) ~= nil)
    end
    Assert.equal(stages["utf8-decode"], 2)
    Assert.equal(stages["ascii-cell-mutation-control"], 1)
    Assert.equal(stages["parser-cluster-mutation-logical-damage"], 2)
    Assert.equal(stages["row-run-construction-fallback"], 2)
    Assert.equal(stages["harfbuzz-shaping"], 2)
    Assert.equal(stages["harfbuzz-atlas-glyph-records"], 2)
    Assert.equal(stages["renderer-glyph-record-packing"], 2)
    Assert.equal(stages["shape-invalidation-cursor-only"], 2)
    Assert.equal(stages["full-parser-to-glyph-record"], 2)
    for _, item in ipairs(results) do
      if item.stage == "ascii-cell-mutation-control" then
        Assert.equal(item.iterations, 2)
        Assert.equal(item.control.legacy_cpu_ms.count, 2)
        Assert.equal(item.control.direct_cpu_ms.count, 2)
      end
      if item.stage == "shape-invalidation-cursor-only" then
        Assert.equal(item.counters.rows_reshaped, 0)
        Assert.equal(item.counters.text_dirty_cells, 0)
      end
    end
  end,
}
