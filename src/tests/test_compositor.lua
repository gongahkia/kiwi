local Assert = require("tests.assert")
local Compositor = require("kiwi.renderer.compositor")

return {
  compositor_converts_cell_layouts_to_exact_physical_viewports = function()
    local viewport = Compositor.viewport({ x = 3, y = 5, width = 40, height = 20 }, 9, 18)
    Assert.equal(viewport.x, 27)
    Assert.equal(viewport.y, 90)
    Assert.equal(viewport.width, 360)
    Assert.equal(viewport.height, 360)
  end,
  compositor_requires_each_pane_viewport_to_fit_the_shared_surface = function()
    local compositor = Compositor.new({
      native = {},
      window = {},
      width = 100,
      height = 80,
    })
    local renderer = {
      encode_into = function() end,
      finish_frame = function() end,
    }
    compositor:validate({ { renderer = renderer, model = {}, viewport = { x = 0, y = 0, width = 100, height = 80 } } })
    local ok = pcall(function()
      compositor:validate({ { renderer = renderer, model = {}, viewport = { x = 60, y = 0, width = 41, height = 80 } } })
    end)
    Assert.truthy(not ok)
  end,
  compositor_tracks_the_earliest_pane_animation_and_synchronized_output = function()
    local compositor = Compositor.new({ native = {}, window = { minimized = false }, width = 100, height = 80 })
    local entries = {
      { model = { modes = {} }, renderer = { needs_render = function(_, now) return now >= 3 end, next_render_deadline = function() return 3 end } },
      { model = { modes = {} }, renderer = { needs_render = function(_, now) return now >= 2 end, next_render_deadline = function() return 2 end } },
    }
    Assert.equal(compositor:next_render_deadline(entries), 2)
    Assert.truthy(not compositor:needs_render(entries, 1))
    Assert.truthy(compositor:needs_render(entries, 2))
    Assert.truthy(compositor:can_present(entries))
    entries[2].model.modes.synchronized_output = true
    Assert.truthy(not compositor:can_present(entries))
  end,
}
