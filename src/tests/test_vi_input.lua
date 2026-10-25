local Assert = require("tests.assert")
local Terminal = require("kiwi.session.terminal")
local Input = require("kiwi.input.modal_input")
local Clipboard = require("kiwi.input.clipboard")
local Interaction = require("kiwi.app.interaction_actions")
local keys = { press = 1, release = 0, repeat_action = 2, mod_shift = 1, mod_control = 2,
  mod_alt = 4, mod_super = 8, key_space = 32, key_escape = 256, key_enter = 257,
  key_backspace = 259, key_right = 262, key_left = 263, key_down = 264, key_up = 265,
  key_page_up = 266, key_page_down = 267, key_home = 268, key_end = 269, key_f3 = 292 }
local function fixture()
  local terminal = Terminal.new({ columns = 20, rows = 4 })
  terminal:write("one 中 two\r\none next\r\nlast one")
  local state = Terminal.state(terminal)
  state.modes.keyboard_flags = 31
  Interaction.terminal("toggle-vi-mode", state)
  local input = Input.new()
  Input.commit(state, "gg0")
  return state, input, terminal
end
local function finish(state)
  local ticks = 0
  while state:navigation_pending() do state:navigation_step(23); ticks = ticks + 1; assert(ticks < 10000) end
end
return {
  vi_pointer_and_ime_commits_are_local_even_with_child_mouse_and_keyboard_protocols = function()
    local state = fixture()
    state.modes.mouse_tracking, state.modes.mouse_sgr = "any", true
    Assert.truthy(Input.pointer(state, { kind = "button", button = 0, action = "press", selection_row = 1, selection_column = 2 }))
    Assert.equal(state:vi_view().row_index, 2); Assert.equal(state:vi_view().column, 2)
    Assert.truthy(Input.pointer(state, { kind = "motion" }))
    local Keyboard = require("kiwi.input.keyboard")
    local text = Keyboard.text_sequence({ 102, 0x4e2d }, Input.encoding_modes(state))
    Assert.equal(text, "f中")
    Assert.truthy(Input.commit(state, text))
    state.vi:leave(state)
    Assert.equal(Input.encoding_modes(state), state.modes)
    Assert.equal(Input.pointer(state, { kind = "button" }), false)
  end,
  vi_committed_commands_counts_and_inline_unicode_ignore_child_keyboard_modes = function()
    local state, input = fixture()
    local descriptor = input:key(state, string.byte("L"), keys.press, 0, keys)
    Assert.truthy(descriptor.handled); Assert.equal(descriptor.suppress_text, false)
    Assert.truthy(Input.text(state, { string.byte("2"), string.byte("l") }))
    Assert.equal(state:vi_view().column, 2)
    Input.commit(state, "f中"); Assert.equal(state:vi_view().column, 4)
    Input.commit(state, "2gg"); Assert.equal(state:vi_view().row_index, 2)
    Input.commit(state, "999999999999")
    Assert.equal(state.vi.count, "9999")
    input:key(state, keys.key_escape, keys.press, 0, keys)
    Assert.equal(state.vi.count, ""); Assert.equal(state.cursor.row, 2)
  end,
  vi_repeats_and_releases_stay_owned_after_exit_and_across_pane_switches = function()
    local state, input = fixture()
    input:key(state, string.byte("I"), keys.press, 0, keys)
    Assert.truthy(Input.commit(state, "ixyz"))
    Assert.equal(state.vi.active, false)
    Assert.truthy(input:key(state, string.byte("I"), keys.repeat_action, 0, keys).suppress_text)
    local other = Terminal.state(Terminal.new({ columns = 2, rows = 2 }))
    Assert.truthy(input:key(other, string.byte("I"), keys.release, 0, keys).handled)
    Assert.equal(input:key(other, string.byte("I"), keys.press, 0, keys), nil)
    Assert.equal(Input.commit(other, "x"), false)
    Assert.equal(state:pop_responses()[1], nil)
  end,
  vi_fresh_press_recovers_from_a_lost_release = function()
    local state, input = fixture()
    input:key(state, string.byte("C"), keys.press, keys.mod_control, keys)
    Assert.equal(state.vi.active, false)
    Assert.truthy(input:key(state, string.byte("C"), keys.repeat_action, keys.mod_control, keys).handled)
    Assert.equal(input:key(state, string.byte("C"), keys.press, keys.mod_control, keys), nil)
    Assert.equal(input:key(state, string.byte("C"), keys.release, keys.mod_control, keys), nil)
  end,
  vi_global_action_claims_do_not_disable_navigation_repeats = function()
    local state, input = fixture()
    input:claim(string.byte("P"))
    Assert.truthy(input:key(state, string.byte("P"), keys.repeat_action, keys.mod_super, keys).suppress_text)
    Assert.truthy(input:key(state, string.byte("P"), keys.release, keys.mod_super, keys).handled)
    input:key(state, keys.key_right, keys.press, 0, keys)
    input:key(state, keys.key_right, keys.repeat_action, 0, keys)
    Assert.equal(state:vi_view().column, 2)
    Assert.truthy(input:key(state, keys.key_right, keys.release, 0, keys).handled)
  end,
  vi_visual_modes_copy_through_clipboard_and_paste_never_reaches_child = function()
    local state, input = fixture()
    local copied
    local clipboard = Clipboard.new({ clipboard_read = function() return "bad" end,
      clipboard_write = function(_, text) copied = text; return true end })
    Input.commit(state, "wv", clipboard)
    Assert.equal(state.vi.visual, "character")
    Input.commit(state, "y", clipboard)
    Assert.equal(copied, "中"); Assert.equal(state.vi.visual, nil)
    input:key(state, string.byte("V"), keys.press, keys.mod_control, keys, clipboard)
    Assert.equal(state.vi.visual, "block")
    input:key(state, keys.key_down, keys.press, 0, keys, clipboard)
    Assert.truthy(state:selection_view().mode == "block")
    Assert.equal(select(2, Interaction.terminal("paste", state, clipboard, function() error("vi paste leaked") end)), "vi-active")
    input:key(state, keys.key_escape, keys.press, 0, keys)
    Assert.equal(state.vi.visual, nil); Assert.truthy(state.vi.active)
  end,
  vi_search_is_relative_directional_and_wraps_without_moving_application_cursor = function()
    local state, input = fixture()
    local column, row = state.cursor.column, state.cursor.row
    Input.commit(state, "/one")
    Assert.equal(state:search_view().query, "one"); Assert.equal(state:search_view().mode, "regex")
    input:key(state, keys.key_enter, keys.press, 0, keys); finish(state)
    input:key(state, keys.key_enter, keys.release, 0, keys)
    Assert.equal(state:vi_view().row_index, 2)
    Input.commit(state, "n"); Assert.equal(state:vi_view().row_index, 3)
    Input.commit(state, "N"); Assert.equal(state:vi_view().row_index, 2)
    Input.commit(state, "?one")
    input:key(state, keys.key_enter, keys.press, 0, keys); finish(state)
    input:key(state, keys.key_enter, keys.release, 0, keys)
    Assert.equal(state:vi_view().row_index, 1)
    Input.commit(state, "n"); Assert.equal(state:vi_view().row_index, 3)
    Assert.equal(state.cursor.column, column); Assert.equal(state.cursor.row, row)
    Assert.truthy(Input.title(state, "fallback"):find("Vi", 1, true))
  end,
  vi_opens_only_the_explicit_hyperlink_at_its_cursor = function()
    local state, input, terminal = fixture()
    terminal:write("\27[H\27]8;;https://example.com\27\\linked\27]8;;\27\\")
    local uri
    local hyperlink = require("kiwi.input.hyperlink").new({ open_uri = function(_, value) uri = value; return true end })
    input:key(state, keys.key_enter, keys.press, 0, keys, nil, hyperlink)
    Assert.equal(uri, "https://example.com")
    Assert.equal(state.vi.status, "opened-link")
  end,
}
