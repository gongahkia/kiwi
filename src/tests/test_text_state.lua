local Assert = require("tests.assert")
local Parser = require("kiwi.terminal.parser")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")
local Width = require("kiwi.terminal.width")

local function scalar(codepoint)
  return Utf8.encode(codepoint), codepoint
end

local function write(state, codepoint)
  state:write_codepoint(scalar(codepoint))
end

local function assert_blank(cell)
  Assert.equal(cell.glyph, " ")
  Assert.truthy(not cell.continuation)
end

local function assert_valid_spans(state, row)
  for column = 0, state.columns - 1 do
    local cell = state:get(column, row)
    if cell.continuation then
      Assert.truthy(column > 0)
      local anchor = state:get(column - 1, row)
      Assert.truthy(not anchor.continuation and anchor.width == 2 and cell.anchor_column == column - 1)
    elseif cell.width == 2 then
      Assert.truthy(column + 1 < state.columns)
      local continuation = state:get(column + 1, row)
      Assert.truthy(continuation.continuation and continuation.anchor_column == column)
    end
  end
end

local function snapshot_with_chunks(input, chunks)
  local state = State.new(12, 3)
  local parser = Parser.new(state)
  local offset = 1
  for _, count in ipairs(chunks) do
    parser:feed(input:sub(offset, offset + count - 1))
    offset = offset + count
  end
  if offset <= #input then parser:feed(input:sub(offset)) end
  parser:finish()
  return Snapshot.encode(state)
end

