local Assert = require("tests.assert")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")
local Terminal = require("kiwi.session.terminal")
local Scrollback = require("kiwi.terminal.scrollback")

local function write_row(state, row, codepoints)
  state:set_cursor(0, row)
  for _, codepoint in ipairs(codepoints) do
    state:write_codepoint(Utf8.encode(codepoint), codepoint)
  end
end

return {
  large_copy_preserves_unicode_at_chunk_boundaries_and_enforces_exact_byte_limit = function()
    local Terminal = require("kiwi.session.terminal")
    local terminal = Terminal.new({ columns = 100, rows = 50 })
    local text = string.rep("a", 4095) .. "中é" .. string.rep("b", 500)
    terminal:write(text)
    local state = Terminal.state(terminal)
    state:set_selection(0, 0, state.cursor.row, state.cursor.column)
    Assert.equal(state:selection_text(#text), text)
    local copied, status = state:selection_text(#text - 1)
    Assert.equal(copied, nil); Assert.equal(status, "over-limit")
  end,
  selection_uses_indexed_rows_without_materializing_retained_history = function()
    local terminal = Terminal.new({ columns = 20, rows = 3, state_options = { scrollback_limit = 2000 } })
    for index = 1, 2003 do terminal:write(string.format("row %04d\r\n", index)) end
    local state = Terminal.state(terminal)
    state.selection_rows = function() error("selection copied the history index") end
    state:scroll_history(1000)
    state:set_selection(0, 0, 1, 8)
    local view = state:selection_view()
    Assert.equal(view.start.row_index, state.scrollback:size() - state.history_offset + 1)
    Assert.equal(state:selection_text(100), "row 1002\nrow 1003")
    Assert.truthy(state:selection_precedes(0, 3, 1, 3))
    -- Growth shifts the ring head but the selected stable row IDs survive.
    local id = view.start.line_id
    terminal:write("new row\r\n")
    Assert.equal(state:selection_view().start.line_id, id)
    Assert.equal(state:selection_text(100), "row 1002\nrow 1003")
  end,
  scrollback_row_lookup_tracks_eviction_clear_and_transaction_forks = function()
    local history = Scrollback.new(3)
    for id = 1, 5 do history:push({ line_id = id }) end
    Assert.equal(history:position(1), nil); Assert.equal(history:position(3), 1)
    Assert.equal(history:position(5), 3)
    local fork = history:fork(function(row) return { line_id = row.line_id } end)
    fork:push({ line_id = 6 })
    Assert.equal(fork:position(3), nil); Assert.equal(fork:position(6), 3)
    Assert.equal(history:position(3), 1); Assert.equal(history:position(6), nil)
    fork:adopt(); fork:clear(); Assert.equal(fork:position(6), nil)
    Assert.equal(next(fork.line_slots), nil)
  end,
  selection_normalizes_forward_reverse_and_returns_a_detached_view = function()
    local state = State.new(6, 2)
    write_row(state, 0, { 0x61, 0x62, 0x63, 0x64, 0x65, 0x66 })
    state:set_selection(0, 4, 0, 1)
    local view = state:selection_view()
    Assert.truthy(view.active)
    Assert.truthy(not view.empty)
    Assert.equal(view.anchor.column, 4)
    Assert.equal(view.focus.column, 1)
    Assert.equal(view.start.column, 1)
    Assert.equal(view.finish.column, 4)
    view.start.column = 0
    Assert.equal(state:selection_view().start.column, 1)
  end,

  selection_snaps_gap_endpoints_around_wide_and_combining_clusters = function()
    local state = State.new(6, 1)
    write_row(state, 0, { 0x41, 0x4e2d, 0x65, 0x301, 0x5a })
    state:set_selection(0, 0, 0, 2)
    local wide = state:selection_view()
    Assert.equal(wide.start.column, 0)
    Assert.equal(wide.finish.column, 3)
    state:set_selection(0, 3, 0, 4)
    local combining = state:selection_view()
    Assert.equal(combining.start.column, 3)
    Assert.equal(combining.finish.column, 4)
  end,

  selection_follows_scrollback_rows_and_clears_after_eviction = function()
    local state = State.new(3, 2, { scrollback_limit = 1 })
    write_row(state, 0, { 0x6f, 0x6e, 0x65 })
    write_row(state, 1, { 0x74, 0x77, 0x6f })
    state:set_selection(0, 0, 0, 1)
    local line_id = state:selection_view().start.line_id
    state:scroll_up(1)
    state:scroll_history(1)
    local preserved = state:selection_view()
    Assert.truthy(preserved.active)
    Assert.equal(preserved.start.line_id, line_id)
    state:scroll_up(1)
    Assert.truthy(not state:selection_view().active)
  end,

  selection_clamps_resize_and_clears_when_a_selected_row_is_dropped = function()
    local state = State.new(5, 2)
    write_row(state, 0, { 0x41, 0x4e2d, 0x5a })
    state:set_selection(0, 0, 0, 5)
    state:resize(3, 1)
    local resized = state:selection_view()
    Assert.truthy(resized.active)
    Assert.equal(resized.start.column, 0)
    Assert.equal(resized.finish.column, 1)
    Assert.equal(state:selection_text(32), "A中Z")
    state:resize(3, 2)
    write_row(state, 1, { 0x78 })
    state:set_selection(1, 0, 1, 1)
    state:resize(3, 1)
    Assert.truthy(not state:selection_view().active)
  end,

  selection_clamps_viewport_coordinates_and_hides_the_other_screen = function()
    local state = State.new(3, 1)
    write_row(state, 0, { 0x61, 0x62, 0x63 })
    state:set_selection(-10, -10, 99, 99)
    local view = state:selection_view()
    Assert.equal(view.start.column, 0)
    Assert.equal(view.finish.column, 3)
    state:switch_alternate(true, true)
    Assert.truthy(not state:selection_view().visible)
  end,
}
