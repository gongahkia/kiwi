local Assert = require("tests.assert")
local Attributes = require("kiwi.terminal.attributes")
local Color = require("kiwi.terminal.color")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")
local Snapshot = require("kiwi.terminal.snapshot")

return {
  underline_styles_colours_and_resets_preserve_independent_rendition = function()
    local state = State.new(12, 2)
    local parser = Parser.new(state)
    parser:feed("\27[58;2;12;171;52m\27[4:1mA\27[4:2mB\27[4:3mC\27[4:4mD\27[4:5mE")
    for column = 0, 4 do
      local cell = state:get(column, 0)
      Assert.equal(cell.underline_style, column + 1)
      Assert.equal(cell.underline_color, Color.pack(12, 171, 52, 255))
    end
    parser:feed("\27[59mF\27[24mG\27[21mH\27[0mI")
    Assert.equal(state:get(5, 0).underline_style, 5)
    Assert.equal(state:get(5, 0).underline_color, nil)
    Assert.equal(state:get(6, 0).underline_style, nil)
    Assert.equal(state:get(7, 0).underline_style, 2)
    Assert.equal(state:get(8, 0).underline_style, nil)
    Assert.equal(state:get(8, 0).underline_color, nil)
  end,
  underline_accepts_mixed_colon_and_semicolon_colour_groups_atomically = function()
    local state = State.new(8, 1)
    local parser = Parser.new(state)
    parser:feed("\27[4:3;58;2;9;10;11;38:5:196mX\27[4:4;58:2::12:13:14mY")
    Assert.equal(state:get(0, 0).underline_color, Color.pack(9, 10, 11, 255))
    Assert.equal(state:get(1, 0).underline_color, Color.pack(12, 13, 14, 255))
    parser:feed("\27[4:2;58:2::999:1:1mZ\27[4:7mQ")
    Assert.equal(state:get(2, 0).underline_style, 4)
    Assert.equal(state:get(3, 0).underline_style, 4)
    Assert.equal(state.stats.unknown.csi, 2)
    parser:feed("\27[58;2;999;1;1mR")
    Assert.equal(state.active_screen.attributes.bold, false)
  end,
  underline_colour_tracks_palette_changes_without_following_reverse_video = function()
    local state = State.new(4, 2)
    local parser = Parser.new(state)
    parser:feed("\27[4:3;58:5:1mA\27[7mB")
    local original = state.colors:indexed(1)
    Assert.equal(state:get(0, 0).underline_color, original)
    Assert.equal(state:get(1, 0).underline_color, original)
    parser:feed("\27]4;1;#010203\7\27[?5h")
    Assert.equal(state:get(0, 0).underline_color, Color.pack(1, 2, 3, 255))
    Assert.equal(state:get(1, 0).underline_color, Color.pack(1, 2, 3, 255))
    state:configure_palette({ foreground = Attributes.default_foreground, background = Attributes.default_background,
      palette = { [1] = Color.pack(4, 5, 6, 255) } })
    Assert.equal(state:get(0, 0).underline_color, Color.pack(4, 5, 6, 255))
  end,
  underline_survives_save_restore_reflow_wide_clusters_and_scrollback = function()
    local state = State.new(6, 2, { scrollback_limit = 10 })
    local parser = Parser.new(state)
    parser:feed("\27[4:3;58:5:2m界é \0277\27[0m\0278ABCD\r\n\r\n")
    Assert.equal(state.active_screen.attributes.underline_style, 3)
    local retained = state.scrollback:get(1).cells[0]
    Assert.equal(retained.underline_style, 3)
    Assert.equal(retained.underline_slot, 3)
    state:resize(4, 3)
    local found = 0
    for row = 1, state.scrollback:size() do
      for _, cell in pairs(state.scrollback:get(row).cells) do
        if cell.underline_style == 3 then found = found + 1; Assert.equal(cell.underline_slot, 3) end
      end
    end
    for row = 0, state.rows - 1 do
      for column = 0, state.columns - 1 do
        local cell = state:get(column, row)
        if cell.underline_style == 3 then found = found + 1; Assert.equal(cell.underline_slot, 3) end
      end
    end
    Assert.truthy(found >= 8)
    parser:feed("\27[?1049h\27[0malt\27[?1049l")
    Assert.equal(state.active_screen.attributes.underline_style, 3)
  end,
  underline_only_changes_invalidate_cached_ascii_cells_and_clear_on_erase = function()
    local state = State.new(3, 1)
    local parser = Parser.new(state)
    parser:feed("\27[4:3;58:5:1mX")
    state.damage:clear(); state.text_damage:clear()
    parser:feed("\r\27[4:4;58:5:2mX")
    Assert.equal(state:get(0, 0).underline_style, 4)
    Assert.equal(state:get(0, 0).underline_slot, 3)
    Assert.truthy(state.text_damage.dirty_count > 0)
    local snapshot = Snapshot.value(state).rows[1].cells[1]
    Assert.equal(snapshot.underline.style, 4)
    parser:feed("\27[0m\r\27[2K")
    Assert.equal(state:get(0, 0).underline_style, nil)
    Assert.equal(state:get(0, 0).underline_color, nil)
  end,
  underline_status_report_round_trips_the_full_rendition = function()
    local state = State.new(8, 1)
    Parser.new(state):feed("\27[4:5;58:2::9:10:11m\27P$qm\27\\")
    local response = state:pop_responses()[1]
    Assert.equal(response, "\27P1$r4:5;58:2::9:10:11m\27\\")
    local restored = State.new(8, 1)
    Parser.new(restored):feed("\27[" .. response:match("1%$r(.-)\27") .. "x")
    Assert.equal(restored:get(0, 0).underline_style, 5)
    Assert.equal(restored:get(0, 0).underline_color, Color.pack(9, 10, 11, 255))
  end,
}