return {
  terminal_text_extends_a_cluster_across_parser_chunks = function()
    local state = State.new(6, 1)
    local parser = Parser.new(state)
    parser:feed("e")
    parser:feed(string.char(0xcc))
    parser:feed(string.char(0x81))
    parser:finish()
    local cell = state:get(0, 0)
    Assert.equal(cell.glyph, "e" .. Utf8.encode(0x0301))
    Assert.equal(#cell.codepoints, 2)
    Assert.equal(cell.width, 1)
    Assert.equal(state.cursor.column, 1)
  end,
  terminal_text_unicode_streaming_is_chunk_boundary_invariant = function()
    local input = "e" .. Utf8.encode(0x0301)
      .. Utf8.encode(0x2764) .. Utf8.encode(0xfe0f)
      .. Utf8.encode(0x1f1f8) .. Utf8.encode(0x1f1ec)
      .. Utf8.encode(0x1f469) .. Utf8.encode(0x200d) .. Utf8.encode(0x1f4bb)
    local whole = snapshot_with_chunks(input, { #input })
    for split = 1, #input - 1 do
      Assert.equal(snapshot_with_chunks(input, { split }), whole, "Unicode stream split " .. split)
    end
  end,
  terminal_text_ascii_fast_path_respects_prepend_boundaries = function()
    local state = State.new(4, 1)
    write(state, 0x0600)
    write(state, string.byte("A"))
    local prepended = state:get(0, 0)
    Assert.equal(#prepended.codepoints, 2)
    Assert.equal(prepended.codepoints[1], 0x0600)
    Assert.equal(prepended.codepoints[2], string.byte("A"))

    local plain = State.new(4, 1)
    write(plain, string.byte("A"))
    write(plain, string.byte("B"))
    Assert.equal(plain:get(0, 0).codepoints[1], string.byte("A"))
    Assert.equal(plain:get(1, 0).codepoints[1], string.byte("B"))
  end,
  terminal_text_keeps_documented_emoji_sequences_as_independent_wide_clusters = function()
    local state = State.new(16, 1)
    local sequences = {
      { 0x1f600 },
      { 0x1f44d, 0x1f3fd },
      { 0x1f1f8, 0x1f1ec },
      { 0x23, 0xfe0f, 0x20e3 },
      { 0x1f469, 0x200d, 0x1f4bb },
      { 0x00a9, 0xfe0f },
    }
    local column = 0
    for _, sequence in ipairs(sequences) do
      for _, codepoint in ipairs(sequence) do write(state, codepoint) end
      local anchor = state:get(column, 0)
      Assert.equal(anchor.width, 2)
      Assert.equal(#anchor.codepoints, #sequence)
      Assert.truthy(state:get(column + 1, 0).continuation)
      column = column + 2
    end
    Assert.equal(state.cursor.column, column)
  end,
  terminal_text_upgrades_an_emoji_variation_cluster_to_two_columns = function()
    local state = State.new(4, 1)
    write(state, 0x2764)
    Assert.equal(state:get(0, 0).width, 1)
    write(state, 0xfe0f)
    Assert.equal(state:get(0, 0).width, 2)
    Assert.truthy(state:get(1, 0).continuation)
    Assert.equal(state:get(1, 0).anchor_column, 0)
    Assert.equal(state.cursor.column, 2)
  end,
  terminal_text_wide_overwrite_and_erase_clear_the_whole_span = function()
    local state = State.new(5, 1)
    write(state, 0x4e2d)
    Assert.equal(state:get(0, 0).width, 2)
    Assert.truthy(state:get(1, 0).continuation)
    state:set_cursor(1, 0)
    write(state, string.byte("A"))
    assert_blank(state:get(0, 0))
    Assert.equal(state:get(1, 0).glyph, "A")
    state:set_cursor(0, 0)
    write(state, 0x4e2d)
    state:erase_cell(1, 0)
    assert_blank(state:get(0, 0))
    assert_blank(state:get(1, 0))
  end,
  terminal_text_clamps_wide_clusters_in_a_one_column_grid = function()
    local state = State.new(1, 1)
    write(state, 0x4e2d)
    Assert.equal(state:get(0, 0).width, 1)
    Assert.truthy(not state:get(0, 0).continuation)
    Assert.equal(state.stats.text.width_change_clamped, 1)
  end,
  terminal_text_wide_edit_operations_never_leave_orphan_spans = function()
    local overwrite_anchor = State.new(6, 1)
    write(overwrite_anchor, 0x4e2d)
    overwrite_anchor:set_cursor(0, 0)
    write(overwrite_anchor, string.byte("A"))
    Assert.equal(overwrite_anchor:get(0, 0).glyph, "A")
    assert_blank(overwrite_anchor:get(1, 0))

    local overwrite_continuation = State.new(6, 1)
    write(overwrite_continuation, 0x4e2d)
    overwrite_continuation:set_cursor(1, 0)
    write(overwrite_continuation, string.byte("B"))
    assert_blank(overwrite_continuation:get(0, 0))
    Assert.equal(overwrite_continuation:get(1, 0).glyph, "B")

    for _, erase_column in ipairs({ 0, 1 }) do
      local state = State.new(6, 1)
      write(state, 0x4e2d)
      state:erase_cell(erase_column, 0)
      assert_blank(state:get(0, 0))
      assert_blank(state:get(1, 0))
      assert_valid_spans(state, 0)
    end

    local edited = State.new(8, 1)
    write(edited, string.byte("A"))
    write(edited, 0x4e2d)
    write(edited, string.byte("B"))
    edited:set_cursor(1, 0)
    edited:delete_characters(1)
    assert_valid_spans(edited, 0)
    edited:set_cursor(1, 0)
    edited:insert_characters(1)
    assert_valid_spans(edited, 0)
    edited:reset()
    assert_valid_spans(edited, 0)
  end,
  terminal_text_preserves_valid_spans_through_edit_resize_scroll_and_alternate = function()
    local state = State.new(5, 2)
    write(state, 0x4e2d)
    write(state, string.byte("B"))
    state:set_cursor(0, 0)
    state:insert_characters(1)
    Assert.equal(state:get(1, 0).width, 2)
    Assert.truthy(state:get(2, 0).continuation)
    state:set_cursor(1, 0)
    state:delete_characters(1)
    for column = 0, state.columns - 1 do
      local cell = state:get(column, 0)
      if cell.continuation then
        Assert.truthy(column > 0 and state:get(column - 1, 0).width == 2)
      end
    end
    state:resize(1, 2)
    Assert.truthy(not state:get(0, 0).continuation)
    Assert.equal(state:get(0, 0).width, 1)
    state:resize(4, 2)
    write(state, 0x4e2d)
    state:scroll_up(1)
    Assert.truthy(not state:get(1, 0).continuation or state:get(0, 0).width == 2)
    state:switch_alternate(true, true)
    write(state, 0x4e2d)
    Assert.truthy(state:get(1, 0).continuation)
    state:switch_alternate(false, true)
    for column = 0, state.columns - 1 do
      local cell = state:get(column, 0)
      if cell.continuation then Assert.truthy(column > 0 and state:get(column - 1, 0).width == 2) end
    end
  end,
  terminal_text_bounds_pathological_grapheme_clusters = function()
    local state = State.new(16, 1, { max_cluster_codepoints = 8 })
    write(state, string.byte("a"))
    for _ = 1, 8 do write(state, 0x0301) end
    Assert.equal(state.stats.text.over_limit_clusters, 1)
    Assert.equal(#state:get(0, 0).codepoints, 8)
    Assert.equal(state:get(1, 0).codepoints[1], 0x0301)
  end,
  terminal_text_keeps_deferred_wrap_for_narrow_and_wide_clusters = function()
    local state = State.new(3, 2)
    write(state, string.byte("A"))
    write(state, 0x4e2d)
    Assert.equal(state:get(1, 0).width, 2)
    Assert.truthy(state.cursor.pending_wrap)
    write(state, string.byte("B"))
    Assert.equal(state:get(0, 1).glyph, "B")
    state:reset()
    write(state, string.byte("A"))
    write(state, string.byte("B"))
    write(state, 0x4e2d)
    Assert.equal(state:get(0, 1).width, 2)
    Assert.truthy(state:get(1, 1).continuation)
  end,
  terminal_text_keeps_combining_and_width_changing_extensions_valid_at_the_margin = function()
    local combining = State.new(2, 2)
    write(combining, string.byte("A"))
    write(combining, string.byte("B"))
    Assert.truthy(combining.cursor.pending_wrap)
    write(combining, 0x301)
    Assert.equal(combining:get(1, 0).glyph, "B" .. Utf8.encode(0x301))
    Assert.truthy(combining.cursor.pending_wrap)
    write(combining, string.byte("C"))
    Assert.equal(combining:get(0, 1).glyph, "C")

    local occupied = State.new(3, 1)
    write(occupied, 0x2764)
    occupied:set_cell(1, 0, occupied:cell_from_attributes("A"))
    write(occupied, 0xfe0f)
    Assert.equal(occupied:get(0, 0).width, 1)
    Assert.equal(occupied.stats.text.width_change_clamped, 1)
    Assert.equal(occupied:get(1, 0).glyph, "A")

    local shrink = State.new(3, 1)
    write(shrink, 0x2764)
    write(shrink, 0xfe0f)
    Assert.equal(shrink:get(0, 0).width, 2)
    write(shrink, 0xfe0e)
    Assert.equal(shrink:get(0, 0).width, 1)
    assert_blank(shrink:get(1, 0))
  end,
  terminal_text_snapshots_expose_multicodepoint_and_continuation_cells = function()
    local state = State.new(3, 1)
    write(state, 0x4e2d)
    write(state, 0x0301)
    local snapshot = Snapshot.value(state)
    Assert.equal(snapshot.rows[1].cells[1].cluster.width, 2)
    Assert.equal(snapshot.rows[1].cells[1].cluster.codepoints[2], 0x0301)
    Assert.equal(snapshot.rows[1].cells[2].cluster.kind, "continuation")
  end,
  terminal_width_is_cluster_policy_not_font_metrics = function()
    Assert.equal(Width.columns({ 0x41 }), 1)
    Assert.equal(Width.columns({ 0x4e2d }), 2)
    Assert.equal(Width.columns({ 0x00a1 }), 1)
    Assert.equal(Width.columns({ 0x00a1 }, { ambiguous_width = 2, private_use_width = 1 }), 2)
    Assert.equal(Width.columns({ 0x2764, 0xfe0e }), 1)
    Assert.equal(Width.columns({ 0x2764, 0xfe0f }), 2)
    Assert.equal(Width.columns({ 0x1f1f8, 0x1f1ec }), 2)
    Assert.equal(Width.columns({ 0x23, 0xfe0f, 0x20e3 }), 2)
    Assert.equal(Width.columns({ 0xe0b0 }), 1)
    local ok = pcall(Width.columns, { 0x41 }, { ambiguous_width = 3, private_use_width = 1 })
    Assert.truthy(not ok)
  end,
}
