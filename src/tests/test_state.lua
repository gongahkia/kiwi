local Assert = require("tests.assert")
local Actions = require("kiwi.terminal.actions")
local State = require("kiwi.terminal.state")

local function text_at(state, row)
  local characters = {}
  for column = 0, state.columns - 1 do
    characters[#characters + 1] = state:get(column, row).glyph
  end
  return table.concat(characters)
end

return {
  terminal_state_uses_deferred_autowrap = function()
    local state = State.new(3, 2)
    state.damage:clear()
    state:write_codepoint("A")
    state:write_codepoint("B")
    state:write_codepoint("C")
    Assert.equal(text_at(state, 0), "ABC")
    Assert.equal(state.cursor.column, 2)
    Assert.truthy(state.cursor.pending_wrap)
    state:write_codepoint("D")
    Assert.equal(text_at(state, 1), "D  ")
    Assert.equal(state.cursor.column, 1)
    Assert.equal(state.cursor.row, 1)
  end,
  terminal_state_scrolls_margins_without_rebuilding_other_rows = function()
    local state = State.new(4, 4)
    for row = 0, 3 do
      state:set_cell(0, row, state:cell_from_attributes(tostring(row)))
    end
    Assert.truthy(state:set_margins(2, 4))
    state:scroll_up(1)
    Assert.equal(state:get(0, 0).glyph, "0")
    Assert.equal(state:get(0, 1).glyph, "2")
    Assert.equal(state:get(0, 2).glyph, "3")
    Assert.equal(state:get(0, 3).glyph, " ")
  end,
  terminal_state_keeps_alternate_screen_out_of_primary_scrollback = function()
    local state = State.new(3, 2, { scrollback_limit = 4 })
    state:set_cell(0, 0, state:cell_from_attributes("P"))
    state:scroll_up(1)
    Assert.equal(state.scrollback:size(), 1)
    state:switch_alternate(true, true)
    state:set_cell(0, 1, state:cell_from_attributes("A"))
    state:scroll_up(1)
    Assert.equal(state.scrollback:size(), 1)
    state:switch_alternate(false, true)
    Assert.equal(state.active_screen, state.primary)
    Assert.equal(state.scrollback:size(), 1)
  end,
  terminal_state_resolves_sgr_colours_and_inverse = function()
    local state = State.new(4, 1)
    state:apply(Actions.csi({ 38, 2, 1, 2, 3, 48, 5, 12, 7 }, "", "", "m"))
    state:write_codepoint("X")
    local cell = state:get(0, 0)
    Assert.equal(cell.glyph, "X")
    Assert.truthy(cell.fg ~= cell.bg)
    Assert.truthy(cell.flags ~= 0)
    state:apply(Actions.csi({ 0 }, "", "", "m"))
    state:write_codepoint("Y")
    Assert.equal(state:get(1, 0).flags, 0)
  end,
  terminal_state_emits_conservative_status_responses = function()
    local state = State.new(4, 2)
    state:set_cursor(2, 1)
    state:apply(Actions.csi({ 5 }, "", "", "n"))
    state:apply(Actions.csi({ 6 }, "", "", "n"))
    state:apply(Actions.csi({}, "", "", "c"))
    local responses = state:pop_responses()
    Assert.equal(responses[1], "\27[0n")
    Assert.equal(responses[2], "\27[2;3R")
    Assert.equal(responses[3], "\27[?1;0c")
  end,
}
