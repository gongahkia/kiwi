local Assert = require("tests.assert")
local Color = require("kiwi.renderer.color")
local Search = require("kiwi.renderer.search")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")

local function write_row(state, row, codepoints)
  state:set_cursor(0, row)
  for _, codepoint in ipairs(codepoints) do
    state:write_codepoint(Utf8.encode(codepoint), codepoint)
  end
end

return {
  search_renderer_exposes_visible_matches_and_current_grapheme_range = function()
    local state = State.new(5, 2)
    write_row(state, 0, { 0x61, 0x4e2d, 0x62 })
    write_row(state, 1, { 0x4e2d, 0x61 })
    state:search_begin("forward")
    Assert.truthy(state:search_append("中"))
    Assert.equal(select(2, state:search_submit("forward")), "matches")
    local descriptor = Search.descriptor(state)
    Assert.truthy(descriptor.active)
    Assert.equal(descriptor.match_count, 2)
    Assert.equal(descriptor.current_index, 1)
    Assert.equal(descriptor.start_column, 1)
    Assert.equal(descriptor.finish_column, 3)
    Assert.equal(descriptor.visible_matches.count, 2)
    Assert.equal(descriptor.visible_matches.match_2.start_row, 1)
  end,

  search_renderer_hides_stale_results_and_validates_colours = function()
    local state = State.new(2, 1)
    write_row(state, 0, { 0x61, 0x61 })
    state:search_begin("forward")
    Assert.truthy(state:search_append("a"))
    state:search_submit("forward")
    state:set_cursor(0, 0)
    state:write_codepoint("b", 0x62)
    local descriptor = Search.descriptor(state)
    Assert.truthy(not descriptor.active)
    Assert.equal(descriptor.status, "stale")
    Assert.equal(descriptor.match_count, 0)
    local color = Color.unpack(Search.parse_color("#11223344"))
    Assert.equal(color.alpha, 0x44)
    Assert.equal(Color.unpack(Search.parse_color("#112233")).alpha, 0x70)
    Assert.truthy(not pcall(Search.parse_color, "112233"))
  end,
}
