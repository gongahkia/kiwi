-- A real host/controller/PTY/GPU run. Instrument only the test process to save
-- its own temporary files and observe the application's state/title boundary.
local Config = require("kiwi.config")
local Color = require("kiwi.terminal.color")
local Dispatcher = require("kiwi.app.product_action_dispatcher")
local Terminal = require("kiwi.session.terminal")
local gtk = os.getenv("KIWI_HOST") == "gtk"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
local Window = require(gtk and "kiwi.platform.gtk_window" or "kiwi.platform.window")
assert(Host.presentation_backend ~= "gtk-gl", "configuration smoke requires the WGPU application path")

local Context = require("kiwi.gpu.context")
local context_new, context, working_effect = Context.new
Context.new = function(...) context = context_new(...); return context end
local path, theme, shader = os.tmpname(), os.tmpname(), os.tmpname()
local identity = require("kiwi.renderer.postprocess").identity
os.remove(theme)
local function save(target, text)
  local temporary = target .. ".new"
  local file = assert(io.open(temporary, "wb")); assert(file:write(text)); assert(file:close())
  assert(os.rename(temporary, target))
end
save(path, "background = #000000\n")
local live, dispatcher, title, loaded
local terminal_new, dispatcher_new, set_title, load, await = Terminal.new, Dispatcher.new, Window.set_title, Config.load, Host.await_events
Terminal.new = function(...) local value = terminal_new(...); live = value; return value end
Dispatcher.new = function(...) local value = dispatcher_new(...); dispatcher = value; return value end
Window.set_title = function(self, value) title = value; return set_title(self, value) end
Config.load = function(...) local value, source = load(...); loaded = value; return value, source end
local started, stage, stage_started = nil, 0, 0
local function background(hex)
  local state = Terminal.state(live)
  local expected = Color.pack(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), 255)
  if state.colors.background ~= expected then return false end
  assert(state:visible_row(0).cells[0].bg == expected, "visible history retained stale palette colours")
  return true
end
local function next_stage(now) stage = stage + 1; stage_started = now end
Host.await_events = function(application, window, timeout)
  await(application, window, timeout)
  local now = window:time()
  started = started or now
  assert(now - started < 30, "configuration reload smoke timed out at stage " .. stage)
  local failed = title and title:find("Configuration error:", 1, true)
  if stage == 0 and now - started > 0.5 then
    assert(background("000000"))
    local state = Terminal.state(live)
    assert(state.scrollback:size() > 8, "reload fixture did not create scrollback")
    state:scroll_history(8)
    save(path, "font-size = 999\n")
    next_stage(now)
  elseif stage == 1 and failed then
    assert(background("000000"), "invalid save changed the live palette")
    save(path, "background = #12ab34\nfont-size = 18\n")
    next_stage(now)
  elseif stage == 2 and background("12ab34") and not failed then
    save(path, "theme-file = " .. theme .. "\n")
    next_stage(now)
  elseif stage == 3 and failed then
    assert(background("12ab34"))
    save(theme, "background = #123456\nforeground = #ffffff\n")
    next_stage(now)
  elseif stage == 4 and background("123456") and not failed then
    save(theme, "background = #654321\nforeground = #ffffff\n")
    next_stage(now)
  elseif stage == 5 and background("654321") then
    save(path, "background = #112233\nlive-config-reload = false\n")
    next_stage(now)
  elseif stage == 6 and background("112233") then
    assert(loaded.live_config_reload == false)
    save(path, "background = #ab1234\n")
    next_stage(now)
  elseif stage == 7 and now - stage_started > 0.6 then
    assert(background("112233"), "disabled watcher applied a save")
    assert(dispatcher:handle("reload-config"))
    next_stage(now)
  elseif stage == 8 and background("ab1234") and not failed then
    local state = Terminal.state(live)
    local retained = false
    for _, row in ipairs(state:selection_rows("primary")) do
      local text = {}
      for column = 0, state.columns - 1 do text[#text + 1] = row.row.cells[column].glyph end
      if table.concat(text):find("PTY-survives-reload", 1, true) then retained = true end
    end
    assert(retained, "reload lost the child output from both viewport and scrollback")
    assert(Terminal.parser(live).stats.errors == 0)
    save(shader, identity)
    save(path, "background = #ab1234\ncustom-shader = " .. shader .. "\nbackground-opacity = " .. (context.transparency_supported and "0.5" or "1") .. "\n")
    next_stage(now)
  elseif stage == 9 and context.effect and not failed then
    working_effect = context.effect
    save(shader, "invalid WGSL")
    save(path, "background = #ff0000\ncustom-shader = " .. shader .. "\n")
    next_stage(now)
  elseif stage == 10 and failed then
    assert(background("ab1234"), "invalid shader partially committed the new palette")
    assert(context.effect == working_effect, "invalid shader replaced the working effect")
    save(shader, identity .. "\n// repaired")
    next_stage(now)
  elseif stage == 11 and background("ff0000") and not failed then
    assert(context.effect ~= working_effect, "shader file edit did not replace the effect")
    working_effect = context.effect
    os.remove(shader)
    next_stage(now)
  elseif stage == 12 and failed then
    assert(context.effect == working_effect, "missing shader discarded the working effect")
    save(shader, identity)
    next_stage(now)
  elseif stage == 13 and context.effect ~= working_effect and not failed then
    save(path, "background = #ab1234\n")
    next_stage(now)
  elseif stage == 14 and background("ab1234") and not failed then
    assert(context.effect == nil, "removing custom-shader retained the effect")
    next_stage(now)
    window:request_close()
  end
end
arg = { "--config", path, "--no-restore-layout", "--no-extensions", "--", "/bin/sh", "-c",
  "printf 'PTY-survives-reload\\r\\n'; i=0; while [ $i -lt 200 ]; do printf 'retained history %03d\\r\\n' $i; i=$((i + 1)); done; sleep 30" }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Terminal.new, Dispatcher.new, Window.set_title, Config.load, Host.await_events = terminal_new, dispatcher_new, set_title, load, await
Context.new = context_new
os.remove(shader); os.remove(shader .. ".new")
os.remove(path); os.remove(theme); os.remove(path .. ".new"); os.remove(theme .. ".new")
assert(ok, message)
assert(stage == 15, "configuration reload smoke ended before all stages completed")
print("Configuration reload smoke passed: atomic saves, visible errors, missing-theme recovery, theme edits, opt-out, manual retry, recoloured visible PTY history, opacity, shader file edits, invalid/missing shader rollback and recovery.")
