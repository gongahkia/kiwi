local Options = {}

Options.help = [=[Usage: kiwi [options] [-- command [args...]]

Kiwi is an experimental GPU-accelerated terminal for Linux and macOS.
Without a command, Kiwi starts your default shell.

  -h, --help                  Show this help without opening a window
  --version                   Show version and build information
  --config PATH               Read a configuration file
  --working-directory PATH    Start in an absolute directory
  --theme NAME                Select a built-in theme
  --theme-file PATH           Load a colour-only theme file
  --appearance MODE           system, dark, or light
  --font-family NAME          Select the primary font family
  --font-size SIZE            Set font size (integer, 1–256)
  --scrollback-limit ROWS     Set retained history size
  --scrollbar POLICY          always or never
  --shell-integration MODE    auto or none
  --no-restore-layout         Start fresh without saving or restoring layout
  --no-extensions             Disable trusted local renderer extensions
  --record PATH               Record this terminal session for replay
  --replay PATH               Replay a recording without a window

Examples:
  kiwi --theme dracula --font-size 18
  kiwi --working-directory /path/to/project -- /bin/zsh -l

Configuration and shortcuts: docs/USER_GUIDE.md
]=]

local configuration_options = {
  ["--appearance"] = "appearance",
  ["--font-family"] = "font-family",
  ["--font-size"] = "font-size",
  ["--scrollback-limit"] = "scrollback-limit",
  ["--scrollbar"] = "scrollbar",
  ["--shell-integration"] = "shell-integration",
  ["--theme"] = "theme",
  ["--theme-file"] = "theme-file",
}

local function option_value(arguments, index, option)
  local value = arguments[index + 1]
  if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then
    error(option .. " needs a non-empty NUL-free value")
  end
  for byte_index = 1, #value do
    local byte = value:byte(byte_index)
    if byte < 0x20 or byte == 0x7f then error(option .. " cannot contain control bytes") end
  end
  return value
end

function Options.parse(arguments, environment, release_mode)
  assert(type(arguments) == "table", "application arguments must be a table")
  environment = environment or os.getenv
  local options = {
    configuration_overrides = {},
    demo = environment("KIWI_DEMO") == "1",
    layout_persistence = environment("KIWI_LAYOUT_PERSISTENCE") ~= "0",
    layout_restore = environment("KIWI_LAYOUT_RESTORE") ~= "0",
    release_mode = release_mode == true,
  }
  local index = 1
  while index <= #arguments do
    local value = arguments[index]
    local configuration_key = configuration_options[value]
    if configuration_key ~= nil then
      options.configuration_overrides[#options.configuration_overrides + 1] = {
        key = configuration_key,
        value = option_value(arguments, index, value),
      }
      index = index + 1
    elseif value == "--demo" then
      options.demo = true
    elseif value == "--version" then
      options.version = true
    elseif value == "--help" or value == "-h" then
      options.help = true
    elseif value == "--working-directory" then
      options.initial_cwd = option_value(arguments, index, value)
      assert(options.initial_cwd:sub(1, 1) == "/" and #options.initial_cwd <= 2048, "--working-directory needs an absolute path of at most 2048 bytes")
      index = index + 1
    elseif value == "--no-extensions" then
      options.no_extensions = true
    elseif value == "--workspace-smoke" then
      options.workspace_smoke = true
    elseif value == "--interaction-smoke" then
      options.interaction_smoke = true
    elseif value == "--menu-smoke" then
      options.menu_smoke = true
    elseif value == "--toolbar-smoke" then
      options.toolbar_smoke = true
    elseif value == "--cwd-smoke" then
      options.cwd_smoke = true
    elseif value == "--palette-smoke" then
      options.palette_smoke = true
    elseif value == "--automation-smoke" then
      options.automation_smoke = true
    elseif value == "--key-sequence-smoke" then
      options.key_sequence_smoke = true
    elseif value == "--multi-window-smoke" then
      options.multi_window_smoke = true
    elseif value == "--session-move-smoke" then
      options.session_move_smoke = true
    elseif value == "--no-restore-layout" then
      options.layout_persistence = false
      options.layout_restore = false
    elseif value == "--config" then
      options.config = option_value(arguments, index, value)
      index = index + 1
    elseif value == "--record" then
      options.record = option_value(arguments, index, value)
      index = index + 1
    elseif value == "--replay" then
      options.replay = option_value(arguments, index, value)
      index = index + 1
    elseif value == "--inspect" then
      options.inspect = {}
    elseif value:sub(1, 10) == "--inspect=" then
      local row, column = value:match("^%-%-inspect=(%d+),(%d+)$")
      if not row then error("--inspect expects zero-based ROW,COLUMN") end
      options.inspect = { row = tonumber(row), column = tonumber(column) }
    elseif value == "--" then
      options.command = {}
      for command_index = index + 1, #arguments do
        options.command[#options.command + 1] = arguments[command_index]
      end
      assert(#options.command > 0 and options.command[1] ~= "", "-- needs a command")
      for _, argument in ipairs(options.command) do
        assert(type(argument) == "string" and not argument:find("\0", 1, true), "command arguments must be NUL-free strings")
      end
      break
    else
      error("unknown option: " .. value .. "; use --help")
    end
    index = index + 1
  end
  -- An explicit launch intent must never silently restore unrelated shells.
  if options.command or options.initial_cwd then
    options.layout_restore = false
    options.layout_persistence = false
  end
  if options.record or options.multi_window_smoke or options.session_move_smoke or options.interaction_smoke then
    options.layout_persistence = false
    options.layout_restore = false
  end
  if (options.workspace_smoke or options.menu_smoke or options.toolbar_smoke or options.cwd_smoke or options.palette_smoke or options.automation_smoke or options.key_sequence_smoke) and environment("KIWI_LAYOUT_PERSISTENCE") == nil then options.layout_persistence = false end
  if (options.workspace_smoke or options.menu_smoke or options.toolbar_smoke or options.cwd_smoke or options.palette_smoke or options.automation_smoke or options.key_sequence_smoke) and environment("KIWI_LAYOUT_RESTORE") == nil then options.layout_restore = false end
  return options
end

return Options
