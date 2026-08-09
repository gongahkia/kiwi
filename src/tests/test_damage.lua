local Assert = require("tests.assert")
local Damage = require("kiwi.terminal.damage")

return {
  damage_coalesces_adjacent_cells = function()
    local damage = Damage.new(12)
    damage:mark(2)
    damage:mark(3)
    damage:mark(7)
    local ranges = damage:ranges()
    Assert.equal(#ranges, 2)
    Assert.equal(ranges[1].first, 2)
    Assert.equal(ranges[1].count, 2)
    Assert.equal(ranges[2].first, 7)
    Assert.equal(ranges[2].count, 1)
  end,
  damage_tracks_full_redraw_without_per_cell_marks = function()
    local damage = Damage.new(8000)
    damage:mark_all()
    local summary = damage:summary()
    Assert.truthy(summary.full)
    Assert.equal(summary.cells, 8000)
    Assert.equal(summary.ranges, 1)
    Assert.equal(damage:ranges()[1].count, 8000)
  end,
  damage_clear_resets_state = function()
    local damage = Damage.new(4)
    damage:mark_all()
    damage:clear()
    Assert.equal(damage:summary().cells, 0)
    Assert.equal(#damage:ranges(), 0)
  end,
}
