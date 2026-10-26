-- Exercise real GTK GL resources and both controller routes in an isolated
-- test process. The driver owns its temporary config, PTYs and native pages.
local Runtime = require("kiwi.app.configuration_runtime")
local Consumer = require("kiwi.renderer.gtk_gl_consumer")
local Dispatcher = require("kiwi.app.product_action_dispatcher")
local Host = require("kiwi.app.gtk_host")
local Session = require("kiwi.app.gtk_gl_session")
local Terminal = require("kiwi.session.terminal")
local Pty = require("kiwi.process.pty")
local Color = require("kiwi.terminal.color")
assert(Host.presentation_backend == "gtk-gl", "fixture requires KIWI_GTK_PRESENTER=gl")
local tabs = os.getenv("KIWI_GTK_NATIVE_TABS") == "1"
local expected_pages = tabs and 2 or 1
local path = os.tmpname()
local function save(text)
  local file = assert(io.open(path .. ".new", "wb")); file:write(text); file:close()
  assert(os.rename(path .. ".new", path))
end
save("theme = kiwi\nfont-size = 16\nbackground = #000000\n")
local runtime, dispatcher
local terminals, ptys, pages, states = {}, {}, {}, {}
local originals = { runtime = Runtime.new, consumer = Consumer.new, dispatcher = Dispatcher.new,
  terminal = Terminal.new, pty = Pty.spawn, session = Session.new, await = Host.await_events }
Runtime.new = function(...) runtime = originals.runtime(...); return runtime end
Dispatcher.new = function(...) dispatcher = originals.dispatcher(...); return dispatcher end
Terminal.new = function(...)
  local terminal = originals.terminal(...); terminals[#terminals + 1] = terminal; return terminal
end
Pty.spawn = function(...)
  local pty = originals.pty(...); ptys[#ptys + 1] = pty; return pty
end
Session.new = function(...)
  local session = originals.session(...); pages[#pages + 1] = session.window; return session
end
local fail_consumer, constructor_calls = false, 0
Consumer.new = function(...)
  if fail_consumer then
    constructor_calls = constructor_calls + 1
    if constructor_calls == expected_pages then error("injected GTK page consumer failure") end
  end
  return originals.consumer(...)
end
local function backgrounds(hex)
  if #terminals ~= expected_pages then return false end
  local color = Color.pack(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), 255)
  for _, terminal in ipairs(terminals) do
    if Terminal.state(terminal).colors.background ~= color then return false end
  end
  return true
end
local function ready()
  for _, terminal in ipairs(terminals) do
    local state = Terminal.state(terminal)
    if state.title ~= "gtk-reload-ready" or state.scrollback:size() < 100 then return false end
  end
  return #terminals > 0
end
local function retained_child_output(index)
  for _, row in ipairs(Terminal.state(terminals[index]):selection_rows("primary")) do
    local text = {}
    for column = 0, Terminal.state(terminals[index]).columns - 1 do text[#text + 1] = row.row.cells[column].glyph end
    if table.concat(text):find("PTY-survives:page-" .. index, 1, true) then return true end
  end
  return false
end
local started, stage, stage_started, readback_page = nil, 0, 0, 1
local function advance(now) stage = stage + 1; stage_started = now end
Host.await_events = function(application, window, timeout)
  local now = window:time()
  started = started or now
  assert(now - started < 25, "GTK configuration fixture timed out at stage " .. stage)
  local failed = runtime.status.error
  if stage == 0 and ready() then
    if tabs then assert(dispatcher:handle("new-tab")) else pages[1] = runtime.window end
    advance(now)
  elseif stage == 1 and #terminals == expected_pages and ready() then
    assert(backgrounds("000000"))
    for i, terminal in ipairs(terminals) do states[i] = Terminal.state(terminal); states[i]:scroll_history(8) end
    save("font-size = 999\n")
    advance(now)
  elseif stage == 2 and failed then
    assert(backgrounds("000000"), "invalid source changed a live page")
    save("font-size = 18\nbackground = #123456\n")
    advance(now)
  elseif stage == 3 and backgrounds("123456") and not failed then
    for i, terminal in ipairs(terminals) do
      assert(Terminal.state(terminal) == states[i], "reload replaced terminal state identity")
      assert(states[i].scrollback:size() > 100, "reload discarded history")
    end
    fail_consumer, constructor_calls = true, 0
    save("font-size = 20\nbackground = #654321\n")
    advance(now)
  elseif stage == 4 and failed then
    assert(failed:find("injected GTK page consumer failure", 1, true), failed)
    assert(constructor_calls == expected_pages)
    assert(backgrounds("123456"), "failed later page partially changed the palette")
    fail_consumer = false
    save("font-size = 20\nbackground = #654321\n")
    advance(now)
  elseif stage == 5 and backgrounds("654321") and not failed then
    save("font-size = 20\nbackground = #654321\nlive-config-reload = false\n")
    advance(now)
  elseif stage == 6 and not runtime.configuration.live_config_reload then
    save("font-size = 20\nbackground = #abcdef\n")
    advance(now)
  elseif stage == 7 and now - stage_started > 0.6 then
    assert(backgrounds("654321"), "disabled watcher applied a save")
    local page = pages[#pages]
    page.on_key(Host.keymap.key_f6, Host.keymap.press, 0)
    page.on_key(Host.keymap.key_f6, Host.keymap.release, 0)
    advance(now)
  elseif stage == 8 and backgrounds("abcdef") and not failed then
    assert(runtime.configuration.live_config_reload)
    for index, pty in ipairs(ptys) do
      assert(not pty.exited and pty.fd ~= nil, "reload replaced or stopped the child")
      pty:enqueue("page-" .. index .. "\n"); pty:flush()
    end
    advance(now)
  elseif stage == 9 then
    local retained = true
    for index = 1, expected_pages do retained = retained and retained_child_output(index) end
    if retained then
      if tabs then assert(pages[readback_page]:select_native_tab()) end
      advance(now)
    end
  elseif stage == 10 then
    local page = pages[readback_page]
    local count, reason = page:gl_area_count_rgb(0xab, 0xcd, 0xef, 4)
    if count then
      assert(count > 100, "reloaded palette did not reach the native framebuffer")
      readback_page = readback_page + 1
      if readback_page > expected_pages then advance(now); window:request_close()
      else assert(pages[readback_page]:select_native_tab()) end
    else assert(reason == "pending", reason) end
  end
  -- Test-only inspection/readback scheduling; native idle readiness has its
  -- own independent indefinite-wait regression gate.
  originals.await(application, window, math.min(timeout, 0.01))
end
arg = { "--config", path, "--no-restore-layout", "--no-extensions", "--", "/bin/sh", "-c",
  "i=0; while [ $i -lt 200 ]; do printf 'retained %03d\\r\\n' $i; i=$((i+1)); done; printf '\\033]2;gtk-reload-ready\\007'; IFS= read -r value; printf 'PTY-survives:%s\\r\\n' \"$value\"; sleep 30" }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Runtime.new, Consumer.new, Dispatcher.new = originals.runtime, originals.consumer, originals.dispatcher
Terminal.new, Pty.spawn, Session.new, Host.await_events = originals.terminal, originals.pty, originals.session, originals.await
os.remove(path); os.remove(path .. ".new")
assert(ok, message)
assert(stage == 11, "GTK configuration fixture ended at stage " .. stage)
print(string.format("GTK GL configuration reload passed: %d page(s), automatic/manual reload, opt-out, invalid-source/resource rollback, retained state/history/PTY and native palette readback.", expected_pages))
