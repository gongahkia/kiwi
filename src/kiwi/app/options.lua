local Options = {}

local configuration_options = {
  ["--appearance"] = "appearance",
  ["--font-family"] = "font-family",
  ["--font-size"] = "font-size",
  ["--scrollback-limit"] = "scrollback-limit",
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

local function option_summary()
  return "--version, --demo, --config PATH, --theme NAME, --theme-file PATH, --appearance system|dark|light, --font-family NAME, --font-size POINTS, --scrollback-limit ROWS, --shell-integration auto|none, --no-extensions, --workspace-smoke, --menu-smoke, --palette-smoke, --key-sequence-smoke, --multi-window-smoke, --session-move-smoke, --no-restore-layout, --inspect[=ROW,COLUMN], or -- <command> [args...]"
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
    elseif value == "--no-extensions" then
      options.no_extensions = true
    elseif value == "--workspace-smoke" then
      options.workspace_smoke = true
    elseif value == "--menu-smoke" then
      options.menu_smoke = true
    elseif value == "--palette-smoke" then
      options.palette_smoke = true
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
      break
    else
      error("unknown option: " .. value .. "; use " .. option_summary())
    end
    index = index + 1
  end
  if options.record or options.multi_window_smoke or options.session_move_smoke then
    options.layout_persistence = false
    options.layout_restore = false
  end
  if (options.workspace_smoke or options.menu_smoke or options.palette_smoke or options.key_sequence_smoke) and environment("KIWI_LAYOUT_PERSISTENCE") == nil then options.layout_persistence = false end
  if (options.workspace_smoke or options.menu_smoke or options.palette_smoke or options.key_sequence_smoke) and environment("KIWI_LAYOUT_RESTORE") == nil then options.layout_restore = false end
  return options
end

return Options
