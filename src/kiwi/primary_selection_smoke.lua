assert(os.getenv("KIWI_PRIMARY_SMOKE_ISOLATED") == "1", "primary smoke must use its private display server")
local Terminal = require("kiwi.session.terminal")
local Primary = require("kiwi.input.primary_selection")
local Font = require("kiwi.font.system")
local gtk = os.getenv("KIWI_HOST") == "gtk"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
local Window = require(gtk and "kiwi.platform.gtk_window" or "kiwi.platform.window")
local gdk_primary = gtk and os.getenv("GDK_BACKEND") == "wayland"
local window_new = Window.new
local handshake = os.getenv("KIWI_PRIMARY_SMOKE_DIRECTORY")
if gdk_primary then
  assert(handshake, "Wayland primary smoke needs its focus handshake")
  local first = true
  Window.new = function(...)
    local window = window_new(...)
    if first then
      first = false
      local file = assert(io.open(handshake .. "/ready", "w")); file:write("ready"); file:close()
      local deadline = window:time() + 5
      while true do
        Window.pump(window, 0.01)
        file = io.open(handshake .. "/go", "r")
        if file then file:close(); break end
        assert(window:time() < deadline, "Wayland focus handshake timed out")
      end
    end
    return window
  end
end
local function retired_count()
  return gdk_primary and 0 or require("kiwi.platform.primary_read").retired_count()
end
local terminal_new, primary_new, font_new, await = Terminal.new, Primary.new, Font.new, Host.await_events
local live, primary, font, probe
Terminal.new = function(...) live = terminal_new(...); return live end
Primary.new = function(...) primary = primary_new(...); return primary end
Font.new = function(...) font = font_new(...); return font end
local capture, config = os.tmpname(), os.tmpname()
local stream = assert(io.open(config, "w")); stream:write("primary-selection = true\nlive-config-reload = false\n"); stream:close()
local expected, stage, started, reported_stage = "", 0, nil, nil
local function received()
  local file = assert(io.open(capture, "rb")); local value = file:read("*a"); file:close(); return value
end
local function key(window, value, action, modifiers)
  if gtk then window.on_key(value, action, modifiers or 0)
  else window.callbacks.key(window.handle, value, 0, action, modifiers or 0) end
end
local function shortcut(window, value, modifiers)
  key(window, value, Host.keymap.press, modifiers)
  key(window, value, Host.keymap.repeat_action, modifiers)
  key(window, value, Host.keymap.release, modifiers)
end
local function pointer(window, button, action, column, shift)
  local scale = font.content_scale or 1
  local x, y = (column + 0.2) * font.cell_width / scale, 0.2 * font.cell_height / scale
  if gtk then
    local native_button = button == 0 and 1 or button == 2 and 2 or 3
    window.callbacks.pointer(nil, 2, x, y, 0, 0, native_button, action == "press" and 1 or 0, shift and 1 or 0)
  else
    local original = window.cursor_position
    window.cursor_position = function() return x, y end
    window.callbacks.mouse_button(window.handle, button, action == "press" and 1 or 0, shift and 1 or 0)
    window.cursor_position = original
  end
