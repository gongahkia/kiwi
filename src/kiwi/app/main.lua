local Build = require("kiwi.build")
local Demo = require("kiwi.app.demo")
local HostController = require("kiwi.app.host_controller")
local LayoutStore = require("kiwi.session.layout_store")
local LiveWindowManager = require("kiwi.app.window_manager")
local Options = require("kiwi.app.options")
local Replay = require("kiwi.terminal.replay")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local function run_replay(path)
  local state = State.new(80, 24)
  local stats = Replay.apply_file(state, path)
  io.stdout:write(Snapshot.encode(state), "\n")
  io.stderr:write(string.format("Kiwi replay: bytes=%d actions=%d errors=%d\n", stats.bytes, stats.actions, stats.errors))
end

local options = Options.parse(arg, os.getenv, Build.info().release_mode)
if options.version then
  io.stdout:write(Build.format(Build.info()), "\n")
elseif options.release_mode and options.demo then
  error("--demo is unavailable in release mode")
elseif options.replay then
  run_replay(options.replay)
elseif options.demo then
  Demo.run()
else
  local requested_host = os.getenv("KIWI_HOST") or "glfw"
  local Host
  if requested_host == "glfw" then
    Host = require("kiwi.app.glfw_host")
  elseif requested_host == "gtk" then
    Host = require("kiwi.app.gtk_host")
  else
    error("KIWI_HOST must be glfw or gtk")
  end
  if Host.presentation_backend == "gtk-gl" then
    -- The experimental GtkGLArea path is one terminal surface. It must not
    -- restore or overwrite the multi-pane WGPU workspace snapshot.
    options.layout_persistence = false
    options.layout_restore = false
  end
  LiveWindowManager.new(function(controller_options)
    return Host.run(controller_options, "Kiwi M2 terminal", HostController.run)
  end, options, {
    layout_path = os.getenv("KIWI_LAYOUT_PATH") or LayoutStore.path(),
    layout_store = LayoutStore,
    window_api = Host.window_api,
  }):run()
end
