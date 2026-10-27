local Assert = require("tests.assert")
local Cell = require("kiwi.terminal.cell")
local Snapshot = require("kiwi.terminal.snapshot")
local Screen = require("kiwi.terminal.screen")
local State = require("kiwi.terminal.state")
local StateTransaction = require("kiwi.terminal.state_transaction")
local Terminal = require("kiwi.session.terminal")

local fields = { "glyph", "fg", "bg", "fg_slot", "bg_slot", "flags", "codepoints", "width",
  "underline_style", "underline_color", "underline_slot", "continuation", "anchor_column", "display_text", "hyperlink_id" }

return {
  scrolling_reuses_storage_without_changing_history_or_transaction_sources = function()
    local terminal = Terminal.new({ columns = 8, rows = 3, state_options = { scrollback_limit = 2 } })
    terminal:write("\27]8;;https://example.com\7\27[1;4:3;58:2::1:2:3m界é")
    local state = Terminal.state(terminal)
    state:scroll_up(1)
    local history = state.scrollback:get(1)
    Assert.equal(history.cells[0].glyph, "界")
    Assert.equal(history.cells[1].continuation, true)
    Assert.equal(history.cells[2].glyph, "é")
    for column = 0, 7 do
      local blank = state:blank_cell()
      for _, key in ipairs(fields) do Assert.equal(state:get(column, 2)[key], blank[key], key) end
    end
    terminal:write("\27[3;1H\27[0m\27]8;;\7NEW")
    Assert.equal(history.cells[0].glyph, "界")
    Assert.equal(history.cells[2].glyph, "é")
    Assert.truthy(history.cells[0].hyperlink_id ~= nil)
    Assert.equal(history.cells[0].underline_style, 3)
    local before = Snapshot.encode(state)
    local staged = StateTransaction.new(state)
    for _ = 1, 8 do staged.state:scroll_up(1) end
    Assert.equal(Snapshot.encode(state), before)
    -- Even evicted history references must not become mutable screen storage.
    for _ = 1, 8 do state:scroll_up(1) end
    terminal:write("\27[3;1HZ")
    Assert.equal(history.cells[0].glyph, "界")
    Assert.equal(history.cells[2].glyph, "é")
    terminal:close()
  end,
  discarded_scroll_rows_clear_renditions_and_metadata_in_both_directions = function()
    local sequence = 0
    local blank = { glyph = " ", fg = 1, bg = 2, flags = 0, width = 1 }
    local screen = Screen.new(3, 3, function() return Cell.expand(blank) end,
      function() sequence = sequence + 1; return sequence end)
    local function decorate(row)
      row.wrapped, row.command_regions_truncated = true, true
      row.command_region_ids, row.kitty_placement_ids = { 3 }, { 4 }
      Cell.copy_into(row.cells[0], { glyph = "界", fg = 4, bg = 5, flags = 7, width = 0,
        codepoints = { 0x754c }, underline_style = 3, underline_color = 6,
        underline_slot = 2, continuation = true, anchor_column = 0,
        display_text = "custom", hyperlink_id = 9 })
    end
    local discarded
    local function release(row) discarded = row.line_id end
    local function check(row)
      Assert.truthy(row.line_id > discarded)
      Assert.equal(row.wrapped, false)
      Assert.equal(row.command_regions_truncated, false)
      Assert.equal(row.command_region_ids, nil)
      Assert.equal(row.kitty_placement_ids, nil)
      for column = 0, 2 do
        for _, key in ipairs(fields) do Assert.equal(row.cells[column][key], blank[key], key) end
      end
    end
    decorate(screen.rows[0])
    local outside = screen.rows[2]
    screen:scroll_up(0, 1, 1, nil, release)
    Assert.equal(screen.rows[2], outside)
    check(screen.rows[1])
    decorate(screen.rows[2])
    outside = screen.rows[0]
    screen:scroll_down(1, 2, 1, release)
    Assert.equal(screen.rows[0], outside)
    check(screen.rows[1])
  end,
  scrolling_bounds_transient_allocation_with_and_without_history = function()
    for _, limit in ipairs({ 0, 256 }) do
      local state = State.new(80, 24, { scrollback_limit = limit })
      for _ = 1, 500 do state:scroll_up(1) end
      collectgarbage("collect")
      collectgarbage("stop")
      local before = collectgarbage("count")
      local ok, message = xpcall(function()
        for _ = 1, 1000 do state:scroll_up(1) end
        local allocated = collectgarbage("count") - before
        local budget = limit == 0 and 2 * 1024 or 16 * 1024
        Assert.truthy(allocated < budget, "scrolling allocated " .. allocated .. " KiB")
        Assert.equal(state.scrollback:size(), limit)
      end, debug.traceback)
      collectgarbage("restart")
      assert(ok, message)
    end
  end,
  packed_history_preserves_style_and_transaction_isolation = function()
    collectgarbage("collect")
    local baseline = collectgarbage("count")
    local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = 512 } })
    terminal:write("\27]8;;https://example.com\7\27[1;4:3;58:2::1:2:3m")
    local line = string.rep("é", 64) .. "\r\n"
    for _ = 1, 536 do terminal:write(line) end
    local state = Terminal.state(terminal)
    collectgarbage("collect")
    local limit = 80 * (512 + 24) * 320 / 1024 + 512
    Assert.truthy(collectgarbage("count") - baseline < limit, "styled history exceeded its Lua heap budget")
    local history = state.scrollback:get(1).cells[0]
    local live = state:get(0, 0)
    for _, key in ipairs(fields) do
      if key ~= "codepoints" then Assert.equal(history[key], live[key], key) end
    end
    Assert.equal(history.codepoints[1], 0xe9)
    local staged = StateTransaction.new(state)
    local copied = staged.state.scrollback:get(1).cells[0]
    Assert.truthy(copied ~= history)
    Assert.equal(copied.codepoints, history.codepoints)
    copied.fg, copied.underline_color, copied.hyperlink_id = 42, nil, nil
    Assert.truthy(history.fg ~= 42)
    Assert.truthy(history.underline_color ~= nil)
    Assert.truthy(history.hyperlink_id ~= nil)
    staged:seal()
    staged:commit()
    Assert.equal(state.scrollback:get(1).cells[0].fg, 42)
    terminal:resize(72, 21)
    terminal:write("\27[H\27[0m\27]8;;\7A\204\129")
    Assert.equal(state:get(0, 0).glyph, "Á")
    Assert.equal(state:get(0, 0).underline_color, nil)
    Assert.equal(state:get(0, 0).hyperlink_id, nil)
    terminal:close()
  end,
  packed_and_plain_cells_copy_all_fields_in_both_directions = function()
    local styled = { glyph = "界", fg = 12, bg = 34, flags = 56, width = 2, codepoints = { 0x754c },
      underline_style = 3, underline_color = 78, underline_slot = 0, hyperlink_id = 90,
      display_text = "display", continuation = false, anchor_column = 0 }
    local plain = { glyph = "A", fg = 1, bg = 2, fg_slot = 0, bg_slot = 0, flags = 0,
      width = 1, codepoints = { 65 } }
    for _, pack in ipairs({ Cell.pack, Cell.expand }) do
      for _, destination in ipairs({ Cell.pack(styled), Cell.expand(styled) }) do
        local source = pack(styled)
        Cell.copy_into(destination, source)
        for _, key in ipairs(fields) do Assert.equal(destination[key], styled[key], key) end
        Cell.copy_into(destination, pack(plain))
        for _, key in ipairs(fields) do Assert.equal(destination[key], plain[key], key) end
        Assert.equal(source.underline_color, 78)
      end
    end
  end,
  cell_copy_preserves_renditions_and_clears_attributes_when_overwritten = function()
    local styled = { glyph = "界", fg = 12, bg = 34, flags = 56, width = 2, codepoints = { 0x754c },
      underline_style = 3, underline_color = 78, underline_slot = 0, hyperlink_id = 90,
      display_text = "display", continuation = false, anchor_column = 0 }
    local copy = Cell.clone(styled)
    Assert.truthy(copy ~= styled)
    for key, value in pairs(styled) do Assert.equal(copy[key], value) end
    local plain = { glyph = "A", fg = 1, bg = 2, fg_slot = 0, bg_slot = 0, flags = 0,
      width = 1, codepoints = { 65 } }
    Cell.copy_into(copy, plain)
    for _, key in ipairs(fields) do Assert.equal(copy[key], plain[key], "stale cell field " .. key) end
    for key, value in pairs(plain) do Assert.equal(copy[key], value) end
    Assert.equal(styled.underline_color, 78)
  end,
  compact_ascii_keeps_visual_text_graphemes_and_snapshot_semantics = function()
    local terminal = Terminal.new({ columns = 12, rows = 2 })
    terminal:write("A")
    local state = Terminal.state(terminal)
    local plain = state:get(0, 0)
    Assert.equal(plain.display_text, nil)
    local constructed = state:ascii_cell("A", plain.codepoints)
    for _, key in ipairs(fields) do Assert.equal(constructed[key], plain[key]) end
    Assert.equal(Snapshot.value(state).rows[1].cells[1].cluster, nil)
    terminal:write("\204\129") -- Extend the compact ASCII anchor with U+0301.
    Assert.equal(state:get(0, 0).glyph, "Á")
    Assert.equal(state:get(0, 0).display_text, nil)
    Assert.equal(state:get(0, 0).display_text or state:get(0, 0).glyph, "Á")
    Assert.equal(#Snapshot.value(state).rows[1].cells[1].cluster.codepoints, 2)
    terminal:write("\r\ń") -- A leading combining mark still displays a dotted circle.
    Assert.equal(state:get(0, 1).display_text, "◌́")
    terminal:write("\204\128") -- Extending it preserves the distinct visual prefix.
    Assert.equal(state:get(0, 1).glyph, "́̀")
    Assert.equal(state:get(0, 1).display_text, "◌́̀")
    terminal:write("\r\27]8;;https://example.com\7\27[4:3;58:2::1:2:3m界")
    terminal:write("\r\27]8;;\7\27[0mB")
    local replaced = state:get(0, 1)
    Assert.equal(replaced.glyph, "B")
    Assert.equal(replaced.display_text, nil)
    Assert.equal(replaced.hyperlink_id, nil)
    Assert.equal(replaced.underline_color, nil)
    Assert.equal(replaced.underline_style, nil)
    Assert.equal(state:get(1, 1).glyph, " ")
    Assert.truthy(not state:get(1, 1).continuation)
    terminal:close()
  end,
  unicode_history_stays_compact_without_sharing_mutable_clusters = function()
    collectgarbage("collect")
    local baseline = collectgarbage("count")
    local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = 512 } })
    local line = string.rep("é", 32) .. string.rep("é", 32) .. "\r\n"
    for _ = 1, 536 do terminal:write(line) end
    local state = Terminal.state(terminal)
    collectgarbage("collect")
    -- Include immutable codepoint arrays, state, rows, and JIT overhead. Repeating
    -- display_text in every anchor doubles its hash capacity and exceeds this.
    local limit = 80 * (512 + 24) * 400 / 1024 + 512
    Assert.truthy(collectgarbage("count") - baseline < limit, "Unicode history exceeded its Lua heap budget")
    Assert.equal(state.scrollback:size(), 512)
    local history = state.scrollback:get(1)
    Assert.equal(history.cells[0].glyph, "é")
    Assert.equal(history.cells[32].glyph, "é")
    Assert.equal(history.cells[32].display_text, nil)
    Assert.equal(#history.cells[32].codepoints, 2)
    local transaction = StateTransaction.new(state, { columns = 72, rows = 21 })
    local staged = transaction.state.scrollback:get(1).cells[32]
    Assert.equal(staged.glyph, "é")
    staged.glyph = "changed"
    Assert.equal(history.cells[32].glyph, "é")
    -- Extending a live anchor replaces the codepoint array; it must not mutate
    -- an earlier clone or a transactional snapshot that still references it.
    terminal:write("\27[Hé")
    local saved = Cell.clone(state:get(0, 0))
    terminal:write("\204\129")
    Assert.equal(saved.glyph, "é")
    Assert.equal(#saved.codepoints, 1)
    Assert.equal(state:get(0, 0).glyph, "é́")
    Assert.equal(#state:get(0, 0).codepoints, 2)
    terminal:close()
  end,
  plain_history_and_staged_reflow_remain_within_cell_memory_budget = function()
    collectgarbage("collect")
    local baseline = collectgarbage("count")
    local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = 512 } })
    for line = 1, 536 do terminal:write(string.rep("x", 64) .. "\r\n") end
    local state = Terminal.state(terminal)
    collectgarbage("collect")
    -- Include state/row/JIT overhead, with room for both supported LuaJIT builds.
    -- A cell inflated to sixteen hash slots exceeds this bound.
    local limit = 80 * (512 + 24) * 320 / 1024 + 512
    Assert.truthy(collectgarbage("count") - baseline < limit, "plain history exceeded its Lua heap budget")
    local staged_baseline = collectgarbage("count")
    local transaction = StateTransaction.new(state, { columns = 72, rows = 21 })
    collectgarbage("collect")
    Assert.truthy(collectgarbage("count") - staged_baseline < limit, "reflow inflated plain cell storage")
    Assert.equal(state:get(0, 0).glyph, "x")
    Assert.equal(transaction.state.scrollback:get(1).cells[0].glyph, "x")
    transaction.state.scrollback:get(1).cells[0].glyph = "Y"
    Assert.equal(state.scrollback:get(1).cells[0].glyph, "x")
    terminal:close()
  end,
}
