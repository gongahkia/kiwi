local Assert = require("tests.assert")
local glfw = require("kiwi.ffi.glfw").constants
local Keyboard = require("kiwi.input.keyboard")

return {
  keyboard_encodes_text_and_terminal_control_keys = function()
    Assert.equal(Keyboard.text(0x20ac), "€")
    Assert.equal(Keyboard.key(glfw.key_enter, glfw.press, 0, {}, glfw).bytes, "\r")
    Assert.equal(Keyboard.key(glfw.key_backspace, glfw.press, 0, {}, glfw).bytes, "\127")
    Assert.equal(Keyboard.key(string.byte("C"), glfw.press, glfw.mod_control, {}, glfw).bytes, "\003")
  end,
  keyboard_tracks_normal_and_application_cursor_modes = function()
    Assert.equal(Keyboard.key(glfw.key_up, glfw.press, 0, { application_cursor = false }, glfw).bytes, "\27[A")
    Assert.equal(Keyboard.key(glfw.key_up, glfw.press, 0, { application_cursor = true }, glfw).bytes, "\27OA")
    Assert.equal(Keyboard.key(glfw.key_page_up, glfw.press, glfw.mod_shift, {}, glfw).local_action, "scroll_up")
  end,
}
