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
  keyboard_reserves_control_shift_clipboard_actions = function()
    local copy = Keyboard.key(string.byte("C"), glfw.press, glfw.mod_control + glfw.mod_shift, { keyboard_flags = 1 }, glfw)
    Assert.equal(copy.local_action, "copy")
    Assert.truthy(copy.suppress_text)
    local paste = Keyboard.key(string.byte("V"), glfw.press, glfw.mod_control + glfw.mod_shift, { keyboard_flags = 1 }, glfw)
    Assert.equal(paste.local_action, "paste")
    Assert.equal(Keyboard.key(string.byte("F"), glfw.press, glfw.mod_control + glfw.mod_shift, { keyboard_flags = 1 }, glfw).local_action, "search_begin")
    Assert.equal(Keyboard.key(string.byte("G"), glfw.press, glfw.mod_control + glfw.mod_shift, {}, glfw).local_action, "search_next")
    Assert.equal(Keyboard.key(string.byte("R"), glfw.press, glfw.mod_control + glfw.mod_shift, {}, glfw).local_action, "search_previous")
    Assert.truthy(Keyboard.key(string.byte("V"), glfw.repeat_action, glfw.mod_control + glfw.mod_shift, {}, glfw).suppress_text)
  end,
  keyboard_encodes_the_kitty_disambiguation_subset = function()
    local modes = { keyboard_flags = 1 }
    local control_c = Keyboard.key(string.byte("C"), glfw.press, glfw.mod_control, modes, glfw)
    Assert.equal(control_c.bytes, "\27[99;5u")
    Assert.truthy(control_c.suppress_text)
    local alt_shift_a = Keyboard.key(string.byte("A"), glfw.press, glfw.mod_alt + glfw.mod_shift, modes, glfw)
    Assert.equal(alt_shift_a.bytes, "\27[97;4u")
    Assert.truthy(alt_shift_a.suppress_text)
    Assert.equal(Keyboard.key(glfw.key_escape, glfw.press, 0, modes, glfw).bytes, "\27[27u")
    Assert.equal(Keyboard.key(glfw.key_up, glfw.press, glfw.mod_shift, modes, glfw).bytes, "\27[1;2A")
    Assert.equal(Keyboard.key(glfw.key_f6, glfw.press, glfw.mod_control, modes, glfw).bytes, "\27[17;5~")
    Assert.equal(Keyboard.key(glfw.key_up, glfw.release, glfw.mod_shift, modes, glfw), nil)
  end,
}
