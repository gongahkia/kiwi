local Assert = require("tests.assert")
local Actions = require("kiwi.terminal.actions")
local State = require("kiwi.terminal.state")

local function marker(state, value)
  state:apply(Actions.osc(133, value))
end

local function history_state()
  local state = State.new(8, 2, { scrollback_limit = 8 })
  for index = 1, 3 do
    marker(state, "A")
    state:write_codepoint("p", 0x70)
    marker(state, "B")
    marker(state, "C")
    state:write_codepoint(tostring(index), 0x30 + index)
    marker(state, "D;0")
    if index < 3 then state:line_feed() end
  end
  return state
end

return {
  command_region_navigation_orders_retained_boundaries_and_preserves_selection = function()
    local state = history_state()
    state:set_selection(0, 0, 0, 1)
    local selection = state:selection_view()
    local region, status = state:navigate_command_region("prompt", "backward")
    Assert.equal(status, "navigated")
    Assert.equal(region.id, 3)
    Assert.equal(state.history_offset, 0)
    region, status = state:navigate_command_region("prompt", "backward")
    Assert.equal(status, "navigated")
    Assert.equal(region.id, 2)
    Assert.equal(state.history_offset, 0)
    region, status = state:navigate_command_region("prompt", "backward")
    Assert.equal(status, "navigated")
    Assert.equal(region.id, 1)
    Assert.equal(state.history_offset, 1)
    region, status = state:navigate_command_region("prompt", "forward")
    Assert.equal(status, "navigated")
    Assert.equal(region.id, 2)
    Assert.equal(state:selection_view().anchor.line_id, selection.anchor.line_id)
    Assert.equal(state:selection_view().focus.line_id, selection.focus.line_id)
  end,

  command_region_navigation_resolves_partial_targets_and_skips_evicted_ones = function()
    local state = State.new(4, 2, { scrollback_limit = 1 })
    marker(state, "A")
    state:write_codepoint("p", 0x70)
    marker(state, "B")
    state:line_feed()
    marker(state, "C")
    state:write_codepoint("o", 0x6f)
    marker(state, "D;0")
    state:line_feed()
    state:line_feed()
    local view = state.command_regions:view().regions[1]
    Assert.equal(view.coverage, "partial")
    local region, status = state:navigate_command_region("output", "backward")
    Assert.equal(status, "navigated")
    Assert.equal(region.id, view.id)
    Assert.equal(state.history_offset, 1)
    region, status = state:navigate_command_region("prompt", "backward")
    Assert.equal(region, nil)
    Assert.equal(status, "no-region")
  end,

  command_region_navigation_gates_search_alternate_and_keyboard_owned_input = function()
    local state = history_state()
    state:search_begin("forward")
    local region, status = state:navigate_command_region("command", "backward")
    Assert.equal(region, nil)
    Assert.equal(status, "search-active")
    Assert.truthy(state:search_view().editing)
    state:clear_search()
    state:switch_alternate(true, true)
    region, status = state:navigate_command_region("command", "backward")
    Assert.equal(region, nil)
    Assert.equal(status, "alternate-screen")
    state:switch_alternate(false, true)
    state.modes.keyboard_flags = 1
    region, status = state:navigate_command_region("command", "backward")
    Assert.equal(region, nil)
    Assert.equal(status, "keyboard-mode")
  end,
}
