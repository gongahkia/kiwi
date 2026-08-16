local Color = require("kiwi.renderer.color")

local Config = {}

Config.maximum_bytes = 64 * 1024
Config.maximum_lines = 512

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
    font_family = "monospace",
    font_path = nil,
    font_size = 20,
    ligatures = false,
    contextual_alternates = false,
    scrollback_limit = 2000,
    ambiguous_width = 1,
    foreground = nil,
    background = nil,
    palette = {},
    selection_color = nil,
    search_color = nil,
    hyperlink_color = nil,
    command_region_color = nil,
    command_regions = false,
    osc52_write = false,
    shell_integration = "auto",
  }
end

local function apply_theme(config, name, line)
  local theme = themes[name]
  if theme == nil then error("configuration line " .. line .. " names an unknown theme: " .. name) end
  config.theme = name
  config.foreground = Config.parse_color(theme.foreground, line)
  config.background = Config.parse_color(theme.background, line)
  config.palette = {}
  for index, value in pairs(theme.palette or {}) do config.palette[index] = Config.parse_color(value, line) end
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
  elseif key == "ambiguous-width" then
    config.ambiguous_width = parse_integer(raw, line, 1, 2)
  elseif key == "foreground" then
    config.foreground = Config.parse_color(raw, line)
  elseif key == "background" then
    config.background = Config.parse_color(raw, line)
  elseif key == "selection-color" then
    config.selection_color = parse_string(raw, line)
    Config.parse_color(config.selection_color, line)
  elseif key == "search-color" then
    config.search_color = parse_string(raw, line)
    Config.parse_color(config.search_color, line)
  elseif key == "hyperlink-color" then
    config.hyperlink_color = parse_string(raw, line)
    Config.parse_color(config.hyperlink_color, line)
  elseif key == "command-region-color" then
    config.command_region_color = parse_string(raw, line)
    Config.parse_color(config.command_region_color, line)
  elseif key == "command-regions" then
    config.command_regions = parse_boolean(raw, line)
  elseif key == "osc52-write" then
    config.osc52_write = parse_boolean(raw, line)
  elseif key == "shell-integration" then
    local mode = parse_string(raw, line)
    if mode ~= "auto" and mode ~= "none" then error("configuration line " .. line .. " shell-integration must be auto or none") end
    config.shell_integration = mode
  else
    local palette_index = key:match("^palette%-(%d+)$")
    if palette_index == nil then error("configuration line " .. line .. " has an unknown key: " .. key) end
    palette_index = tonumber(palette_index)
    if palette_index > 255 then error("configuration line " .. line .. " palette index must be 0 through 255") end
    config.palette[palette_index] = Config.parse_color(raw, line)
  end
end

function Config.parse(text, source)
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
  local config = defaults()
  for _, assignment in ipairs(assignments) do
    if assignment.key == "theme" then apply_theme(config, parse_string(assignment.value, assignment.line), assignment.line) end
  end
  if config.foreground == nil then apply_theme(config, config.theme, 0) end
  for _, assignment in ipairs(assignments) do
    if assignment.key ~= "theme" then apply_value(config, assignment.key, assignment.value, assignment.line) end
  end
  return config
end

function Config.default_path(environment)
  environment = environment or os.getenv
  local xdg = environment("XDG_CONFIG_HOME")
  if type(xdg) == "string" and #xdg > 0 then return xdg .. "/kiwi/config" end
  local home = environment("HOME")
  if type(home) == "string" and #home > 0 then return home .. "/.config/kiwi/config" end
  return nil
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
    ["ambiguous-width"] = environment("KIWI_AMBIGUOUS_WIDTH"),
    ["selection-color"] = environment("KIWI_SELECTION_COLOR"),
    ["search-color"] = environment("KIWI_SEARCH_COLOR"),
    ["hyperlink-color"] = environment("KIWI_HYPERLINK_COLOR"),
    ["command-region-color"] = environment("KIWI_COMMAND_REGION_COLOR"),
    ["command-regions"] = environment("KIWI_COMMAND_REGIONS") == "1" and "true" or environment("KIWI_COMMAND_REGIONS") == "0" and "false" or nil,
    ["osc52-write"] = environment("KIWI_OSC52_WRITE") == "1" and "true" or environment("KIWI_OSC52_WRITE") == "0" and "false" or nil,
    ["shell-integration"] = environment("KIWI_SHELL_INJECTION"),
  }
  for key, value in pairs(values) do
    if value ~= nil and value ~= "" then apply_value(config, key, value, "environment " .. key) end
  end
  return config
end

function Config.load(path, environment)
  local explicit = path ~= nil
  path = path or Config.default_path(environment)
  if path == nil then return Config.apply_environment(Config.parse("", "defaults"), environment), nil end
  local handle = io.open(path, "rb")
  if handle == nil then
    if explicit then error("could not open configuration file: " .. path) end
    return Config.apply_environment(Config.parse("", "defaults"), environment), nil
  end
  local text = handle:read(Config.maximum_bytes + 1)
  handle:close()
  if text == nil then error("could not read configuration file: " .. path) end
  local config = Config.apply_environment(Config.parse(text, path), environment)
  config.path = path
  return config, path
end

function Config.theme_names()
  local names = {}
  for name in pairs(themes) do names[#names + 1] = name end
  table.sort(names)
  return names
end

return Config
