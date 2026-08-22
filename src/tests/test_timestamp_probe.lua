local Assert = require("tests.assert")
local Context = require("kiwi.gpu.context")

return {
  framebuffer_rgb_expectation_is_strictly_bounded = function()
    local expected = Context.parse_framebuffer_expected_rgb("18,171,52")
    Assert.equal(expected.red, 18)
    Assert.equal(expected.green, 171)
    Assert.equal(expected.blue, 52)
    Assert.equal(Context.parse_framebuffer_expected_rgb(nil), nil)
    Assert.truthy(not pcall(Context.parse_framebuffer_expected_rgb, "18,171"))
    Assert.truthy(not pcall(Context.parse_framebuffer_expected_rgb, "18,256,52"))
  end,
  surface_format_selection_prefers_an_srgb_target_with_a_safe_fallback = function()
    local formats = require("ffi").new("uint32_t[3]", { 0x1b, 0x1c, 0x17 })
    local format, is_srgb = Context.select_surface_format(formats, 3)
    Assert.equal(format, 0x1c)
    Assert.truthy(is_srgb)
    format, is_srgb = Context.select_surface_format(require("ffi").new("uint32_t[1]", { 0x1b }), 1)
    Assert.equal(format, 0x1b)
    Assert.equal(is_srgb, false)
  end,
  timestamp_probe_reports_unsupported_adapter_without_creating_resources = function()
    local supported, message = Context.probe_timestamp_queries({ timestamp_query_supported = false })
    Assert.equal(supported, false)
    Assert.equal(message, "adapter does not expose timestamp-query")
  end,
}
