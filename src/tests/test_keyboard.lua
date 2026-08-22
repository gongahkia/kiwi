local Assert = require("tests.assert")
local glfw = require("kiwi.ffi.glfw").constants
local Keyboard = require("kiwi.input.keyboard")

return {
  keyboard_encodes_text_and_terminal_control_keys = function()
    Assert.equal(Keyboard.text(0x20ac), "€")
    Assert.equal(Keyboard.key(glfw.key_enter, glfw.press, 0, {}, glfw).bytes, "\r")
    Assert.equal(Keyboard.key(glfw.key_backspace, glfw.press, 0, {}, glfw).bytes, "\127")
    Assert.equal(Keyboard.key(glfw.key_backspace, glfw.press, 0, { backarrow = true }, glfw).bytes, "\b")
    Assert.equal(Keyboard.key(string.byte("C"), glfw.press, glfw.mod_control, {}, glfw).bytes, "\003")
  end,
  keyboard_encodes_xterm_modify_other_keys_without_duplicate_text = function()
    local level_one = { modify_other_keys = 1 }
    local level_two = { modify_other_keys = 2 }
    local level_three = { modify_other_keys = 3 }
    local alt = Keyboard.key(string.byte("A"), glfw.press, glfw.mod_alt, level_one, glfw)
    Assert.equal(alt.bytes, "\27[27;3;97~")
    Assert.truthy(alt.suppress_text)
    Assert.equal(Keyboard.key(string.byte("A"), glfw.press, glfw.mod_shift, level_one, glfw), nil)
    local control = Keyboard.key(string.byte("C"), glfw.press, glfw.mod_control, level_two, glfw)
    Assert.equal(control.bytes, "\27[27;5;99~")
    Assert.truthy(control.suppress_text)
    local plain = Keyboard.key(string.byte("A"), glfw.press, 0, level_three, glfw)
    Assert.equal(plain.bytes, "\27[27;1;97~")
    Assert.truthy(plain.suppress_text)
  end,
  keyboard_tracks_normal_and_application_cursor_modes = function()
    Assert.equal(Keyboard.key(glfw.key_up, glfw.press, 0, { application_cursor = false }, glfw).bytes, "\27[A")
    Assert.equal(Keyboard.key(glfw.key_up, glfw.press, 0, { application_cursor = true }, glfw).bytes, "\27OA")
    Assert.equal(Keyboard.key(glfw.key_page_up, glfw.press, glfw.mod_shift, {}, glfw).local_action, "scroll_up")
  end,
  keyboard_encodes_numeric_and_application_keypads = function()
    Assert.equal(Keyboard.key(glfw.key_kp_1, glfw.press, 0, {}, glfw).bytes, "1")
    Assert.equal(Keyboard.key(glfw.key_kp_decimal, glfw.press, 0, {}, glfw).bytes, ".")
    Assert.equal(Keyboard.key(glfw.key_kp_enter, glfw.press, 0, { application_keypad = true }, glfw).bytes, "\27OM")
    local one = Keyboard.key(glfw.key_kp_1, glfw.press, 0, { application_keypad = true }, glfw)
    Assert.equal(one.bytes, "\27Oq")
    Assert.truthy(one.suppress_text)
    Assert.equal(Keyboard.key(glfw.key_kp_1, glfw.release, 0, { application_keypad = true }, glfw), nil)
    Assert.equal(Keyboard.key(glfw.key_kp_1, glfw.press, 0, { application_keypad = true, keyboard_flags = 8 }, glfw), nil)
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
    Assert.equal(Keyboard.key(string.byte("O"), glfw.press, glfw.mod_control + glfw.mod_shift, {}, glfw).local_action, "open_hyperlink")
    Assert.truthy(Keyboard.key(string.byte("V"), glfw.repeat_action, glfw.mod_control + glfw.mod_shift, {}, glfw).suppress_text)
  end,
  keyboard_reserves_control_alt_command_region_navigation = function()
    local previous = Keyboard.key(string.byte("P"), glfw.press, glfw.mod_control + glfw.mod_alt, { keyboard_flags = 1 }, glfw)
    Assert.equal(previous.local_action, "region_previous_prompt")
    Assert.truthy(previous.suppress_text)
    Assert.equal(Keyboard.key(string.byte("C"), glfw.press, glfw.mod_control + glfw.mod_alt + glfw.mod_shift, {}, glfw).local_action, "region_next_command")
    Assert.equal(Keyboard.key(string.byte("O"), glfw.repeat_action, glfw.mod_control + glfw.mod_alt, {}, glfw).local_action, "region_previous_output")
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
  keyboard_reports_kitty_event_types_for_non_text_keys = function()
    local modes = { keyboard_flags = 2 }
    Assert.equal(Keyboard.key(glfw.key_up, glfw.press, 0, modes, glfw).bytes, "\27[1;1:1A")
    Assert.equal(Keyboard.key(glfw.key_up, glfw.repeat_action, 0, modes, glfw).bytes, "\27[1;1:2A")
    Assert.equal(Keyboard.key(glfw.key_up, glfw.release, 0, modes, glfw).bytes, "\27[1;1:3A")
    Assert.equal(Keyboard.key(string.byte("A"), glfw.release, 0, modes, glfw), nil)
  end,
  keyboard_reports_all_kitty_keys_as_escape_codes = function()
    local modes = { keyboard_flags = 8 }
    local letter = Keyboard.key(string.byte("A"), glfw.press, 0, modes, glfw)
    Assert.equal(letter.bytes, "\27[97u")
    Assert.truthy(letter.suppress_text)
    Assert.equal(Keyboard.text(string.byte("a"), modes), nil)
    Assert.equal(Keyboard.key(glfw.key_enter, glfw.press, 0, modes, glfw).bytes, "\27[13u")
    Assert.equal(Keyboard.key(string.byte("C"), glfw.press, glfw.mod_control + glfw.mod_shift, modes, glfw).bytes, "\27[99;6u")
    local event_modes = { keyboard_flags = 10 }
    Assert.equal(Keyboard.key(string.byte("A"), glfw.press, 0, event_modes, glfw).bytes, "\27[97;1:1u")
    Assert.equal(Keyboard.key(string.byte("A"), glfw.release, 0, event_modes, glfw).bytes, "\27[97;1:3u")
  end,
  keyboard_reports_kitty_associated_text_only_with_all_key_reporting = function()
    local modes = { keyboard_flags = 24 }
    local key = Keyboard.key(string.byte("A"), glfw.press, glfw.mod_shift, modes, glfw, { associated_text = { string.byte("A") } })
    Assert.equal(key.bytes, "\27[97;2;65u")
    Assert.equal(Keyboard.text_sequence({ 0x00e5 }, modes), "\27[0;;229u")
    Assert.equal(Keyboard.key(string.byte("A"), glfw.press, glfw.mod_shift, { keyboard_flags = 16 }, glfw, { associated_text = { string.byte("A") } }), nil)
  end,
}
