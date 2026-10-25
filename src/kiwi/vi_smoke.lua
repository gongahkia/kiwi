-- Live controller + host callbacks + a raw PTY receiver. Clipboard uses a
-- private bridge so qualification cannot overwrite the user's clipboard.
local Dispatcher = require("kiwi.app.product_action_dispatcher")
local Terminal = require("kiwi.session.terminal")
local Clipboard = require("kiwi.input.clipboard")
local Utf8 = require("kiwi.terminal.utf8")
local gtk = os.getenv("KIWI_HOST") == "gtk"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
local Window = require(gtk and "kiwi.platform.gtk_window" or "kiwi.platform.window")
assert(Host.presentation_backend ~= "gtk-gl", "this fixture requires the WGPU controller")
local keys = Host.keymap
local capture, config = os.tmpname(), os.tmpname()
local file = assert(io.open(config, "w")); file:write("scrollback-limit = 2000\nlive-config-reload = false\n"); file:close()
local live, dispatcher, title, last_action, copied
local terminal_new, dispatcher_new, clipboard_new = Terminal.new, Dispatcher.new, Clipboard.new
local set_title, await = Window.set_title, Host.await_events
Terminal.new = function(...) live = terminal_new(...); return live end
Clipboard.new = function() return clipboard_new({ clipboard_read = function() return "clipboard" end,
  clipboard_write = function(_, text) copied = text; return true end }) end
Dispatcher.new = function(...)
  dispatcher = dispatcher_new(...)
  local handle = dispatcher.handle
  dispatcher.handle = function(self, action) last_action = action; return handle(self, action) end
  return dispatcher
end
Window.set_title = function(self, text) title = text; return set_title(self, text) end
local function received()
  local stream = assert(io.open(capture, "rb")); local bytes = stream:read("*a"); stream:close(); return bytes
end
local function key(window, value, action, modifiers)
  if not gtk then window.callbacks.key(window.handle, value, 0, action, modifiers or 0)
  else assert(window.on_key(value, action, modifiers or 0)) end
end
local function text(window, value)
  local points = {}
  local decoder = Utf8.Decoder.new(function(point) points[#points + 1] = point end)
  for index = 1, #value do decoder:feed_byte(value:byte(index)) end
  decoder:finish()
  window.on_text(points, { key = string.byte("Q"), action = keys.press, modifiers = 0 })
end
local started, stage, flags, steps, maximum = nil, 0, 0, 0, 0
Host.await_events = function(application, window, timeout)
  await(application, window, timeout)
  local now, state = window:time(), Terminal.state(live)
  started = started or now
  assert(now - started < 25, "vi smoke timed out at stage " .. stage)
  maximum = math.max(maximum, state.vi.last_step_work or 0)
  assert(maximum <= 4096)
  if stage == 0 and state.title == "search-fixture-ready" then
    flags = state.modes.keyboard_flags
    assert(require("bit").band(flags, 24) == 24)
    state.modes.keyboard_flags = 7
    key(window, keys.key_space, keys.press, keys.mod_control + keys.mod_shift)
    key(window, keys.key_space, keys.release, keys.mod_control + keys.mod_shift)
    assert(state.vi.active and last_action == "toggle-vi-mode", "default vi shortcut did not dispatch")
    state.modes.keyboard_flags = flags
    key(window, string.byte("0"), keys.press, keys.mod_control)
    key(window, string.byte("0"), keys.release, keys.mod_control)
    assert(last_action == "reset-font-size", "vi captured a global product binding")
    text(window, "gg0wvey")
    assert(copied == "history", "vi did not copy through the private clipboard: " .. tostring(copied))
    text(window, "/^unique é中 (needle|missing)$")
    key(window, keys.key_enter, keys.press); key(window, keys.key_enter, keys.release)
    assert(state:search_pending()); stage = 1
  elseif stage == 1 then
    steps = steps + 1
    if not state:search_pending() then
      assert(state:vi_view().line_id == state:search_view().current.line_id)
      assert(title:find("Vi", 1, true) and title:find("match 1/1", 1, true))
      assert(received() == "", "vi/search input reached the child")
      -- A long logical word forces the navigation loop to yield and resume.
      live:write("\r\n")
      local document = state:document()
      local id = document:row(state.scrollback:size() + state.cursor.row + 1).line_id
      live:write(string.rep("a", 12000))
      state.vi:set_position(state, state:document():position(id), 0)
      text(window, "e"); assert(state:vi_pending(), "long word motion did not yield")
      stage = 2
    end
  elseif stage == 2 then
    steps = steps + 1
    if not state:vi_pending() then
      assert(state.vi.status == "normal")
      assert(received() == "", "navigation input reached the child")
      key(window, string.byte("I"), keys.press)
      text(window, "i")
      key(window, string.byte("I"), keys.repeat_action)
      key(window, string.byte("I"), keys.release)
      assert(not state.vi.active)
      -- A subsequent character must reach the child after owned key releases.
      live:write("\27[<u")
      if not gtk then
        key(window, string.byte("X"), keys.press)
        window.callbacks.character(window.handle, 120)
        key(window, string.byte("X"), keys.release)
      else window.on_text({ 120 }) end
      stage = 3
    end
  elseif stage == 3 and #received() > 0 then
    assert(received() == "x", "vi key leaked or post-vi text was lost")
    stage = 4; window:request_close()
  end
end
arg = { "--config", config, "--no-restore-layout", "--no-extensions", "--", "python3", "src/tests/fixtures/search_input_child.py", capture }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Terminal.new, Dispatcher.new, Clipboard.new = terminal_new, dispatcher_new, clipboard_new
Window.set_title, Host.await_events = set_title, await
os.remove(capture); os.remove(config)
assert(ok, message); assert(stage == 4, "vi fixture ended before completion")
print(string.format("Vi smoke passed: default shortcut, global action, private copy, Unicode regex, bounded navigation (%d ticks, max %d operations), Kitty flags=%d input isolation and return to shell.", steps, maximum, flags))
