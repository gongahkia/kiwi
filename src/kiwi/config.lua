local Color = require("kiwi.renderer.color")
local Actions = require("kiwi.app.actions")

local Config = {}

Config.maximum_bytes = 64 * 1024
Config.maximum_lines = 512
Config.maximum_theme_bytes = 32 * 1024
Config.maximum_theme_lines = 256

Config.edit_template = [[# Kiwi configuration
#
# This file is read on launch and by Reload Configuration (F6). Uncomment and
# adjust only the settings you want to override. See docs/USER_GUIDE.md for the
# complete, bounded configuration surface.
#
# theme = kiwi
# font-family = "monospace"
# font-size = 20
# ligatures = false
# contextual-alternates = false
# scrollback-limit = 2000
# scrollbar = always
# mouse-shift-capture = false
# osc52-read = deny
# osc52-write = false
# shell-integration = auto
# macos-applescript = true
# notify-on-command-finish = never
# notify-on-command-finish-after = 5
# keybind = ctrl+shift+t = new-tab
]]

local command_line_keys = {
  ["appearance"] = true,
  ["font-family"] = true,
  ["font-size"] = true,
  ["scrollback-limit"] = true,
  ["scrollbar"] = true,
  ["shell-integration"] = true,
  ["theme"] = true,
  ["theme-file"] = true,
}

local themes = {
  kiwi = {
    foreground = "#d8dee9",
    background = "#20242b",
  },
  nord = {
    foreground = "#d8dee9",
    background = "#2e3440",
    palette = {
      [0] = "#3b4252", [1] = "#bf616a", [2] = "#a3be8c", [3] = "#ebcb8b",
      [4] = "#81a1c1", [5] = "#b48ead", [6] = "#88c0d0", [7] = "#e5e9f0",
      [8] = "#4c566a", [9] = "#bf616a", [10] = "#a3be8c", [11] = "#ebcb8b",
      [12] = "#81a1c1", [13] = "#b48ead", [14] = "#8fbcbb", [15] = "#eceff4",
    },
  },
  light = {
    foreground = "#2e3440",
    background = "#eceff4",
  },
  dracula = {
    foreground = "#f8f8f2",
    background = "#282a36",
    palette = {
      [0] = "#21222c", [1] = "#ff5555", [2] = "#50fa7b", [3] = "#f1fa8c",
      [4] = "#bd93f9", [5] = "#ff79c6", [6] = "#8be9fd", [7] = "#f8f8f2",
      [8] = "#6272a4", [9] = "#ff6e6e", [10] = "#69ff94", [11] = "#ffffa5",
      [12] = "#d6acff", [13] = "#ff92df", [14] = "#a4ffff", [15] = "#ffffff",
    },
  },
  ["gruvbox-dark"] = {
    foreground = "#ebdbb2",
    background = "#282828",
    palette = {
      [0] = "#282828", [1] = "#cc241d", [2] = "#98971a", [3] = "#d79921",
      [4] = "#458588", [5] = "#b16286", [6] = "#689d6a", [7] = "#a89984",
      [8] = "#928374", [9] = "#fb4934", [10] = "#b8bb26", [11] = "#fabd2f",
      [12] = "#83a598", [13] = "#d3869b", [14] = "#8ec07c", [15] = "#ebdbb2",
    },
  },
  ["solarized-dark"] = {
    foreground = "#839496",
    background = "#002b36",
    palette = {
      [0] = "#073642", [1] = "#dc322f", [2] = "#859900", [3] = "#b58900",
      [4] = "#268bd2", [5] = "#d33682", [6] = "#2aa198", [7] = "#eee8d5",
      [8] = "#002b36", [9] = "#cb4b16", [10] = "#586e75", [11] = "#657b83",
      [12] = "#839496", [13] = "#6c71c4", [14] = "#93a1a1", [15] = "#fdf6e3",
    },
  },
  ["solarized-light"] = {
    foreground = "#657b83",
    background = "#fdf6e3",
    palette = {
      [0] = "#073642", [1] = "#dc322f", [2] = "#859900", [3] = "#b58900",
      [4] = "#268bd2", [5] = "#d33682", [6] = "#2aa198", [7] = "#eee8d5",
      [8] = "#002b36", [9] = "#cb4b16", [10] = "#586e75", [11] = "#657b83",
      [12] = "#839496", [13] = "#6c71c4", [14] = "#93a1a1", [15] = "#fdf6e3",
    },
  },
  ["tokyo-night"] = {
    foreground = "#c0caf5",
    background = "#1a1b26",
    palette = {
      [0] = "#15161e", [1] = "#f7768e", [2] = "#9ece6a", [3] = "#e0af68",
      [4] = "#7aa2f7", [5] = "#bb9af7", [6] = "#7dcfff", [7] = "#a9b1d6",
      [8] = "#414868", [9] = "#ff899d", [10] = "#9fe044", [11] = "#faba4a",
      [12] = "#8db0ff", [13] = "#c7a9ff", [14] = "#a4daff", [15] = "#c0caf5",
    },
  },
  ["catppuccin-mocha"] = {
    foreground = "#cdd6f4",
    background = "#1e1e2e",
    palette = {
      [0] = "#45475a", [1] = "#f38ba8", [2] = "#a6e3a1", [3] = "#f9e2af",
      [4] = "#89b4fa", [5] = "#f5c2e7", [6] = "#94e2d5", [7] = "#bac2de",
      [8] = "#585b70", [9] = "#f38ba8", [10] = "#a6e3a1", [11] = "#f9e2af",
      [12] = "#89b4fa", [13] = "#f5c2e7", [14] = "#94e2d5", [15] = "#a6adc8",
    },
  },
}

