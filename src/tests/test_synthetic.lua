local Assert = require("tests.assert")
local Synthetic = require("kiwi.terminal.synthetic")

return {
  synthetic_generation_is_deterministic = function()
    local first = Synthetic.new(1234, 60, 24)
    local second = Synthetic.new(1234, 60, 24)
    for index = 0, first.columns * first.rows - 1 do
      local left = first.cells[index]
      local right = second.cells[index]
      Assert.equal(left.glyph, right.glyph)
      Assert.equal(left.fg, right.fg)
      Assert.equal(left.bg, right.bg)
      Assert.equal(left.flags, right.flags)
    end
  end,
  synthetic_scenarios_have_expected_damage_shapes = function()
    local terminal = Synthetic.new(80, 80, 30)
    Synthetic.apply(terminal, "typing", 2)
    Assert.truthy(terminal.damage:summary().cells <= 6)
    terminal:clear_damage()
    Synthetic.apply(terminal, "line-churn", 3)
    Assert.truthy(terminal.damage:summary().cells <= terminal.columns)
    terminal:clear_damage()
    Synthetic.apply(terminal, "full-redraw", 4)
    Assert.truthy(terminal.damage:summary().full)
  end,
}
