local Assert = require("tests.assert")
local Context = require("kiwi.gpu.context")

return {
  timestamp_probe_reports_unsupported_adapter_without_creating_resources = function()
    local supported, message = Context.probe_timestamp_queries({ timestamp_query_supported = false })
    Assert.equal(supported, false)
    Assert.equal(message, "adapter does not expose timestamp-query")
  end,
}
