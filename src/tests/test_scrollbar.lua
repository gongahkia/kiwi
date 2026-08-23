local Assert = require("tests.assert")
local Pointer = require("kiwi.input.scrollbar_pointer")
local Scrollbar = require("kiwi.renderer.scrollbar")
local State = require("kiwi.terminal.state")

local function state_with_history()
  local state = State.new(4, 4, { scrollback_limit = 8 })
  for _ = 1, 10 do
    state:carriage_return()
    state:line_feed()
  end
  Assert.truthy(state.scrollback:size() > 0)
  return state
end

local function event(kind, x, y, action)
  return {
    action = action,
    button = 0,
    kind = kind,
    pixel_height = 100,
    pixel_width = 100,
    pixel_x = x,
    pixel_y = y,
  }
end

return {
  scrollbar_descriptor_projects_only_primary_history_with_a_clamped_thumb = function()
    local state = state_with_history()
    local descriptor = Scrollbar.descriptor(state)
    Assert.truthy(descriptor.active)
    Assert.equal(descriptor.history_size, state.scrollback:size())
    Assert.equal(descriptor.history_offset, 0)
    Assert.near(descriptor.bottom, 1, 0.000001)
    Assert.truthy(descriptor.thumb_size >= Scrollbar.minimum_thumb_rows / state.rows)
    state:scroll_history(state.scrollback:size())
    descriptor = Scrollbar.descriptor(state)
    Assert.near(descriptor.top, 0, 0.000001)
    state:switch_alternate(true, true)
    Assert.equal(Scrollbar.descriptor(state).active, false)
    state:switch_alternate(false, true)
    Assert.equal(Scrollbar.descriptor(state, "never").active, false)
  end,
  scrollbar_pointer_owns_primary_track_clicks_and_drag_without_forwarding_mouse_input = function()
    local state = state_with_history()
    local descriptor = Scrollbar.descriptor(state)
    local pointer = Pointer.new()
    local handled, changed = pointer:handle(event("button", 90, 5, "press"), state, descriptor)
    Assert.equal(handled, true)
    Assert.equal(changed, true)
    Assert.truthy(state.history_offset > 0)
    handled, changed = pointer:handle(event("motion", 90, 95), state, descriptor)
    Assert.equal(handled, true)
    Assert.equal(changed, true)
    Assert.equal(state.history_offset, 0)
    handled = pointer:handle(event("button", 90, 95, "release"), state, descriptor)
    Assert.equal(handled, true)
    Assert.equal(pointer.drag, nil)
    handled = pointer:handle(event("button", 10, 50, "press"), state, Scrollbar.descriptor(state))
    Assert.equal(handled, false)
  end,
}
