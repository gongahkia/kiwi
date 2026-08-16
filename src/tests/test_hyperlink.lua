local Assert = require("tests.assert")
local Actions = require("kiwi.terminal.actions")
local Hyperlink = require("kiwi.input.hyperlink")
local HyperlinkPointer = require("kiwi.input.hyperlink_pointer")
local HyperlinkRenderer = require("kiwi.renderer.hyperlink")
local Color = require("kiwi.renderer.color")
local Parser = require("kiwi.terminal.parser")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")
local TerminalHyperlink = require("kiwi.terminal.hyperlink")
local glfw = require("kiwi.ffi.glfw").constants

local function opener()
  return {
    open_uri = function(self, uri)
      self.uri = uri
      return true
    end,
  }
end

return {
  osc8_parser_state_retains_spans_closes_and_reuses_matching_ids = function()
    local state = State.new(8, 2)
    Parser.new(state):feed("\27]8;id=one;https://example.test/a\27\\ab\27]8;;\7c\27]8;id=one;https://example.test/a\7d")
    Assert.equal(state:get(0, 0).hyperlink_id, state:get(1, 0).hyperlink_id)
    Assert.equal(state:get(2, 0).hyperlink_id, nil)
    Assert.equal(state:get(3, 0).hyperlink_id, state:get(0, 0).hyperlink_id)
    Assert.equal(state:hyperlink_at(0, 1).uri, "https://example.test/a")
    Assert.truthy(Snapshot.encode(state):match('"hyperlink"'))
  end,

  osc8_rejects_malformed_unsafe_nested_and_over_limit_targets = function()
    local state = State.new(4, 1, { hyperlink_limit = 1 })
    state:apply(Actions.osc(8, "id=one;https://example.test/a"))
    state:write_codepoint("a")
    state:apply(Actions.osc(8, "id=one;javascript:alert(1)"))
    state:write_codepoint("b")
    state:apply(Actions.osc(8, "id=two;https://example.test/b"))
    state:write_codepoint("c")
    Assert.truthy(state:get(0, 0).hyperlink_id ~= nil)
    Assert.equal(state:get(1, 0).hyperlink_id, nil)
    Assert.equal(state:get(2, 0).hyperlink_id, nil)
    Assert.equal(state.stats.hyperlinks.rejected, 2)
    Assert.equal(TerminalHyperlink.parse_osc8("id=x;mailto:user@example.test").uri, "mailto:user@example.test")
    Assert.equal(TerminalHyperlink.parse_osc8("id=x;file:///tmp/value"), nil)
  end,

  osc8_metadata_survives_scrollback_resize_and_replay = function()
    local source = "\27]8;;https://example.test/a\7xy\27]8;;\7\nq"
    local direct = State.new(2, 1, { scrollback_limit = 2 })
    local parser = Parser.new(direct)
    parser:feed(source)
    direct:resize(3, 2)
    direct:scroll_history(1)
    Assert.equal(direct:hyperlink_at(0, 0).uri, "https://example.test/a")
    local replayed = State.new(2, 1, { scrollback_limit = 2 })
    Parser.new(replayed):feed(source)
    Assert.equal(replayed.scrollback:get(1).cells[0].hyperlink_id, direct:get(0, 0).hyperlink_id)
  end,

  hyperlink_activation_requires_explicit_safe_pointer_or_keyboard_action = function()
    local state = State.new(4, 1)
    state:apply(Actions.osc(8, ";https://example.test/a"))
    state:write_codepoint("a")
    local platform = opener()
    local activator = Hyperlink.new(platform)
    local pointer = HyperlinkPointer.new(activator, glfw)
    local handled = pointer:handle({ action = "press", button = 0, kind = "button", modifiers = 0, selection_column = 0, selection_row = 0 }, state, state.modes)
    Assert.truthy(not handled)
    handled = pointer:handle({ action = "press", button = 0, kind = "button", modifiers = glfw.mod_control, selection_column = 0, selection_row = 0 }, state, state.modes)
    Assert.truthy(handled)
    Assert.equal(platform.uri, "https://example.test/a")
    state:apply(Actions.csi({ 1000 }, "?", "", "h"))
    handled = pointer:handle({ action = "press", button = 0, kind = "button", modifiers = glfw.mod_control, selection_column = 0, selection_row = 0 }, state, state.modes)
    Assert.truthy(not handled)
    state:set_cursor(0, 0)
    Assert.truthy(activator:activate(state:hyperlink_at_cursor()))
    Assert.equal(activator:snapshot().counters.activated, 2)
  end,

  hyperlink_renderer_exposes_only_bounded_visible_affordance_metadata = function()
    local state = State.new(3, 1)
    state:apply(Actions.osc(8, ";https://example.test/a"))
    state:write_codepoint("a")
    local descriptor = HyperlinkRenderer.descriptor(state)
    Assert.truthy(descriptor.active)
    Assert.equal(descriptor.visible_cells, 1)
    Assert.equal(descriptor.uri, nil)
    Assert.equal(Color.unpack(HyperlinkRenderer.parse_color("#112233")).alpha, 0xff)
    Assert.truthy(not pcall(HyperlinkRenderer.parse_color, "112233"))
  end,
}
