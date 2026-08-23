local bit = require("bit")

local Actions = {}

Actions.maximum_bindings = 64
Actions.maximum_binding_bytes = 128
Actions.maximum_palette_entries = 32

local known_actions = {
  ["command-palette"] = true,
  ["close-pane"] = true,
  ["new-tab"] = true,
  ["new-window"] = true,
  ["next-tab"] = true,
  ["reload-config"] = true,
  ["move-session-new-window"] = true,
  ["move-session-next-window"] = true,
  ["duplicate-session-new-window"] = true,
  ["duplicate-session-next-window"] = true,
  ["split-down"] = true,
  ["split-right"] = true,
}

local palette_catalog = {
  { action = "new-tab", title = "New Tab", description = "Create a terminal tab in this window." },
  { action = "new-window", title = "New Window", description = "Open a new Kiwi window." },
  { action = "next-tab", title = "Next Tab", description = "Focus the next terminal tab." },
  { action = "close-pane", title = "Close Pane", description = "Close the active terminal pane." },
  { action = "split-right", title = "Split Right", description = "Create a pane to the right of the active pane." },
  { action = "split-down", title = "Split Down", description = "Create a pane below the active pane." },
  { action = "move-session-new-window", title = "Move Session to New Window", description = "Move the active live terminal session into a new window." },
  { action = "move-session-next-window", title = "Move Session to Next Window", description = "Move the active live terminal session into the next Kiwi window." },
  { action = "duplicate-session-new-window", title = "Duplicate Session to New Window", description = "Open a fresh terminal session in a new window." },
  { action = "duplicate-session-next-window", title = "Duplicate Session to Next Window", description = "Open a fresh terminal session in the next Kiwi window." },
  { action = "reload-config", title = "Reload Configuration", description = "Reload Kiwi's configuration and trusted theme data." },
}

local default_specs = {
  "ctrl+tab=next-tab",
  "ctrl+shift+t=new-tab",
  "ctrl+shift+n=new-window",
  "ctrl+shift+m=move-session-new-window",
  "ctrl+shift+alt+m=move-session-next-window",
  "ctrl+shift+d=duplicate-session-new-window",
  "ctrl+shift+alt+d=duplicate-session-next-window",
  "ctrl+shift+w=close-pane",
  "ctrl+shift+enter=split-right",
  "ctrl+shift+j=split-down",
  "ctrl+shift+p=command-palette",
  "f6=reload-config",
}

local modifier_aliases = {
  alt = "alt",
  cmd = "super",
  control = "control",
  ctrl = "control",
  shift = "shift",
  super = "super",
}

local special_keys = {
  backspace = "key_backspace",
  delete = "key_delete",
  down = "key_down",
  ["end"] = "key_end",
  enter = "key_enter",
  escape = "key_escape",
  home = "key_home",
  insert = "key_insert",
  left = "key_left",
  page_down = "key_page_down",
  page_up = "key_page_up",
  right = "key_right",
  space = "key_space",
  tab = "key_tab",
  up = "key_up",
}

local function trim(value)
  return value:match("^%s*(.-)%s*$")
end

