local Assert = require("tests.assert")
local Color = require("kiwi.terminal.color")
local Decoration = require("kiwi.text.decoration")
local Layout = require("kiwi.text.layout")
local Parser = require("kiwi.terminal.parser")
local PreparedFrame = require("kiwi.renderer.prepared_frame")
local State = require("kiwi.terminal.state")
local System = require("kiwi.font.system")

return {
  decoration_layout_renders_all_styles_on_blank_cells_and_preserves_packing = function()
    local font = System.new({ pixel_height = 18 })
    local state = State.new(6, 1)
    local parser = Parser.new(state)
    for style = 1, 5 do parser:feed("\27[4:" .. style .. ";58:2::12:171:52m ") end
    local prepared = PreparedFrame.new(font, state)
    local plan = prepared:prepare_model(state)
    Assert.equal(plan.glyph_update.count, 5)
    Assert.equal(plan.glyph_update.byte_count, 5 * 48)
    for index = 0, 4 do
      local instance = plan.glyph_update.data[index]
      Assert.equal(tonumber(instance.x), index)
      Assert.equal(tonumber(instance.width), 1)
      Assert.equal(tonumber(instance.height), 1)
      Assert.equal(tonumber(instance.glyph), index + 1)
    end
    prepared:commit_model(plan)
    Assert.equal(prepared:prepare_model(state).glyph_update, nil)
    prepared:discard_model(prepared.pending_model)
    prepared:destroy(); font:destroy()
  end,
  decorations_follow_grid_cells_across_wide_text_fallback_and_spaces = function()
    local font = System.new({ pixel_height = 18 })
    local layout, state = Layout.new(font), State.new(8, 1)
    Parser.new(state):feed("\27[4:3;58:5:1mA 界é")
    local count = 0
    for _, glyph in ipairs(layout:update(state)) do
      if glyph.decoration then
        Assert.equal(glyph.x, count)
        Assert.equal(glyph.y, 0)
        Assert.equal(glyph.decoration, 3)
        Assert.equal(glyph.fg, state.colors:indexed(1))
        count = count + 1
      end
    end
    Assert.equal(count, 5)
    layout:destroy(); font:destroy()
  end,
  decoration_layout_uses_default_foreground_but_keeps_explicit_colour_on_reverse = function()
    local font = System.new({ pixel_height = 18 })
    local layout, state = Layout.new(font), State.new(4, 1)
    Parser.new(state):feed("\27[4m \27[58:2::1:2:3m \27[?5h")
    local glyphs = layout:update(state)
    Assert.equal(glyphs[1].fg, state:get(0, 0).bg)
    Assert.equal(glyphs[2].fg, Color.pack(1, 2, 3, 255))
    layout:destroy(); font:destroy()
  end,
  concealed_cells_suppress_coloured_decorations_and_hyperlinks_use_separate_masks = function()
    local font = System.new({ pixel_height = 18 })
    local layout, state = Layout.new(font), State.new(4, 1)
    Parser.new(state):feed("\27[8;4:3;58:5:1m \27[0m\27]8;;https://example.com\7 \27]8;;\7\27[9m ")
    local glyphs = layout:update(state)
    Assert.equal(#glyphs, 2)
    Assert.equal(glyphs[1].x, 1)
    Assert.equal(glyphs[1].flags, Decoration.hyperlink_flag)
    Assert.equal(glyphs[2].decoration, Decoration.strike)
    layout:destroy(); font:destroy()
  end,
  decoration_cache_recovers_when_styles_change_under_tiny_entry_budget = function()
    local font = System.new({ pixel_height = 18, atlas = { max_entries = 1, width = 64, height = 64 } })
    local layout, state = Layout.new(font), State.new(2, 1)
    local parser = Parser.new(state)
    for round = 1, 100 do
      local style = (round - 1) % 5 + 1
      parser:feed("\r\27[4:" .. style .. "m ")
      local glyphs = layout:update(state)
      Assert.equal(#glyphs, 1)
      Assert.equal(glyphs[1].decoration, style)
    end
    Assert.equal(font.glyph_cache.atlas:glyph_count(), 1)
    Assert.equal(font.glyph_cache.stats.evictions, 99)
    layout:destroy(); font:destroy()
  end,
}
