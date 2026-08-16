local Assert = require("tests.assert")
local Mouse = require("kiwi.input.mouse")
local Utf8 = require("kiwi.terminal.utf8")

local function modes(tracking, encoding)
  return { mouse_tracking = tracking or "normal", mouse_protocol = encoding or "sgr", mouse_sgr = encoding == nil or encoding == "sgr", focus_reporting = true }
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
  mouse_reports_the_declared_tracking_and_encoding_surface = function()
    local mouse = Mouse.new()
    Assert.equal(mouse:button({ button = 0, action = "press", column = 1, row = 1 }, { mouse_tracking = "none" }), nil)
    Assert.equal(mouse:button({ button = 0, action = "press", column = 1, row = 1 }, { mouse_tracking = "normal", mouse_sgr = false }), "\27[M !!")
    Assert.equal(mouse:button({ button = 7, action = "press", column = 1, row = 1 }, modes()), nil)
    mouse:button({ button = 0, action = "press", column = 1, row = 1 }, modes("button"))
    mouse:focus(false, modes())
    Assert.equal(mouse:motion({ column = 2, row = 1 }, modes("button")), nil)
  end,
  mouse_encodes_x10_utf8_and_urxvt_extensions_with_explicit_limits = function()
    local mouse = Mouse.new()
    Assert.equal(mouse:button({ button = 0, action = "press", column = 1, row = 2 }, modes("x10", "x10")), "\27[M !\"")
    Assert.equal(mouse:button({ button = 0, action = "release", column = 1, row = 2 }, modes("x10", "x10")), nil)
    Assert.equal(mouse:button({ button = 0, action = "press", column = 300, row = 400 }, modes("normal", "utf8")), "\27[M " .. Utf8.encode(332) .. Utf8.encode(432))
    Assert.equal(mouse:button({ button = 1, action = "press", column = 300, row = 400 }, modes("normal", "urxvt")), "\27[34;300;400M")
    Assert.equal(mouse:button({ button = 0, action = "press", column = 224, row = 1 }, modes("normal", "x10")), nil)
    Assert.equal(mouse:button({ button = 0, action = "press", column = 2016, row = 1 }, modes("normal", "utf8")), nil)
  end,
  mouse_encodes_focus_only_when_requested = function()
    local mouse = Mouse.new()
    Assert.equal(mouse:focus(true, modes()), "\27[I")
    Assert.equal(mouse:focus(false, modes()), "\27[O")
    Assert.equal(mouse:focus(true, { focus_reporting = false }), nil)
  end,
}
