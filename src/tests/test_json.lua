local Assert = require("tests.assert")
local Json = require("kiwi.bench.json")

return {
  benchmark_json_is_machine_readable_and_escapes_strings = function()
    local encoded = Json.encode({ b = 2, a = "line\nquote\"", nested = { true, false } })
    Assert.equal(encoded, "{\"a\":\"line\\nquote\\\"\",\"b\":2,\"nested\":[true,false]}")
  end,
}
