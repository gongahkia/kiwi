-- Observe production input handling. All keys and composition come from the
-- external virtual keyboard and the real IBus engine, not injected callbacks.
assert(os.getenv("KIWI_IME_SMOKE_ISOLATED") == "1", "IME smoke needs a private desktop and input-method service")
local Host = require("kiwi.app.gtk_host")
local Terminal = require("kiwi.session.terminal")
local Json = require("kiwi.bench.json")
local Window = require("kiwi.platform.gtk_window")
local handlers = Window.set_input_handlers
local keys = {}
Window.set_input_handlers = function(window, text, key, ...)
  return handlers(window, text, function(value, action, modifiers, ...)
    assert(#keys < 256, "key observation limit exceeded")
    keys[#keys + 1] = { key = value, action = action, modifiers = modifiers }
    return key(value, action, modifiers, ...)
  end, ...)
end
local root = assert(os.getenv("KIWI_IME_SMOKE_DIRECTORY"))
local terminal_new, enable, await = Terminal.new, Host.enable_text_input, Host.await_events
local live, started
local preedits, commits = {}, {}
Terminal.new = function(...) live = terminal_new(...); return live end
Host.enable_text_input = function(window, preedit, commit)
  return enable(window, function(text, ...)
    assert(#preedits < 256, "preedit observation limit exceeded")
    preedits[#preedits + 1] = text
    return preedit(text, ...)
  end, function(text, ...)
    assert(#commits < 128, "commit observation limit exceeded")
    commits[#commits + 1] = text
    return commit(text, ...)
  end)
end
Host.await_events = function(application, window, timeout)
  await(application, window, math.min(timeout, 0.01))
  local now = window:time()
  started = started or now
  assert(now - started < 45, "IME fixture exceeded its deadline")
  local state = Terminal.state(live)
  local file = io.open(root .. "/command", "r")
  if file then
    local command = file:read("*a"); file:close(); os.remove(root .. "/command")
    if command == "quit" then window:request_close()
    elseif command == "kitty" then live:write("\27[>31u")
    elseif command == "legacy" then live:write("\27[<u")
    else error("unknown IME fixture command") end
  end
  local line = {}
  for column = 0, math.min(20, state.columns - 1) do line[#line + 1] = state:get(column, 0).glyph end
  local snapshot = { title = state.title, preedit = state.ime_preedit and state.ime_preedit.text or "",
    preedits = preedits, commits = commits, query = state.search.query, editing = state.search.editing,
    row = table.concat(line), flags = state.modes.keyboard_flags, keys = keys }
  file = assert(io.open(root .. "/snapshot.new", "w"))
  assert(file:write(Json.encode(snapshot))); assert(file:close())
  assert(os.rename(root .. "/snapshot.new", root .. "/snapshot.json"))
end
local file = assert(io.open(root .. "/config", "w"))
file:write("live-config-reload = false\n"); file:close()
arg = { "--config", root .. "/config", "--no-restore-layout", "--no-extensions", "--", "python3",
  "src/tests/fixtures/ime_input_child.py", root .. "/input" }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Terminal.new, Host.enable_text_input, Host.await_events = terminal_new, enable, await
Window.set_input_handlers = handlers
assert(ok, message)
