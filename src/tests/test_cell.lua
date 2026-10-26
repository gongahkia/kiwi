local Assert = require("tests.assert")
local Cell = require("kiwi.terminal.cell")
local Snapshot = require("kiwi.terminal.snapshot")
local StateTransaction = require("kiwi.terminal.state_transaction")
local Terminal = require("kiwi.session.terminal")

return {
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
    for key, value in pairs(copy) do Assert.equal(value, plain[key], "stale cell field " .. key) end
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
    for key, value in pairs(constructed) do Assert.equal(value, plain[key]) end
    for key, value in pairs(plain) do Assert.equal(value, constructed[key]) end
    Assert.equal(Snapshot.value(state).rows[1].cells[1].cluster, nil)
    terminal:write("\204\129") -- Extend the compact ASCII anchor with U+0301.
    Assert.equal(state:get(0, 0).glyph, "Á")
    Assert.equal(state:get(0, 0).display_text, "Á")
    Assert.equal(#Snapshot.value(state).rows[1].cells[1].cluster.codepoints, 2)
    terminal:write("\r\ń") -- A leading combining mark still displays a dotted circle.
    Assert.equal(state:get(0, 1).display_text, "◌́")
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
