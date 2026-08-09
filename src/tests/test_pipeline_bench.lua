local Assert = require("tests.assert")
local Pipeline = require("kiwi.bench.pipeline")

return {
  pipeline_benchmark_covers_each_m1_5_cpu_layer = function()
    local results = Pipeline.run(1, 0)
    for _, layer in ipairs({ "byte_utf8", "parser_only", "state_only", "parser_state", "damage", "packing", "scroll", "full_cpu_pipeline" }) do
      Assert.truthy(#results[layer] > 0, layer .. " benchmark layer is empty")
      for _, result in ipairs(results[layer]) do
        Assert.equal(result.cpu_ms.count, 1)
        Assert.truthy(result.cpu_ms.total >= 0)
        Assert.truthy(result.memory.peak_kib_delta == result.memory.peak_kib_delta)
      end
    end
  end,
}
