local Assert = require("tests.assert")
local Actions = require("kiwi.terminal.actions")
local CommandRegions = require("kiwi.renderer.command_regions")
local Renderer = require("kiwi.renderer.renderer")
local State = require("kiwi.terminal.state")

local function marker(state, value)
  state:apply(Actions.osc(133, value))
end

return {
  command_region_resource_exposes_only_bounded_visible_boundaries_and_roles = function()
    local state = State.new(8, 2)
    marker(state, "A")
    state:write_codepoint("p", 0x70)
    marker(state, "B")
    state:write_codepoint("c", 0x63)
    marker(state, "C")
    state:line_feed()
    state:write_codepoint("o", 0x6f)
    marker(state, "D;7")
    local descriptor = CommandRegions.descriptor(state)
    Assert.truthy(descriptor.active)
    Assert.equal(descriptor.boundary_count, 4)
    Assert.equal(descriptor.boundaries.boundary_1.role, "prompt")
    Assert.equal(descriptor.boundaries.boundary_2.role, "command")
    Assert.equal(descriptor.boundaries.boundary_3.role, "output")
    Assert.equal(descriptor.boundaries.boundary_4.role, "finish")
    Assert.equal(descriptor.boundaries.boundary_1.line_id, nil)
    Assert.equal(descriptor.boundaries.boundary_1.id, nil)
    Assert.equal(descriptor.boundaries.boundary_1.cwd_id, nil)
    Assert.equal(descriptor.boundaries.boundary_1.exit_status, nil)
    Assert.equal(descriptor.boundaries.boundary_1.text, nil)
  end,

  command_region_resource_tracks_viewport_changes_and_bounds_visible_data = function()
    local state = State.new(4, 1, { scrollback_limit = 2 })
    marker(state, "A")
    state:scroll_up(1)
    Assert.equal(CommandRegions.descriptor(state).active, false)
    state:scroll_history(1)
    Assert.truthy(CommandRegions.descriptor(state).active)

    local many = State.new(4, CommandRegions.visible_boundary_limit + 1)
    for row = 0, CommandRegions.visible_boundary_limit do
      many:set_cursor(0, row)
      marker(many, "A")
    end
    local descriptor = CommandRegions.descriptor(many)
    Assert.equal(descriptor.boundary_count, CommandRegions.visible_boundary_limit)
    Assert.truthy(descriptor.omitted_boundary_count > 0)
  end,

  command_region_resource_changes_request_a_distinct_invalidation = function()
    local state = State.new(4, 1)
    local reasons = {}
    local renderer = setmetatable({
      command_regions = CommandRegions.descriptor(state),
      invalidate = function(_, reason) reasons[#reasons + 1] = reason end,
    }, { __index = Renderer })
    Assert.truthy(CommandRegions.same(renderer.command_regions, renderer:update_command_regions(state)))
    marker(state, "A")
    local updated = renderer:update_command_regions(state)
    Assert.truthy(updated.active)
    Assert.equal(reasons[1], "command_regions")
  end,
}
