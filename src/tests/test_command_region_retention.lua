local Assert = require("tests.assert")
local Actions = require("kiwi.terminal.actions")
local Parser = require("kiwi.terminal.parser")
local Replay = require("kiwi.terminal.replay")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local function marker(state, value)
  state:apply(Actions.osc(133, value))
end

local function complete_region(state)
  marker(state, "A")
  state:write_codepoint("a", 0x61)
  marker(state, "B")
  marker(state, "C")
  state:line_feed()
  state:write_codepoint("b", 0x62)
  marker(state, "D;0")
end

local function with_recording(callback)
  local path = os.tmpname()
  local ok, result = xpcall(function() return callback(path) end, debug.traceback)
  os.remove(path)
  if not ok then error(result) end
  return result
end

return {
  command_region_rows_survive_scrollback_then_degrade_on_eviction = function()
    local state = State.new(3, 2, { scrollback_limit = 1 })
    complete_region(state)
    state:line_feed()
    state:line_feed()
    local region = state.command_regions:view().regions[1]
    Assert.equal(region.row_count, 2)
    Assert.equal(region.retained_rows, 1)
    Assert.equal(region.coverage, "partial")
    state:scroll_history(1)
    Assert.equal(state:command_regions_at(0).ids[1], region.id)
    Assert.equal(Snapshot.value(state).rows[1].command_region_ids[1], region.id)
    state:scroll_history(-1)
    state:line_feed()
    region = state.command_regions:view().regions[1]
    Assert.equal(region.retained_rows, 0)
    Assert.equal(region.coverage, "evicted")
  end,

  command_region_rows_reconcile_on_resize_and_snapshot_without_text_duplication = function()
    local state = State.new(3, 2)
    complete_region(state)
    state:resize(3, 1)
    local region = state.command_regions:view().regions[1]
    Assert.equal(region.row_count, 2)
    Assert.equal(region.retained_rows, 1)
    Assert.equal(region.coverage, "partial")
    local snapshot = Snapshot.value(state)
    Assert.equal(snapshot.v, Snapshot.version)
    Assert.equal(snapshot.rows[1].command_region_ids[1], region.id)
    Assert.truthy(Snapshot.encode(state):find('"command_region_ids"') ~= nil)
    Assert.equal(snapshot.command_regions.regions[1].text, nil)
  end,

  command_region_rows_mark_same_row_overflow_without_dangling_references = function()
    local state = State.new(8, 1, { command_regions = { row_reference_limit = 1 } })
    marker(state, "A")
    marker(state, "D")
    marker(state, "A")
    marker(state, "B")
    marker(state, "C")
    local view = state.command_regions:view()
    Assert.equal(view.regions[1].coverage, "retained")
    Assert.equal(view.regions[2].coverage, "truncated")
    Assert.truthy(state:command_regions_at(0).truncated)
    Assert.equal(#state:command_regions_at(0).ids, 1)
  end,

  command_region_history_replays_many_bounded_lifecycles = function()
    local parts = { "\27]7;file://host.example/work\7" }
    for index = 1, 12 do
      parts[#parts + 1] = "\27]133;A\7p" .. index .. "\27]133;B\7x\27]133;C\7\r\ny\r\n\27]133;D;0\7"
    end
    local output = table.concat(parts)
    with_recording(function(path)
      local recording = Replay.Recorder.new(path)
      recording:resize(4, 2)
      recording:output(output)
      recording:close()
      local replayed = State.new(1, 1, { scrollback_limit = 2 })
      Replay.apply_file(replayed, path)
      local direct = State.new(1, 1, { scrollback_limit = 2 })
      direct:resize(4, 2)
      Parser.new(direct):feed(output)
      Assert.equal(Snapshot.encode(replayed), Snapshot.encode(direct))
      local regions = replayed.command_regions:view().regions
      Assert.equal(#regions, 12)
      Assert.equal(regions[12].state, "completed")
      Assert.equal(regions[12].exit_status, 0)
    end)
  end,
}
