local Assert = require("tests.assert")
local ParserBench = require("kiwi.bench.parser")

return {
  parser_benchmark_covers_the_declared_workloads = function()
    local results = ParserBench.run(1)
    Assert.equal(#results, 5)
    for _, result in ipairs(results) do
      Assert.truthy(result.bytes > 0)
      Assert.truthy(result.actions > 0)
      Assert.truthy(result.throughput_bytes_per_second >= 0)
      Assert.equal(result.cpu_parse_state_ms.count, 1)
    end
  end,
}
