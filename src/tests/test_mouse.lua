local Assert = require("tests.assert")
local Mouse = require("kiwi.input.mouse")

local function modes(tracking)
  return { mouse_tracking = tracking or "normal", mouse_sgr = true, focus_reporting = true }
end

return {
  mouse_encodes_sgr_button_motion_and_wheel_events = function()
    local mouse = Mouse.new()
    Assert.equal(mouse:button({ button = 0, action = "press", column = 4, row = 2, modifiers = 0x0001 }, modes()), "\27[<4;4;2M")
    Assert.equal(mouse:button({ button = 0, action = "release", column = 4, row = 2, modifiers = 0x0001 }, modes()), "\27[<4;4;2m")
    Assert.equal(mouse:motion({ column = 5, row = 2, modifiers = 0 }, modes("normal")), nil)
    mouse:button({ button = 1, action = "press", column = 5, row = 2, modifiers = 0 }, modes("button"))
    Assert.equal(mouse:motion({ column = 5, row = 2, modifiers = 0 }, modes("button")), "\27[<34;5;2M")
    Assert.equal(mouse:motion({ column = 5, row = 2, modifiers = 0 }, modes("button")), nil)
    mouse:button({ button = 1, action = "release", column = 5, row = 2, modifiers = 0 }, modes("button"))
    Assert.equal(mouse:motion({ column = 6, row = 2, modifiers = 0x0004 }, modes("any")), "\27[<43;6;2M")
    Assert.equal(mouse:wheel({ delta = -2, column = 6, row = 2, modifiers = 0x0002 }, modes()), "\27[<81;6;2M\27[<81;6;2M")
    Assert.equal(mouse:wheel({ delta = 0 / 0, column = 6, row = 2 }, modes()), nil)
  end,
  mouse_reports_only_the_enabled_sgr_tracking_surface = function()
    local mouse = Mouse.new()
    Assert.equal(mouse:button({ button = 0, action = "press", column = 1, row = 1 }, { mouse_tracking = "normal", mouse_sgr = false }), nil)
    Assert.equal(mouse:button({ button = 7, action = "press", column = 1, row = 1 }, modes()), nil)
    mouse:button({ button = 0, action = "press", column = 1, row = 1 }, modes("button"))
    mouse:focus(false, modes())
    Assert.equal(mouse:motion({ column = 2, row = 1 }, modes("button")), nil)
  end,
  mouse_encodes_focus_only_when_requested = function()
    local mouse = Mouse.new()
    Assert.equal(mouse:focus(true, modes()), "\27[I")
    Assert.equal(mouse:focus(false, modes()), "\27[O")
    Assert.equal(mouse:focus(true, { focus_reporting = false }), nil)
  end,
}
