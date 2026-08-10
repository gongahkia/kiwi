local Assert = require("tests.assert")
local Color = require("kiwi.renderer.color")
local Passes = require("kiwi.renderer.passes")
local Renderer = require("kiwi.renderer.renderer")
local Selection = require("kiwi.renderer.selection")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")

local function write_row(state, row, codepoints)
  state:set_cursor(0, row)
  for _, codepoint in ipairs(codepoints) do
    state:write_codepoint(Utf8.encode(codepoint), codepoint)
  end
end

local function stub_model(start_line, finish_line)
  local document = {}
  for line_id = 1, 5 do document[line_id] = { line_id = line_id, row = {} } end
  return {
    columns = 4,
    rows = 3,
    selection_rows = function() return document end,
    selection_view = function()
      return {
        active = true,
        empty = false,
        finish = { column = 2, line_id = finish_line },
        scope = "primary",
        start = { column = 1, line_id = start_line },
        visible = true,
      }
    end,
    visible_row = function(_, row) return document[row + 2] end,
  }
end

return {
  selection_renderer_derives_grapheme_safe_visible_ranges = function()
    local state = State.new(6, 1)
    write_row(state, 0, { 0x41, 0x4e2d, 0x5a })
    state:set_selection(0, 2, 0, 3)
    local descriptor = Renderer.selection_descriptor({}, state)
    Assert.truthy(descriptor.active)
    Assert.equal(descriptor.start_column, 1)
    Assert.equal(descriptor.finish_column, 3)
    Assert.equal(descriptor.start_row, 0)
    Assert.equal(descriptor.finish_row, 0)
  end,

  selection_renderer_clips_ranges_to_the_current_viewport = function()
    local clipped = Selection.descriptor(stub_model(1, 5))
    Assert.truthy(clipped.active)
    Assert.equal(clipped.start_row, -1)
    Assert.equal(clipped.finish_row, 3)
    local outside = Selection.descriptor(stub_model(1, 1))
    Assert.truthy(not outside.active)
  end,

  selection_renderer_validates_configured_rgba_colours = function()
    local color = Color.unpack(Selection.parse_color("#11223344"))
    Assert.equal(color.red, 0x11)
    Assert.equal(color.green, 0x22)
    Assert.equal(color.blue, 0x33)
    Assert.equal(color.alpha, 0x44)
    local default = Color.unpack(Selection.parse_color("#112233"))
    Assert.equal(default.alpha, 0x70)
    local ok = pcall(Selection.parse_color, "112233")
    Assert.truthy(not ok)
  end,

  selection_renderer_declares_alpha_overlay_order = function()
    local renderer = { native = { constants = { load_clear = 2, load_load = 1 } }, selection = { active = true } }
    local passes = Passes.build(renderer)
    Assert.equal(#passes, 4)
    Assert.equal(passes[2].name, "terminal/selection")
    Assert.equal(passes[2].blend, "alpha")
    Assert.equal(passes[2].reads[1], "terminal.selection")
    Assert.equal(passes[2].after[1], "terminal/background")
    Assert.equal(passes[3].after[1], "terminal/selection")
    Assert.equal(passes[4].after[1], "terminal/glyph")
  end,
}
