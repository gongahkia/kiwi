local Build = require("kiwi.build")
local Demo = require("kiwi.app.demo")
local GLFWHost = require("kiwi.app.glfw_host")
local HostController = require("kiwi.app.host_controller")
local LayoutStore = require("kiwi.session.layout_store")
local LiveWindowManager = require("kiwi.app.window_manager")
local Replay = require("kiwi.terminal.replay")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local function parse_options()
  local options = {
    demo = os.getenv("KIWI_DEMO") == "1",
    layout_persistence = os.getenv("KIWI_LAYOUT_PERSISTENCE") ~= "0",
    layout_restore = os.getenv("KIWI_LAYOUT_RESTORE") ~= "0",
    release_mode = Build.info().release_mode,
  }
  local index = 1
  while index <= #arg do
    local value = arg[index]
    if value == "--demo" then
      options.demo = true
    elseif value == "--version" then
      options.version = true
    elseif value == "--no-extensions" then
      options.no_extensions = true
    elseif value == "--workspace-smoke" then
      options.workspace_smoke = true
    elseif value == "--multi-window-smoke" then
      options.multi_window_smoke = true
    elseif value == "--session-move-smoke" then
      options.session_move_smoke = true
    elseif value == "--no-restore-layout" then
      options.layout_persistence = false
      options.layout_restore = false
    elseif value == "--config" then
      index = index + 1
      options.config = assert(arg[index], "--config needs a path")
    elseif value == "--record" then
      index = index + 1
      options.record = assert(arg[index], "--record needs a JSONL path")
    elseif value == "--replay" then
      index = index + 1
      options.replay = assert(arg[index], "--replay needs a JSONL path")
    elseif value == "--inspect" then
      options.inspect = {}
    elseif value:sub(1, 10) == "--inspect=" then
      local row, column = value:match("^%-%-inspect=(%d+),(%d+)$")
      if not row then error("--inspect expects zero-based ROW,COLUMN") end
      options.inspect = { row = tonumber(row), column = tonumber(column) }
    elseif value == "--" then
      options.command = {}
      for command_index = index + 1, #arg do
        options.command[#options.command + 1] = arg[command_index]
      end
      break
    else
      error("unknown option: " .. value .. "; use --version, --demo, --config PATH, --no-extensions, --workspace-smoke, --multi-window-smoke, --session-move-smoke, --no-restore-layout, --inspect[=ROW,COLUMN], or -- <command> [args...]")
    end
    index = index + 1
  end
  if options.record or options.multi_window_smoke or options.session_move_smoke then
    options.layout_persistence = false
    options.layout_restore = false
  end
  if options.workspace_smoke and os.getenv("KIWI_LAYOUT_PERSISTENCE") == nil then options.layout_persistence = false end
  if options.workspace_smoke and os.getenv("KIWI_LAYOUT_RESTORE") == nil then options.layout_restore = false end
  return options
end

local function run_replay(path)
  local state = State.new(80, 24)
  local stats = Replay.apply_file(state, path)
  io.stdout:write(Snapshot.encode(state), "\n")
  io.stderr:write(string.format("Kiwi replay: bytes=%d actions=%d errors=%d\n", stats.bytes, stats.actions, stats.errors))
end

local options = parse_options()
if options.version then
  io.stdout:write(Build.format(Build.info()), "\n")
elseif options.release_mode and options.demo then
  error("--demo is unavailable in release mode")
elseif options.replay then
  run_replay(options.replay)
elseif options.demo then
  Demo.run()
else
  LiveWindowManager.new(function(controller_options)
    return GLFWHost.run(controller_options, "Kiwi M2 terminal", HostController.run)
  end, options, {
    layout_path = os.getenv("KIWI_LAYOUT_PATH") or LayoutStore.path(),
    layout_store = LayoutStore,
  }):run()
end
