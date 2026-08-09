local Assert = require("tests.assert")
local Terminal = require("kiwi.terminal.model")

return {
  terminal_mutation_marks_only_changed_cells = function()
    local terminal = Terminal.new(4, 2)
    terminal:clear_damage()
    Assert.truthy(terminal:set(1, 0, { glyph = "A", fg = 1, bg = 2, flags = 3 }))
    Assert.equal(terminal.damage:summary().cells, 1)
    Assert.equal(terminal:get(1, 0).glyph, "A")
    Assert.equal(terminal:set(1, 0, { glyph = "A", fg = 1, bg = 2, flags = 3 }), false)
    Assert.equal(terminal.damage:summary().cells, 1)
  end,
  terminal_cursor_damages_old_and_new_positions = function()
    local terminal = Terminal.new(4, 2)
    terminal:clear_damage()
    terminal:set_cursor(3, 1)
    Assert.equal(terminal.damage:summary().cells, 2)
  end,
  terminal_resize_marks_new_model_fully_dirty = function()
    local terminal = Terminal.new(4, 2)
    terminal:resize(3, 3)
    Assert.equal(terminal.damage:summary().cells, 9)
    Assert.truthy(terminal.damage:summary().full)
  end,
}
