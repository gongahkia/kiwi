local Assert = require("tests.assert")
local Actions = require("kiwi.terminal.actions")
local Metrics = require("kiwi.diagnostics.metrics")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")

local function metrics_for(state, runtime)
  local context = {
    timestamp_query_supported = false,
    width = 320,
    height = 160,
    window = { content_scale = function() return 1, 1 end },
    adapter_info = { backend_name = "test", device = "test-device", vendor = "test-vendor" },
  }
  local font = { atlas = { glyph_count = function() return 2 end, width = 32, height = 32, occupancy = function() return 0.5 end } }
  local metrics = Metrics.new(context, font, state, runtime)
  metrics:record(0.001, 0.0005, { diagnostics = {
    dirty_cells = 2,
    dirty_ranges = 1,
    cells_uploaded = 2,
    bytes_uploaded = 80,
    full_update = false,
    draw_calls = 3,
    visible_shaped_runs = 2,
    visible_shaped_glyphs = 3,
  } })
  return metrics
end

return {
  diagnostics_expose_terminal_runtime_without_logging_payloads = function()
    local state = State.new(4, 2)
    state:write_codepoint(Utf8.encode(0x4e2d), 0x4e2d)
    state:apply(Actions.csi({ 1000 }, "?", "", "h"))
    state:apply(Actions.osc(9, "unreported payload"))
    local metrics = metrics_for(state, {
      pty = { pid = 42, bytes_read = 128, bytes_written = 7 },
      parser = { stats = { bytes = 128, actions = 4, errors = 1, ignored = 2 } },
    })
    local snapshot = metrics:snapshot()
    Assert.equal(snapshot.pty_bytes_read, 128)
    Assert.equal(snapshot.pty_bytes_written, 7)
    Assert.equal(snapshot.parser_actions, 4)
    Assert.equal(snapshot.terminal_mutations, state.stats.mutations)
    Assert.equal(snapshot.active_screen, "primary")
    Assert.equal(snapshot.grapheme_clusters, 1)
    Assert.equal(snapshot.wide_clusters, 1)
    Assert.equal(snapshot.visible_shaped_runs, 2)
    Assert.equal(snapshot.visible_shaped_glyphs, 3)
    Assert.equal(snapshot.extensions.enabled, true)
    Assert.equal(#snapshot.extensions.diagnostics, 0)
    Assert.equal(snapshot.unknown_csi, 1)
    Assert.equal(snapshot.unknown_osc, 1)
    Assert.equal(snapshot.unknown_samples[1].detail.private, "?")
    Assert.equal(snapshot.unknown_samples[1].detail.final, "h")
    Assert.equal(snapshot.unknown_samples[2].detail.command, 9)
  end,
  unknown_sequence_samples_are_bounded = function()
    local state = State.new(2, 1)
    for _ = 1, 64 do
      state:apply(Actions.csi({ 1000 }, "?", "", "h"))
    end
    Assert.equal(state.stats.unknown.csi, 64)
    Assert.equal(#state.stats.unknown_samples, 16)
  end,
}
