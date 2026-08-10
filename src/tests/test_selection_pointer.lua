local Assert = require("tests.assert")
local SelectionPointer = require("kiwi.input.selection_pointer")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")

local function write_row(state, row, codepoints)
  state:set_cursor(0, row)
  for _, codepoint in ipairs(codepoints) do
    state:write_codepoint(Utf8.encode(codepoint), codepoint)
  end
end

local function button(action, row, column, time)
  return {
    action = action,
    button = 0,
    kind = "button",
    selection_column = column,
    selection_row = row,
    time = time,
    x = column * 8,
    y = row * 16,
  }
end

return {
  selection_pointer_maps_pixels_to_clamped_cells = function()
    local column, row = SelectionPointer.cell_position(13, 25, 2, 8, 10, 3, 2)
    Assert.equal(column, 2)
    Assert.equal(row, 1)
    column, row = SelectionPointer.cell_position(-1, 999, 1, 8, 10, 3, 2)
    Assert.equal(column, 0)
    Assert.equal(row, 1)
  end,

  selection_pointer_drags_forward_and_reverse_without_splitting_wide_cells = function()
    local state = State.new(6, 1)
    write_row(state, 0, { 0x41, 0x4e2d, 0x5a })
    local pointer = SelectionPointer.new()
    Assert.truthy(pointer:handle(button("press", 0, 0, 1), state, {}))
    Assert.truthy(pointer:handle({ kind = "motion", selection_row = 0, selection_column = 2 }, state, {}))
    local forward = state:selection_view()
    Assert.equal(forward.start.column, 0)
    Assert.equal(forward.finish.column, 3)
    Assert.truthy(pointer:handle(button("release", 0, 2, 1.1), state, {}))

    Assert.truthy(pointer:handle(button("press", 0, 3, 2), state, {}))
    Assert.truthy(pointer:handle({ kind = "motion", selection_row = 0, selection_column = 1 }, state, {}))
    local reverse = state:selection_view()
    Assert.equal(reverse.start.column, 1)
    Assert.equal(reverse.finish.column, 4)
  end,

  selection_pointer_expands_double_words_and_triple_lines = function()
    local state = State.new(7, 1)
    write_row(state, 0, { 0x66, 0x6f, 0x6f, 0x2e, 0x62, 0x61, 0x72 })
    local pointer = SelectionPointer.new()
    pointer:handle(button("press", 0, 1, 1), state, {})
    pointer:handle(button("release", 0, 1, 1.05), state, {})
    pointer:handle(button("press", 0, 1, 1.2), state, {})
    local word = state:selection_view()
    Assert.equal(word.start.column, 0)
    Assert.equal(word.finish.column, 3)
    pointer:handle(button("press", 0, 1, 1.3), state, {})
    local line = state:selection_view()
    Assert.equal(line.start.column, 0)
    Assert.equal(line.finish.column, 7)
  end,

  selection_pointer_targets_the_scrollback_viewport_and_survives_resize = function()
    local state = State.new(3, 2, { scrollback_limit = 1 })
    write_row(state, 0, { 0x6f, 0x6e, 0x65 })
    write_row(state, 1, { 0x74, 0x77, 0x6f })
    state:scroll_up(1)
    state:scroll_history(1)
    local pointer = SelectionPointer.new()
    pointer:handle(button("press", 0, 1, 1), state, {})
    pointer:handle({ kind = "motion", selection_row = 0, selection_column = 2 }, state, {})
    local selection = state:selection_view()
    Assert.equal(selection.start.column, 1)
    Assert.equal(selection.finish.column, 3)
    state:resize(2, 2)
    Assert.equal(state:selection_view().finish.column, 2)
  end,

  selection_pointer_defers_to_application_mouse_reporting = function()
    local state = State.new(3, 1)
    write_row(state, 0, { 0x61, 0x62, 0x63 })
    local pointer = SelectionPointer.new()
    local handled = pointer:handle(button("press", 0, 1, 1), state, { mouse_sgr = true, mouse_tracking = "button" })
    Assert.truthy(not handled)
    Assert.truthy(not state:selection_view().active)
  end,
}
