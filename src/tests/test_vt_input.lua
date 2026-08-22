local Assert = require("tests.assert")
local VT = require("kiwi.vt")

return {
  libkiwi_vt_input_encodes_symbolic_keys_without_glfw = function()
    local Input = VT.Input
    Assert.equal(Input.api_version, VT.api_version)
    Assert.equal(Input.text(0x20ac, {}), "€")
    Assert.equal(Input.key({ key = "up", action = "press" }, { application_cursor = true }).bytes, "\27OA")
    Assert.equal(Input.key({ key = "C", action = "press", modifiers = Input.modifiers.control }, {}).bytes, "\003")
    Assert.equal(Input.key({ key = "escape", action = "press" }, { keyboard_flags = 1 }).bytes, "\27[27u")
    Assert.equal(Input.key({ key = "A", action = "press", modifiers = Input.modifiers.shift, associated_text = { string.byte("A") } }, { keyboard_flags = 24 }).bytes, "\27[97;2;65u")
    Assert.equal(Input.key({ key = "A", action = "press", modifiers = Input.modifiers.control + Input.modifiers.shift, layout_key = string.byte("q"), shifted_key = string.byte("Q"), base_key = string.byte("a") }, { keyboard_flags = 5 }).bytes, "\27[113:81:97;6u")
    Assert.equal(Input.key({ key = "kp_1", action = "press" }, { application_keypad = true }).bytes, "\27Oq")
    Assert.equal(Input.key({ key = "backspace", action = "press" }, { backarrow = true }).bytes, "\b")
  end,
  libkiwi_vt_input_exposes_mouse_focus_and_bracketed_paste_without_host_handles = function()
    local Input = VT.Input
    local mouse = Input.new_mouse()
    local modes = { focus_reporting = true, mouse_protocol = "sgr", mouse_tracking = "normal" }
    Assert.equal(mouse:button({ button = 0, action = "press", column = 4, row = 2, modifiers = Input.modifiers.shift }, modes), "\27[<4;4;2M")
    Assert.equal(mouse:button({ button = 0, action = "press", pixel_x = 14, pixel_y = 22, modifiers = Input.modifiers.shift }, { mouse_protocol = "sgr-pixels", mouse_tracking = "normal" }), "\27[<4;14;22M")
    Assert.equal(mouse:focus(false, modes), "\27[O")
    Assert.equal(Input.paste("hello", { bracketed_paste = true }), "\27[200~hello\27[201~")
  end,
  libkiwi_vt_render_updates_publish_the_input_modes_needed_by_a_host = function()
    local terminal = VT.new({ columns = 2, rows = 1 })
    terminal:write("\27[?1h\27[?67h\27[?1016h\27[?1000h\27[?1004h\27[?1007h\27[?2004h\27[?1049h")
    local view = terminal:begin_render_update()
    Assert.equal(view.input_modes.application_cursor, true)
    Assert.equal(view.input_modes.backarrow, true)
    Assert.equal(view.input_modes.mouse_protocol, "sgr-pixels")
    Assert.equal(view.input_modes.mouse_tracking, "normal")
    Assert.equal(view.input_modes.alternate_scroll, true)
    Assert.equal(view.input_modes.alternate_screen, true)
    Assert.equal(view.input_modes.focus_reporting, true)
    Assert.equal(view.input_modes.bracketed_paste, true)
    terminal:end_render_update(false)
  end,
}
