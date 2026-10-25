-- Exercise the live controller, real host callbacks and a raw PTY receiver.
local Dispatcher = require("kiwi.app.product_action_dispatcher")
local Terminal = require("kiwi.session.terminal")
local Search = require("kiwi.input.search")
local Utf8 = require("kiwi.terminal.utf8")
local gtk = os.getenv("KIWI_HOST") == "gtk"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
local Window = require(gtk and "kiwi.platform.gtk_window" or "kiwi.platform.window")
assert(Host.presentation_backend ~= "gtk-gl", "this controller fixture requires WGPU")
local keys = Host.keymap
local capture, config = os.tmpname(), os.tmpname()
local file = assert(io.open(config, "w")); file:write("scrollback-limit = 2000\nlive-config-reload = false\n"); file:close()
local live, dispatcher, title
local terminal_new, dispatcher_new, set_title, await = Terminal.new, Dispatcher.new, Window.set_title, Host.await_events
Terminal.new = function(...) live = terminal_new(...); return live end
Dispatcher.new = function(...) dispatcher = dispatcher_new(...); return dispatcher end
Window.set_title = function(self, text) title = text; return set_title(self, text) end
local function read_capture()
  local stream = assert(io.open(capture, "rb")); local bytes = stream:read("*a"); stream:close(); return bytes
end
local function key(window, value, action, modifiers)
  if not gtk then window.callbacks.key(window.handle, value, 0, action, modifiers or 0)
  else assert(window.on_key(value, action, modifiers or 0)) end
end
local function type_query(window, text)
  local points = {}
  local decoder = Utf8.Decoder.new(function(point) points[#points + 1] = point end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  -- A correlated IME/text event must also bypass Kitty encoding during Find.
  window.on_text(points, { key = string.byte("Q"), action = keys.press, modifiers = 0 })
end
local started, stage, max_step_work, steps, keyboard_flags = nil, 0, 0, 0, 0
Host.await_events = function(application, window, timeout)
  await(application, window, timeout)
  local now, state = window:time(), Terminal.state(live)
  started = started or now
  assert(now - started < 20, "search smoke timed out at stage " .. stage)
  max_step_work = math.max(max_step_work, state.search.last_step_work)
  assert(max_step_work <= Search.step_budget)
  if stage == 0 and state.title == "search-fixture-ready" then
    keyboard_flags = Host.keyboard_supported_flags_for and Host.keyboard_supported_flags_for(window) or Host.keyboard_supported_flags
    assert(state.scrollback:size() > 900 and state.modes.keyboard_flags == keyboard_flags)
    assert(require("bit").band(keyboard_flags, 24) == 24, "fixture needs report-all-keys and associated text")
    assert(dispatcher:handle("search-regex"))
    type_query(window, "^unique é中 (needle|missing)$")
    key(window, keys.key_enter, keys.press); key(window, keys.key_enter, keys.release)
    assert(state:search_pending(), "large-history search did not yield")
    stage = 1
  elseif stage == 1 then
    steps = steps + 1
    if not state:search_pending() then
      local view = state:search_view()
      assert(view.status == "matches" and view.match_count == 1)
      assert(view.current.start_column == 0 and view.current.finish_column == 17)
      assert(title:find("1/1", 1, true), "Find progress did not become a result count")
      assert(read_capture() == "", "Find query or Enter release reached the child: " .. read_capture():gsub(".", function(byte) return string.format("%02x ", byte:byte()) end))
      assert(dispatcher:handle("search-regex")); type_query(window, "[")
      key(window, keys.key_enter, keys.press); key(window, keys.key_enter, keys.release)
      assert(state:search_view().editing and state:search_view().status == "invalid-pattern")
      stage = 2
    end
  elseif stage == 2 then
    assert(title:find("unclosed", 1, true), "invalid regex did not reach the title")
    key(window, keys.key_backspace, keys.press); key(window, keys.key_backspace, keys.release)
    type_query(window, "a+z")
    key(window, keys.key_enter, keys.press); key(window, keys.key_enter, keys.release)
    assert(state:search_pending())
    key(window, keys.key_escape, keys.press); key(window, keys.key_escape, keys.release)
    assert(not state:search_pending() and not state:search_view().active)
    assert(read_capture() == "", "Find control input reached the raw child")
    -- Legacy character delivery after a handled release catches stale GLFW
    -- suppress_text state. This is the only byte the receiver should observe.
    live:write("\27[<u")
    if not gtk then
      key(window, string.byte("X"), keys.press)
      window.callbacks.character(window.handle, 120)
      key(window, string.byte("X"), keys.release)
    else window.on_text({ 120 }) end
    stage = 3
  elseif stage == 3 and #read_capture() > 0 then
    assert(read_capture() == "x", "query input leaked or the next character was suppressed")
    stage = 4; window:request_close()
  end
end
arg = { "--config", config, "--no-restore-layout", "--no-extensions", "--", "python3", "src/tests/fixtures/search_input_child.py", capture }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Terminal.new, Dispatcher.new, Window.set_title, Host.await_events = terminal_new, dispatcher_new, set_title, await
os.remove(capture); os.remove(config)
assert(ok, message); assert(stage == 4, "search fixture ended before all stages completed")
print(string.format("Search smoke passed: real PTY input isolation with Kitty flags=%d, Unicode regex, incremental history (%d ticks, at most %d operations/tick), visible errors, cancellation and subsequent input.", keyboard_flags, steps, max_step_work))