end
Host.await_events = function(application, window, timeout)
  if gdk_primary and stage ~= reported_stage then
    io.stderr:write("Wayland PRIMARY controller stage ", stage, "\n")
    reported_stage = stage
  end
  -- The test driver polls a private capture file and a separate selection
  -- requester. Those are not application event sources; give the fixture its
  -- own bounded tick instead of relying on a production fallback timer.
  await(application, window, math.min(timeout, 0.01))
  local state, now = Terminal.state(live), window:time()
  started = started or now
  assert(now - started < 25, "primary smoke timed out at stage " .. stage .. ", status=" .. primary.status
    .. ", vi=" .. tostring(state.vi.primary_revision) .. "/" .. tostring(primary.keyboard_revision)
    .. ", generation=" .. tostring(state.vi.primary_generation) .. "/" .. tostring(state.search_generation))
  if stage == 0 and state.title == "primary-fixture-ready" then
    assert(window:primary_supported())
    assert(window:clipboard_write("ordinary clipboard"))
    pointer(window, 0, "press", 0)
    pointer(window, 0, "release", 8)
    assert(primary.status == "published")
    probe = assert(window:primary_read(1024))
    stage = 1
  elseif stage == 1 then
    local text, status = probe:poll()
    if status ~= "pending" then
      assert(text == "primary 中", "native primary publication failed: " .. tostring(status))
      probe = nil
      assert(window:clipboard_read(1024) == "ordinary clipboard")
      pointer(window, 2, "press", 0); pointer(window, 2, "release", 0)
      assert(primary.request, "middle click did not initiate asynchronous paste")
      expected = "\27[200~primary 中\27[201~"
      stage = 2
    end
  elseif stage == 2 and #received() >= #expected then
    assert(received() == expected, "middle-click paste bytes differ")
    live:write("\27[?1000h\27[?1006h")
    pointer(window, 2, "press", 0); pointer(window, 2, "release", 0)
    pointer(window, 1, "press", 0); pointer(window, 1, "release", 0)
    expected = expected .. "\27[<1;1;1M\27[<1;1;1m\27[<2;1;1M\27[<2;1;1m"
    assert(primary.request == nil, "application-owned mouse initiated a paste")
    stage = 3
  elseif stage == 3 and #received() >= #expected then
    assert(received() == expected, "application mouse buttons were swapped")
    assert(window:primary_write("replacement"))
    pointer(window, 2, "press", 0, true); pointer(window, 2, "release", 0, true)
    assert(primary.request)
    expected = expected .. "\27[200~replacement\27[201~"
    stage = 4
  elseif stage == 4 and #received() >= #expected then
    assert(received() == expected, "Shift override used stale text or leaked mouse input")
    pointer(window, 2, "press", 0, true)
    assert(primary.request)
    window.on_focus(false)
    assert(primary.cancelled and primary.target == nil, "focus loss retained a paste target")
    pointer(window, 2, "release", 0, true)
    window.on_focus(true)
    assert(window:clipboard_read(1024) == "ordinary clipboard")
    stage = 5
  elseif stage == 5 and primary.request == nil then
    assert(received() == expected, "cancelled paste reached the child")
    -- Closing a requester must not crash the still-running selection owner.
    local other = Window.new(200, 100, "Primary closing requester")
    local original_primary = primary
    local closing = Primary.new(other)
    primary = original_primary
    assert(closing:button({ kind = "button", button = 2, action = "press", modifiers = 1 }, state, true))
    closing:destroy(); other:destroy()
    assert(retired_count() == (gdk_primary and 0 or 1))
    stage = 6
  elseif stage == 6 and retired_count() == 0 then
    assert(received() == expected)
    local reads = {}
    for index = 1, 16 do reads[index] = assert(window:primary_read(1024)) end
    local overflow, reason = window:primary_read(1024)
    assert(overflow == nil and reason == "busy", "process read limit was not enforced")
    for _, read in ipairs(reads) do read:retire() end
    assert(retired_count() == (gdk_primary and 0 or 16))
    stage = 7
  elseif stage == 7 and retired_count() == 0 then
    assert(received() == expected)
    state:set_selection(0, 0, 0, 7)
    shortcut(window, Host.keymap.key_insert, Host.keymap.mod_control + Host.keymap.mod_shift)
    assert(primary.status == "published", "default keyboard primary copy did not dispatch")
    probe = assert(window:primary_read(1024))
    stage = 8
  elseif stage == 8 then
    local text, status = probe:poll()
    if status ~= "pending" then
      assert(text == "primary", "keyboard copy did not publish selected text")
      probe = nil
      shortcut(window, Host.keymap.key_insert, Host.keymap.mod_shift)
      assert(primary.request, "default keyboard primary paste did not dispatch")
      expected = expected .. "\27[200~primary\27[201~"
      stage = 9
    end
  elseif stage == 9 and #received() >= #expected then
    assert(received() == expected, "keyboard primary paste repeated or leaked release bytes")
    -- Xvfb has no window manager to return focus after the temporary requester
    -- closes. Establish focus before injecting keyboard-driven selection.
    window.on_focus(true)
    primary.status = "awaiting-vi-publication"
    -- Initial native-tab allocation can retain blank rows in history. This
    -- fixture tests publication of the visible first row, not startup reflow.
    state:clear_scrollback()
    shortcut(window, Host.keymap.key_space, Host.keymap.mod_control + Host.keymap.mod_shift)
    assert(state.vi.active)
    window.on_text({ 103, 103, 48, 118, 108, 108 }) -- gg0vll selects "pri".
    stage = 10
  elseif stage == 10 and primary.status == "published" then
    probe = assert(window:primary_read(1024))
    stage = 11
  elseif stage == 11 then
    local text, status = probe:poll()
    if status ~= "pending" then
      assert(text == "pri", "completed vi selection was not published: " .. tostring(text) .. "/" .. tostring(status))
      probe = nil
      assert(window:clipboard_read(1024) == "ordinary clipboard")
      assert(received() == expected, "vi primary selection reached the child")
      window.on_text({ 47 }) -- Vi Find; primary paste belongs to this query.
      assert(state.search.editing)
      shortcut(window, Host.keymap.key_insert, Host.keymap.mod_shift)
      assert(primary.request)
      stage = 12
    end
  elseif stage == 12 and state.search.query == "pri" then
    assert(received() == expected, "Find primary paste reached the child")
    stage = 13; window:request_close()
  end
end
arg = { "--config", config, "--no-restore-layout", "--no-extensions", "--", "python3", "src/tests/fixtures/primary_input_child.py", capture }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
if probe then probe:destroy() end
Terminal.new, Primary.new, Font.new, Host.await_events = terminal_new, primary_new, font_new, await
Window.new = window_new
os.remove(capture); os.remove(config)
assert(ok, message); assert(stage == 13)
print("Primary selection host smoke passed: Unicode publication, clipboard isolation, bracketed middle/keyboard paste, native button mapping, mouse capture/Shift override, replacement, focus/window cancellation, bounded retirement and vi publication.")
