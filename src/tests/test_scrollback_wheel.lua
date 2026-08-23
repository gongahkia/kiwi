local Assert = require("tests.assert")
local Wheel = require("kiwi.input.scrollback_wheel")

local primary = { alternate_screen = false, mouse_tracking = "none" }

return {
  scrollback_wheel_accumulates_fractional_primary_screen_input_per_session = function()
    local wheel = Wheel.new()
    Assert.equal(wheel:consume({ delta = 0.5 }, primary), nil)
    Assert.equal(wheel:consume({ delta = 0.5 }, primary), 1)
    Assert.equal(wheel:consume({ delta = 0.5 }, primary), nil)
    Assert.equal(wheel:consume({ delta = -0.25 }, primary), nil)
    Assert.equal(wheel:consume({ delta = -0.75 }, primary), -1)
  end,
  scrollback_wheel_preserves_application_mouse_and_alternate_screen_ownership = function()
    local wheel = Wheel.new()
    Assert.equal(wheel:consume({ delta = 0.5 }, primary), nil)
    Assert.equal(wheel:consume({ delta = 1 }, { alternate_screen = false, mouse_tracking = "normal" }), nil)
    Assert.equal(wheel:consume({ delta = 0.5 }, primary), nil)
    Assert.equal(wheel:consume({ delta = 1 }, { alternate_screen = true, mouse_tracking = "none" }), nil)
    Assert.equal(wheel:consume({ delta = 1 }, primary), 1)
  end,
  scrollback_wheel_bounds_invalid_and_oversized_host_deltas = function()
    local wheel = Wheel.new()
    Assert.equal(wheel:consume({ delta = 0 / 0 }, primary), nil)
    Assert.equal(wheel:consume({ delta = math.huge }, primary), nil)
    Assert.equal(wheel:consume({ delta = 1000 }, primary), Wheel.maximum_lines_per_event)
    Assert.equal(wheel:consume({ delta = -1000 }, primary), -Wheel.maximum_lines_per_event)
  end,
}
