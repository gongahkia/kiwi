local Dispatcher = require("kiwi.app.product_action_dispatcher")
local Terminal = require("kiwi.session.terminal")
local Clipboard = require("kiwi.input.clipboard")
local Renderer = require("kiwi.renderer.renderer")
local gtk = os.getenv("KIWI_HOST") == "gtk"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
local Window = require(gtk and "kiwi.platform.gtk_window" or "kiwi.platform.window")
assert(Host.presentation_backend ~= "gtk-gl", "this fixture requires the WGPU controller")
local keys, capture, config = Host.keymap, os.tmpname(), os.tmpname()
local file = assert(io.open(config, "w")); file:write("live-config-reload = false\n"); file:close()
local live, dispatcher, renderer, title, copied, last_action
local opened = {}
local terminal_new, dispatcher_new, renderer_new, clipboard_new = Terminal.new, Dispatcher.new, Renderer.new, Clipboard.new
local set_title, await, open_uri = Window.set_title, Host.await_events, Window.open_uri
Terminal.new = function(...) live = terminal_new(...); return live end
Renderer.new = function(...) renderer = renderer_new(...); return renderer end
Clipboard.new = function() return clipboard_new({ clipboard_read = function() return "clipboard" end,
  clipboard_write = function(_, text) copied = text; return true end }) end
Window.open_uri = function(_, uri) opened[#opened + 1] = uri; return true end
Dispatcher.new = function(...)
  dispatcher = dispatcher_new(...)
  local handle = dispatcher.handle
  dispatcher.handle = function(self, action) last_action = action; return handle(self, action) end
  return dispatcher
end
Window.set_title = function(self, value) title = value; return set_title(self, value) end
local function received()
  local stream = assert(io.open(capture, "rb")); local value = stream:read("*a"); stream:close(); return value
end
local function key(window, value, action, modifiers)
  if not gtk then window.callbacks.key(window.handle, value, 0, action, modifiers or 0)
  else assert(window.on_key(value, action, modifiers or 0)) end
end
local function text(window, value)
  local points = {}; for index = 1, #value do points[index] = value:byte(index) end
  window.on_text(points, { key = string.byte("Q"), action = keys.press, modifiers = 0 })
end
local started, stage, flags, ticks, maximum = nil, 0, 0, 0, 0
Host.await_events = function(application, window, timeout)
  await(application, window, timeout)
  local now, state = window:time(), Terminal.state(live)
  started = started or now
  assert(now - started < 25, "URL hint smoke timed out at stage " .. stage)
  maximum = math.max(maximum, state.hints.last_step_work or 0); assert(maximum <= 4096)
  if stage == 0 and state.title == "hints-fixture-ready" then
    flags = state.modes.keyboard_flags
    assert(require("bit").band(flags, 24) == 24)
    state.modes.keyboard_flags = 7
    key(window, string.byte("U"), keys.press, keys.mod_control + keys.mod_shift)
    key(window, string.byte("U"), keys.release, keys.mod_control + keys.mod_shift)
    assert(state.hints.active and last_action == "open-url-hints")
    assert(state:hints_pending(), "viewport hint scan did not yield")
    maximum = math.max(maximum, state.hints.last_step_work)
    state.modes.keyboard_flags = flags
    key(window, string.byte("0"), keys.press, keys.mod_control)
    key(window, string.byte("0"), keys.release, keys.mod_control)
    assert(last_action == "reset-font-size")
    stage = 1
  elseif stage == 1 then
    ticks = ticks + 1
    if not state:hints_pending() then
      assert(#state.hints.matches == 3 and renderer.hint_count == 3, "visible labels did not reach rendering")
      assert(title:find("3 links", 1, true))
      text(window, "s"); assert(#opened == 0, "typing a label opened it without Enter")
      key(window, keys.key_enter, keys.press); key(window, keys.key_enter, keys.repeat_action); key(window, keys.key_enter, keys.release)
      assert(#opened == 1 and opened[1] == "https://actual.example/target")
      assert(not state.hints.active and received() == "")
      assert(dispatcher:handle("copy-url-hints")); stage = 2
    end
  elseif stage == 2 and not state:hints_pending() then
    text(window, "a")
    key(window, keys.key_enter, keys.press); key(window, keys.key_enter, keys.release)
    assert(copied == "https://a.example/path(test)")
    assert(received() == "")
    assert(dispatcher:handle("open-url-hints")); stage = 3
  elseif stage == 3 and not state:hints_pending() then
    text(window, "a"); live:write("x")
    key(window, keys.key_enter, keys.press); key(window, keys.key_enter, keys.release)
    assert(#opened == 1 and state.hints.status == "output-changed")
    stage = 4
  elseif stage == 4 then
    assert(title:find("output changed", 1, true))
    key(window, keys.key_escape, keys.press); key(window, keys.key_escape, keys.repeat_action); key(window, keys.key_escape, keys.release)
    live:write("\27[<u")
    if not gtk then
      key(window, string.byte("X"), keys.press); window.callbacks.character(window.handle, 120)
      key(window, string.byte("X"), keys.release)
    else window.on_text({ 120 }) end
    stage = 5
  elseif stage == 5 and #received() > 0 then
    assert(received() == "x", "hint input leaked or subsequent input was suppressed")
    stage = 6; window:request_close()
  end
end
arg = { "--config", config, "--no-restore-layout", "--no-extensions", "--", "python3", "src/tests/fixtures/hints_input_child.py", capture }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Terminal.new, Dispatcher.new, Renderer.new, Clipboard.new = terminal_new, dispatcher_new, renderer_new, clipboard_new
Window.set_title, Host.await_events, Window.open_uri = set_title, await, open_uri
os.remove(capture); os.remove(config)
assert(ok, message); assert(stage == 6, "URL hints fixture ended before completion")
print(string.format("URL hints smoke passed: default binding, global action, rendered labels, explicit open/copy, actual OSC 8 target, stale cancellation, Kitty flags=%d isolation; %d scan ticks, max %d units.", flags, ticks, maximum))