local function sorted_modifier_names(modifiers)
  local names = {}
  for name in pairs(modifiers) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local function canonical_chord(key, modifiers)
  local parts = sorted_modifier_names(modifiers)
  parts[#parts + 1] = key
  return table.concat(parts, "+")
end

local function parse_chord(value, line)
  local modifiers = {}
  local key
  local count = 0
  for part in value:gmatch("[^+]+") do
    count = count + 1
    part = trim(part):lower():gsub("%-", "_")
    if part == "" then error("configuration line " .. line .. " has an empty keybinding chord component") end
    local modifier = modifier_aliases[part]
    if modifier ~= nil then
      if modifiers[modifier] then error("configuration line " .. line .. " repeats a keybinding modifier") end
      modifiers[modifier] = true
    elseif key == nil then
      if not part:match("^[a-z0-9_]+$") then error("configuration line " .. line .. " has an invalid keybinding key") end
      key = part
    else
      error("configuration line " .. line .. " has more than one keybinding key")
    end
  end
  if count == 0 or key == nil then error("configuration line " .. line .. " needs a keybinding key") end
  if key:match("^f%d+$") then
    local number = tonumber(key:sub(2))
    if number == nil or number < 1 or number > 12 then error("configuration line " .. line .. " supports F1 through F12") end
  elseif #key ~= 1 and special_keys[key] == nil then
    error("configuration line " .. line .. " names an unsupported keybinding key: " .. key:gsub("_", "-"))
  end
  return key, modifiers
end

function Actions.parse(value, line)
  assert(type(value) == "string", "keybinding value must be a string")
  line = tostring(line or "?")
  value = trim(value)
  if #value == 0 or #value > Actions.maximum_binding_bytes then
    error("configuration line " .. line .. " has an out-of-range keybinding value")
  end
  if value == "clear" then return { clear = true } end
  local chord, action = value:match("^([^=]+)%s*=%s*([a-z][a-z0-9%-]*)$")
  if chord == nil then error("configuration line " .. line .. " keybind must use chord = action") end
  local key, modifiers = parse_chord(chord, line)
  if action ~= "none" and known_actions[action] ~= true then
    error("configuration line " .. line .. " names an unknown keybinding action: " .. action)
  end
  return {
    action = action,
    chord = canonical_chord(key, modifiers),
    key = key,
    modifiers = modifiers,
  }
end

local function modifier_mask(modifiers, keymap)
  local mask = 0
  if modifiers.shift then mask = mask + keymap.mod_shift end
  if modifiers.control then mask = mask + keymap.mod_control end
  if modifiers.alt then mask = mask + keymap.mod_alt end
  if modifiers.super then mask = mask + keymap.mod_super end
  return mask
end

local function key_code(name, keymap)
  if #name == 1 then return string.byte(name:upper()) end
  if name:match("^f%d+$") then return keymap["key_" .. name] end
  return keymap[special_keys[name]]
end

local function signature(key, modifiers)
  return tostring(key) .. ":" .. tostring(modifiers)
end

function Actions.new(configured, keymap)
  assert(type(configured) == "table", "configured keybindings must be a table")
  assert(type(keymap) == "table", "keybinding map must be a table")
  local known_modifier_mask = keymap.mod_shift + keymap.mod_control + keymap.mod_alt + keymap.mod_super
  local bindings = {}
  local function apply(specification, line)
    local parsed = type(specification) == "string" and Actions.parse(specification, line) or specification
    if parsed.clear then
      bindings = {}
      return
    end
    local key = key_code(parsed.key, keymap)
    if key == nil then error("configuration line " .. tostring(line or "?") .. " uses an unavailable keybinding key") end
    local binding = signature(key, modifier_mask(parsed.modifiers, keymap))
    if parsed.action == "none" then
      bindings[binding] = nil
    else
      bindings[binding] = parsed.action
    end
  end
  for _, specification in ipairs(default_specs) do apply(specification, "default") end
  if #configured > Actions.maximum_bindings then error("configured keybindings exceed " .. Actions.maximum_bindings) end
  for index, specification in ipairs(configured) do apply(specification, "keybind " .. index) end
  return setmetatable({ bindings = bindings, known_modifier_mask = known_modifier_mask }, { __index = Actions })
end

function Actions:lookup(key, modifiers)
  local normalized = bit.band(modifiers or 0, self.known_modifier_mask)
  return self.bindings[signature(key, normalized)]
end

function Actions:bindings_view()
  local values = {}
  for binding, action in pairs(self.bindings) do values[#values + 1] = { action = action, binding = binding } end
  table.sort(values, function(left, right) return left.binding < right.binding end)
  return values
end

function Actions.names()
  local names = {}
  for name in pairs(known_actions) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function Actions.palette_entries()
  local entries = {}
  for index, entry in ipairs(palette_catalog) do
    entries[index] = {
      action = entry.action,
      description = entry.description,
      title = entry.title,
    }
  end
  return entries
end

return Actions
