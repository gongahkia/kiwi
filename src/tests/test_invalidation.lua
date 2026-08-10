local Assert = require("tests.assert")
local Invalidation = require("kiwi.renderer.invalidation")
local Renderer = require("kiwi.renderer.renderer")

return {
  invalidations_coalesce_reason_categories_until_successful_present = function()
    local invalidation = Invalidation.new()
    invalidation:request("terminal")
    invalidation:request("resize")
    invalidation:request("terminal")
    Assert.truthy(invalidation:due(1))
    Assert.equal(table.concat(invalidation:snapshot().reasons, ","), "resize,terminal")
    invalidation:consume_success(1)
    Assert.equal(invalidation:due(1), false)
  end,
  invalidation_deadlines_coalesce_and_clamp_extension_cadence = function()
    local invalidation = Invalidation.new({ minimum_interval = 0.1, maximum_delay = 2 })
    Assert.near(invalidation:schedule("extension", 10, 0), 10.1, 0.0001)
    Assert.near(invalidation:schedule("cursor", 10, 10), 10.1, 0.0001)
    Assert.equal(invalidation:due(10.09), false)
    Assert.equal(invalidation:due(10.1), true)
    invalidation:consume_success(10.1)
    Assert.equal(invalidation:next_deadline(), nil)
  end,
  invalidations_remain_pending_when_presentation_has_not_succeeded = function()
    local invalidation = Invalidation.new()
    invalidation:request("configuration")
    Assert.truthy(invalidation:due(0))
    Assert.truthy(invalidation:due(1))
    invalidation:consume_success(1)
    Assert.equal(invalidation:due(1), false)
  end,
  selection_only_invalidations_are_a_distinct_bounded_reason = function()
    local invalidation = Invalidation.new()
    invalidation:request("selection")
    Assert.equal(table.concat(invalidation:snapshot().reasons, ","), "selection")
    invalidation:consume_success(1)
    Assert.equal(invalidation:due(1), false)
  end,
  synchronized_output_defers_presentation_and_cursor_style_reaches_the_renderer = function()
    local model = {
      cursor = { column = 3, row = 2, visible = true },
      modes = { cursor_style = 5, synchronized_output = true },
    }
    local cursor = Renderer.cursor_descriptor({}, model)
    Assert.equal(cursor.style, 5)
    Assert.equal(cursor.shape, "bar")
    Assert.equal(cursor.blink, true)
    Assert.equal(Renderer.can_present({}, model), false)
    model.modes.synchronized_output = false
    Assert.equal(Renderer.can_present({}, model), true)
    Assert.near(Renderer.cursor_blink_delay({}, model), 0.5, 0.0001)
    model.modes.cursor_style = 6
    Assert.equal(Renderer.cursor_blink_delay({}, model), nil)
  end,
}
