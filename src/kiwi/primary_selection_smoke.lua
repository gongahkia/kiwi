assert(os.getenv("KIWI_PRIMARY_SMOKE_ISOLATED") == "1", "primary smoke must use its private Xvfb server")
local Terminal = require("kiwi.session.terminal")
local Primary = require("kiwi.input.primary_selection")
local Font = require("kiwi.font.system")
local gtk = os.getenv("KIWI_HOST") == "gtk"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
local Window = require(gtk and "kiwi.platform.gtk_window" or "kiwi.platform.window")
local terminal_new, primary_new, font_new, await = Terminal.new, Primary.new, Font.new, Host.await_events
local live, primary, font, probe
Terminal.new = function(...) live = terminal_new(...); return live end
Primary.new = function(...) primary = primary_new(...); return primary end
Font.new = function(...) font = font_new(...); return font end
local capture, config = os.tmpname(), os.tmpname()
local stream = assert(io.open(config, "w")); stream:write("primary-selection = true\nlive-config-reload = false\n"); stream:close()
local expected, stage, started = "", 0, nil
local function received()
  local file = assert(io.open(capture, "rb")); local value = file:read("*a"); file:close(); return value
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
  await(application, window, timeout)
  local state, now = Terminal.state(live), window:time()
  started = started or now
  assert(now - started < 25, "primary smoke timed out at stage " .. stage .. ", status=" .. primary.status)
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
    local closing = Primary.new(other)
    primary = closing -- restored below; constructor interception is intentional
    assert(closing:button({ kind = "button", button = 2, action = "press" }, state, true))
    closing:destroy(); other:destroy()
    assert(require("kiwi.platform.primary_read").retired_count() == 1)
    stage = 6
  elseif stage == 6 and require("kiwi.platform.primary_read").retired_count() == 0 then
    assert(received() == expected)
    stage = 7; window:request_close()
  end
end
arg = { "--config", config, "--no-restore-layout", "--no-extensions", "--", "python3", "src/tests/fixtures/primary_input_child.py", capture }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
if probe then probe:destroy() end
Terminal.new, Primary.new, Font.new, Host.await_events = terminal_new, primary_new, font_new, await
os.remove(capture); os.remove(config)
assert(ok, message); assert(stage == 7)
print("Primary selection host smoke passed: Unicode publication, clipboard isolation, bracketed middle paste, native button mapping, mouse capture/Shift override, replacement and focus cancellation.")