local function copy_table(source)
  local copy = {}
  for key, value in pairs(source) do
    if type(value) == "table" then
      copy[key] = copy_table(value)
    else
      copy[key] = value
    end
  end
  return copy
end

local function trim(value)
  return value:match("^%s*(.-)%s*$")
end

local function parse_string(value, line)
  value = trim(value)
  if value:sub(1, 1) ~= '"' then
    if value == "" then error("configuration line " .. line .. " has an empty value") end
    return value
  end
  if value:sub(-1) ~= '"' or #value < 2 then error("configuration line " .. line .. " has an unterminated string") end
  local output = {}
  local index = 2
  while index < #value do
    local byte = value:sub(index, index)
    if byte == "\\" then
      index = index + 1
      local escaped = value:sub(index, index)
      if escaped == '"' or escaped == "\\" then
        output[#output + 1] = escaped
      elseif escaped == "n" then
        output[#output + 1] = "\n"
      else
        error("configuration line " .. line .. " has an unsupported string escape")
      end
    else
      output[#output + 1] = byte
    end
    index = index + 1
  end
  return table.concat(output)
end

local function parse_boolean(value, line)
  value = parse_string(value, line)
  if value == "true" then return true end
  if value == "false" then return false end
  error("configuration line " .. line .. " must use true or false")
end

local function parse_integer(value, line, minimum, maximum)
  local number = tonumber(parse_string(value, line))
  if number == nil or number % 1 ~= 0 or number < minimum or (maximum and number > maximum) then
    error("configuration line " .. line .. " has an out-of-range integer")
  end
  return number
end

function Config.parse_color(value, line)
  value = parse_string(value, line or "?")
  local red, green, blue = value:match("^#([%x][%x])([%x][%x])([%x][%x])$")
  if red == nil then error("configuration line " .. tostring(line or "?") .. " needs a #RRGGBB colour") end
  return Color.pack(tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16), 0xff)
end

local function defaults()
  return {
    theme = "kiwi",
    theme_mode = "named",
    theme_dark = "kiwi",
    theme_light = "light",
    theme_file = nil,
    appearance = "system",
    resolved_appearance = "dark",
    font_family = "monospace",
    font_path = nil,
    font_size = 20,
    ligatures = false,
    contextual_alternates = false,
    scrollback_limit = 2000,
    scrollbar = "always",
    ambiguous_width = 1,
    foreground = nil,
    background = nil,
    palette = {},
    selection_color = nil,
    search_color = nil,
    hyperlink_color = nil,
    command_region_color = nil,
    color_overrides = { palette = {} },
    command_regions = false,
    keybindings = {},
    command_palette_entries = {},
    mouse_shift_capture = false,
    osc52_read = "deny",
    osc52_write = false,
    osc9_notifications = "off",
    osc9_progress = "off",
    notify_on_command_finish = "never",
    notify_on_command_finish_after = 5,
    shell_integration = "auto",
    macos_applescript = true,
  }
end

local function assert_builtin_theme(name, line)
  if themes[name] == nil then error("configuration line " .. line .. " names an unknown theme: " .. name) end
  return name
end

local function parse_appearance(value, line)
  value = parse_string(value, line)
  if value ~= "system" and value ~= "dark" and value ~= "light" then
    error("configuration line " .. line .. " appearance must be system, dark, or light")
  end
  return value
end

local function parse_osc52_read_policy(value, line)
  value = parse_string(value, line)
  if value ~= "allow" and value ~= "deny" then
    error("configuration line " .. line .. " osc52-read must be allow or deny")
  end
  return value
end

local function parse_mouse_shift_capture(value, line)
  value = parse_string(value, line)
  if value == "true" then return true end
  if value == "false" then return false end
  if value == "always" or value == "never" then return value end
  error("configuration line " .. line .. " mouse-shift-capture must be true, false, always, or never")
end

local function parse_scrollbar_policy(value, line)
  value = parse_string(value, line)
  if value ~= "always" and value ~= "never" then
    error("configuration line " .. line .. " scrollbar must be always or never")
  end
  return value
end

function Config.resolve_appearance(preference, system_appearance)
  assert(preference == "system" or preference == "dark" or preference == "light", "appearance preference must be system, dark, or light")
  if preference ~= "system" then return preference end
  return system_appearance == "light" and "light" or "dark"
end

local function empty_color_overrides()
  return { palette = {} }
end

local function apply_color_overrides(config)
  local overrides = config.color_overrides or empty_color_overrides()
  for _, field in ipairs({ "foreground", "background", "selection_color", "search_color", "hyperlink_color", "command_region_color" }) do
    if overrides[field] ~= nil then config[field] = overrides[field] end
  end
  for index, colour in pairs(overrides.palette or {}) do config.palette[index] = colour end
end

local function parse_osc9_policy(value, line)
  value = parse_string(value, line)
  if value ~= "off" and value ~= "system" then
    error("configuration line " .. line .. " OSC 9 policy must be off or system")
  end
  return value
end

local function parse_command_finish_policy(value, line)
  value = parse_string(value, line)
  if value ~= "never" and value ~= "unfocused" and value ~= "always" then
    error("configuration line " .. line .. " notify-on-command-finish must be never, unfocused, or always")
  end
  return value
end

local function apply_theme(config, name, line)
  local theme = themes[assert_builtin_theme(name, line)]
  config.theme = name
  config.foreground = Config.parse_color(theme.foreground, line)
  config.background = Config.parse_color(theme.background, line)
  config.palette = {}
  for index, value in pairs(theme.palette or {}) do config.palette[index] = Config.parse_color(value, line) end
end

local external_theme_keys = {
  ["background"] = true,
  ["command-region-color"] = true,
  ["foreground"] = true,
  ["hyperlink-color"] = true,
  ["search-color"] = true,
  ["selection-color"] = true,
}

function Config.parse_theme(text, source)
  assert(type(text) == "string", "theme text must be a string")
  source = source or "theme"
  if #text > Config.maximum_theme_bytes then error("theme " .. source .. " exceeds " .. Config.maximum_theme_bytes .. " bytes") end
  local theme = { palette = {} }
  local count = 0
  for raw_line in (text .. "\n"):gmatch("(.-)\n") do
    count = count + 1
    if count > Config.maximum_theme_lines then error("theme " .. source .. " exceeds " .. Config.maximum_theme_lines .. " lines") end
    local line = trim(raw_line)
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local key, value = line:match("^([a-z][a-z0-9%-]*)%s*=%s*(.-)%s*$")
      if key == nil then error("theme line " .. count .. " must use key = value") end
      if external_theme_keys[key] then
        local colour = parse_string(value, count)
        Config.parse_color(colour, count)
        theme[key:gsub("%-", "_")] = colour
      else
        local palette_index = key:match("^palette%-(%d+)$")
        if palette_index == nil then error("theme line " .. count .. " has an unsafe key: " .. key) end
        palette_index = tonumber(palette_index)
        if palette_index > 255 then error("theme line " .. count .. " palette index must be 0 through 255") end
        theme.palette[palette_index] = Config.parse_color(value, count)
      end
    end
  end
  if theme.foreground == nil or theme.background == nil then error("theme " .. source .. " needs foreground and background colours") end
  return theme
end

function Config.load_theme(path)
  assert(type(path) == "string" and path:sub(1, 1) == "/" and not path:find("\0", 1, true), "theme-file must be an absolute NUL-free path")
  local handle = io.open(path, "rb")
  if handle == nil then error("could not open theme file: " .. path) end
  local text = handle:read(Config.maximum_theme_bytes + 1)
  handle:close()
  if text == nil then error("could not read theme file: " .. path) end
  return Config.parse_theme(text, path)
end

local function apply_external_theme(config, path, theme)
  config.theme = "external"
  config.theme_mode = "external"
  config.theme_file = path
  config.color_overrides = empty_color_overrides()
  config.foreground = Config.parse_color(theme.foreground, path)
  config.background = Config.parse_color(theme.background, path)
  config.palette = copy_table(theme.palette)
  for _, field in ipairs({ "selection_color", "search_color", "hyperlink_color", "command_region_color" }) do
    if theme[field] ~= nil then config[field] = theme[field] end
  end
end

local function apply_value(config, key, raw, line)
  if key == "font-family" then
    config.font_family = parse_string(raw, line)
  elseif key == "font-path" then
    config.font_path = parse_string(raw, line)
  elseif key == "font-size" then
    config.font_size = parse_integer(raw, line, 1, 256)
  elseif key == "ligatures" then
    config.ligatures = parse_boolean(raw, line)
  elseif key == "contextual-alternates" then
    config.contextual_alternates = parse_boolean(raw, line)
  elseif key == "scrollback-limit" then
    config.scrollback_limit = parse_integer(raw, line, 0, 1000000)
  elseif key == "scrollbar" then
    config.scrollbar = parse_scrollbar_policy(raw, line)
  elseif key == "ambiguous-width" then
    config.ambiguous_width = parse_integer(raw, line, 1, 2)
  elseif key == "foreground" then
    config.foreground = Config.parse_color(raw, line)
    config.color_overrides.foreground = config.foreground
  elseif key == "background" then
    config.background = Config.parse_color(raw, line)
    config.color_overrides.background = config.background
  elseif key == "selection-color" then
    config.selection_color = parse_string(raw, line)
    Config.parse_color(config.selection_color, line)
    config.color_overrides.selection_color = config.selection_color
  elseif key == "search-color" then
    config.search_color = parse_string(raw, line)
    Config.parse_color(config.search_color, line)
    config.color_overrides.search_color = config.search_color
  elseif key == "hyperlink-color" then
    config.hyperlink_color = parse_string(raw, line)
    Config.parse_color(config.hyperlink_color, line)
    config.color_overrides.hyperlink_color = config.hyperlink_color
  elseif key == "command-region-color" then
    config.command_region_color = parse_string(raw, line)
    Config.parse_color(config.command_region_color, line)
    config.color_overrides.command_region_color = config.command_region_color
  elseif key == "command-regions" then
    config.command_regions = parse_boolean(raw, line)
  elseif key == "mouse-shift-capture" then
    config.mouse_shift_capture = parse_mouse_shift_capture(raw, line)
  elseif key == "keybind" then
    if #config.keybindings >= Actions.maximum_bindings then
      error("configuration line " .. line .. " exceeds " .. Actions.maximum_bindings .. " keybindings")
    end
    config.keybindings[#config.keybindings + 1] = Actions.parse(parse_string(raw, line), line)
  elseif key == "command-palette-entry" then
    if #config.command_palette_entries >= Actions.maximum_palette_directives then
      error("configuration line " .. line .. " exceeds " .. Actions.maximum_palette_directives .. " command-palette directives")
    end
    config.command_palette_entries[#config.command_palette_entries + 1] = Actions.parse_palette_entry(raw, line)
  elseif key == "osc52-write" then
    config.osc52_write = parse_boolean(raw, line)
  elseif key == "osc52-read" then
    config.osc52_read = parse_osc52_read_policy(raw, line)
  elseif key == "osc9-notifications" then
    config.osc9_notifications = parse_osc9_policy(raw, line)
  elseif key == "osc9-progress" then
    config.osc9_progress = parse_osc9_policy(raw, line)
  elseif key == "notify-on-command-finish" then
    config.notify_on_command_finish = parse_command_finish_policy(raw, line)
  elseif key == "notify-on-command-finish-after" then
    config.notify_on_command_finish_after = parse_integer(raw, line, 0, 86400)
  elseif key == "shell-integration" then
    local mode = parse_string(raw, line)
    if mode ~= "auto" and mode ~= "none" then error("configuration line " .. line .. " shell-integration must be auto or none") end
    config.shell_integration = mode
  elseif key == "macos-applescript" then
    config.macos_applescript = parse_boolean(raw, line)
  else
    local palette_index = key:match("^palette%-(%d+)$")
    if palette_index == nil then error("configuration line " .. line .. " has an unknown key: " .. key) end
    palette_index = tonumber(palette_index)
    if palette_index > 255 then error("configuration line " .. line .. " palette index must be 0 through 255") end
    config.palette[palette_index] = Config.parse_color(raw, line)
    config.color_overrides.palette[palette_index] = config.palette[palette_index]
  end
end

function Config.parse(text, source, base, options)
  options = options or {}
  assert(type(text) == "string", "configuration text must be a string")
  if #text > Config.maximum_bytes then error("configuration " .. (source or "input") .. " exceeds " .. Config.maximum_bytes .. " bytes") end
  local assignments = {}
  local count = 0
  for raw_line in (text .. "\n"):gmatch("(.-)\n") do
    count = count + 1
    if count > Config.maximum_lines then error("configuration " .. (source or "input") .. " exceeds " .. Config.maximum_lines .. " lines") end
    local line = trim(raw_line)
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local key, value = line:match("^([a-z][a-z0-9%-]*)%s*=%s*(.-)%s*$")
      if key == nil then error("configuration line " .. count .. " must use key = value") end
      assignments[#assignments + 1] = { key = key, value = value, line = count }
    end
  end
  local config = base and copy_table(base) or defaults()
  local requested_theme
  local requested_theme_line
  local requested_theme_file
  local requested_theme_file_line
  local theme_settings_changed = false
  for _, assignment in ipairs(assignments) do
    if assignment.key == "theme" then
      local name = parse_string(assignment.value, assignment.line)
      if name ~= "system" then assert_builtin_theme(name, assignment.line) end
      requested_theme = name
      requested_theme_line = assignment.line
      theme_settings_changed = true
    elseif assignment.key == "theme-dark" then
      config.theme_dark = assert_builtin_theme(parse_string(assignment.value, assignment.line), assignment.line)
      theme_settings_changed = true
    elseif assignment.key == "theme-light" then
      config.theme_light = assert_builtin_theme(parse_string(assignment.value, assignment.line), assignment.line)
      theme_settings_changed = true
    elseif assignment.key == "appearance" then
      config.appearance = parse_appearance(assignment.value, assignment.line)
      theme_settings_changed = true
    elseif assignment.key == "theme-file" then
      requested_theme_file = parse_string(assignment.value, assignment.line)
      requested_theme_file_line = assignment.line
      theme_settings_changed = true
    end
  end
  if requested_theme ~= nil and requested_theme_file ~= nil then
    error("configuration line " .. requested_theme_file_line .. " cannot combine theme-file with theme")
  end
  if requested_theme_file ~= nil then
    local loader = options.theme_loader
    if loader == nil then error("configuration line " .. requested_theme_file_line .. " theme-file needs a trusted theme loader") end
    apply_external_theme(config, requested_theme_file, loader(requested_theme_file))
  elseif requested_theme ~= nil then
    config.color_overrides = empty_color_overrides()
    if requested_theme == "system" then
      config.theme_file = nil
      config.theme_mode = "system"
      config.resolved_appearance = Config.resolve_appearance(config.appearance, options.appearance)
      apply_theme(config, config.resolved_appearance == "light" and config.theme_light or config.theme_dark, requested_theme_line)
      config.theme_mode = "system"
    else
      config.theme_file = nil
      config.theme_mode = "named"
      apply_theme(config, requested_theme, requested_theme_line)
    end
  elseif config.foreground == nil then
    apply_theme(config, config.theme, 0)
  elseif theme_settings_changed and config.theme_mode == "system" then
    config.resolved_appearance = Config.resolve_appearance(config.appearance, options.appearance)
    apply_theme(config, config.resolved_appearance == "light" and config.theme_light or config.theme_dark, "appearance")
    apply_color_overrides(config)
    config.theme_mode = "system"
  end
  for _, assignment in ipairs(assignments) do
    if assignment.key ~= "theme" and assignment.key ~= "theme-dark" and assignment.key ~= "theme-light"
      and assignment.key ~= "appearance" and assignment.key ~= "theme-file" then
      apply_value(config, assignment.key, assignment.value, assignment.line)
    end
  end
  Actions.palette_entries(config.command_palette_entries)
  return config
end

function Config.default_paths(environment, platform)
  environment = environment or os.getenv
  platform = platform or (jit and jit.os) or ""
  local paths = {}
  local xdg = environment("XDG_CONFIG_HOME")
  local home = environment("HOME")
  if type(xdg) == "string" and #xdg > 0 then
    paths[#paths + 1] = xdg .. "/kiwi/config"
  elseif type(home) == "string" and #home > 0 then
    paths[#paths + 1] = home .. "/.config/kiwi/config"
  end
  if platform == "OSX" and type(home) == "string" and #home > 0 then
    paths[#paths + 1] = home .. "/Library/Application Support/io.github.gongahkia.kiwi/config"
  end
  return paths
end

function Config.default_path(environment, platform)
  return Config.default_paths(environment, platform)[1]
end

function Config.edit_path(explicit_path, loaded_path, environment, platform)
  if loaded_path ~= nil then
    assert(type(loaded_path) == "string" and #loaded_path > 0 and not loaded_path:find("\0", 1, true), "loaded configuration path must be non-empty and NUL-free")
    return loaded_path
  end
  if explicit_path ~= nil then
    assert(type(explicit_path) == "string" and #explicit_path > 0 and not explicit_path:find("\0", 1, true), "explicit configuration path must be non-empty and NUL-free")
    return explicit_path
  end
  local paths = Config.default_paths(environment, platform)
  return paths[#paths]
end

function Config.apply_environment(config, environment)
  environment = environment or os.getenv
  local values = {
    ["font-path"] = environment("KIWI_FONT"),
    ["font-family"] = environment("KIWI_FONT_FAMILY"),
    ["font-size"] = environment("KIWI_FONT_PX"),
    ["ligatures"] = environment("KIWI_LIGATURES") == "1" and "true" or environment("KIWI_LIGATURES") == "0" and "false" or nil,
    ["contextual-alternates"] = environment("KIWI_CALT") == "1" and "true" or environment("KIWI_CALT") == "0" and "false" or nil,
    ["scrollback-limit"] = environment("KIWI_SCROLLBACK"),
    ["scrollbar"] = environment("KIWI_SCROLLBAR"),
    ["ambiguous-width"] = environment("KIWI_AMBIGUOUS_WIDTH"),
    ["selection-color"] = environment("KIWI_SELECTION_COLOR"),
    ["search-color"] = environment("KIWI_SEARCH_COLOR"),
    ["hyperlink-color"] = environment("KIWI_HYPERLINK_COLOR"),
    ["command-region-color"] = environment("KIWI_COMMAND_REGION_COLOR"),
    ["command-regions"] = environment("KIWI_COMMAND_REGIONS") == "1" and "true" or environment("KIWI_COMMAND_REGIONS") == "0" and "false" or nil,
    ["mouse-shift-capture"] = environment("KIWI_MOUSE_SHIFT_CAPTURE"),
    ["osc52-read"] = environment("KIWI_OSC52_READ"),
    ["osc52-write"] = environment("KIWI_OSC52_WRITE") == "1" and "true" or environment("KIWI_OSC52_WRITE") == "0" and "false" or nil,
    ["notify-on-command-finish"] = environment("KIWI_NOTIFY_ON_COMMAND_FINISH"),
    ["notify-on-command-finish-after"] = environment("KIWI_NOTIFY_ON_COMMAND_FINISH_AFTER"),
    ["shell-integration"] = environment("KIWI_SHELL_INJECTION"),
  }
  for key, value in pairs(values) do
    if value ~= nil and value ~= "" then apply_value(config, key, value, "environment " .. key) end
  end
  return config
end

local function quoted_command_line_value(value)
  if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then
    error("command-line configuration values must be non-empty NUL-free strings")
  end
  for index = 1, #value do
    local byte = value:byte(index)
    if byte < 0x20 or byte == 0x7f then
      error("command-line configuration values cannot contain control bytes")
    end
  end
  return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

function Config.apply_command_line(config, overrides, options)
  assert(type(config) == "table", "command-line configuration needs a configuration table")
  assert(type(overrides) == "table", "command-line configuration overrides must be a table")
  if #overrides == 0 then return config end
  local lines = {}
  for index, override in ipairs(overrides) do
    if type(override) ~= "table" or command_line_keys[override.key] ~= true then
      error("command-line configuration override " .. index .. " has an unsupported key")
    end
    lines[index] = override.key .. " = " .. quoted_command_line_value(override.value)
  end
  return Config.parse(table.concat(lines, "\n"), "command line", config, options)
end

function Config.load(path, environment, options)
  options = options or {}
  local explicit = path ~= nil
  local paths = explicit and { path } or Config.default_paths(environment)
  local config = Config.parse("", "defaults")
  local loaded_path = nil
  for _, candidate in ipairs(paths) do
    local handle = io.open(candidate, "rb")
    if handle == nil then
      if explicit then error("could not open configuration file: " .. candidate) end
    else
      local text = handle:read(Config.maximum_bytes + 1)
      handle:close()
      if text == nil then error("could not read configuration file: " .. candidate) end
      config = Config.parse(text, candidate, config, {
        appearance = options.appearance,
        theme_loader = options.theme_loader or Config.load_theme,
      })
      loaded_path = candidate
    end
  end
  config = Config.apply_environment(config, environment)
  config = Config.apply_command_line(config, options.command_line_overrides or {}, {
    appearance = options.appearance,
    theme_loader = options.theme_loader or Config.load_theme,
  })
  config.path = loaded_path
  return config, loaded_path
end

function Config.theme_names()
  local names = {}
  for name in pairs(themes) do names[#names + 1] = name end
  table.sort(names)
  return names
end

return Config
