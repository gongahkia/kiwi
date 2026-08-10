local Assert = require("tests.assert")
local Inspector = require("kiwi.renderer.inspector")

return {
  inspector_serializes_semantic_builtin_graph_and_timing = function()
    local renderer = {
      pass_registry = {
        state = "ready",
        passes = {
          { name = "terminal/background", order = 10, reads = { "terminal.cells" }, writes = { "surface.color" }, after = {}, lifecycle = "ready" },
          { name = "terminal/glyph", order = 20, reads = { "text.shaped_glyphs" }, writes = { "surface.color" }, after = { "terminal/background" }, lifecycle = "ready" },
          { name = "terminal/cursor", order = 30, reads = { "terminal.cursor" }, writes = { "surface.color" }, after = { "terminal/glyph" }, lifecycle = "ready" },
        },
      },
      diagnostics = {
        pass_cpu = { samples = { { name = "terminal/glyph", prepare_ms = 0.1, encode_ms = 0.2 } } },
        gpu_timing = { status = "supported", samples = { { name = "terminal/glyph", frame = 4, gpu_ticks = 17, map_latency_ms = 2.5 } } },
        pass_budgets = { enabled = true, warnings = { { pass = "terminal/glyph", dimension = "cpu_ms" } }, passes = { { name = "terminal/glyph", status = "over-budget", declaration = { cpu_ms = 0.1 }, dimensions = {} } } },
        extensions = { enabled = true, diagnostics = { { extension = "fixture", phase = "animation" } }, disabled = { ["extension/fixture/broken"] = true } },
      },
      context = { timestamp_query_supported = false },
      invalidation_snapshot = function() return { reasons = { "terminal" }, deadline = nil } end,
    }
    local view = Inspector.build(renderer, "terminal/glyph")
    Assert.equal(#view.passes, 3)
    Assert.equal(view.passes[2].selected, true)
    Assert.near(view.passes[2].cpu.encode_ms, 0.2, 0.0001)
    Assert.equal(view.passes[2].gpu.ticks, 17)
    Assert.equal(view.passes[2].budget.status, "over-budget")
    Assert.equal(#view.budget_warnings, 1)
    Assert.equal(view.passes[1].cpu.unavailable, true)
    Assert.equal(#view.extensions.diagnostics, 1)
    Assert.truthy(Inspector.format(view):match("extensions=enabled disabled=1 diagnostics=1") ~= nil)
    Assert.truthy(Inspector.format(view):match("gpu=17 ticks/2%.500ms") ~= nil)
    Assert.truthy(Inspector.format(view):match("budget=over%-budget") ~= nil)
    Assert.truthy(Inspector.format(view):match("pass=terminal/cursor") ~= nil)
  end,
  inspector_exposes_registration_failure_location_without_pipeline_details = function()
    local renderer = {
      pass_registry = { state = "failed", last_error = "pass extension/example/bad depends on missing pass", passes = {} },
      diagnostics = {},
      context = { timestamp_query_supported = true },
      invalidation_snapshot = function() return { reasons = {}, deadline = nil } end,
    }
    local view = Inspector.build(renderer)
    Assert.truthy(view.error:match("extension/example/bad") ~= nil)
    Assert.truthy(view.gpu_timing:match("unavailable") ~= nil)
  end,
}
