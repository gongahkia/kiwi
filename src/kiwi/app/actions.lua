local bit = require("bit")
local Utf8 = require("kiwi.terminal.utf8")

local Actions = {}

Actions.maximum_bindings = 64
Actions.maximum_binding_bytes = 128
Actions.maximum_sequence_steps = 3
Actions.sequence_timeout_seconds = 1
Actions.maximum_palette_entries = 32
Actions.maximum_palette_directives = 64
Actions.maximum_palette_entry_bytes = 512
Actions.maximum_palette_title_bytes = 128
Actions.maximum_palette_description_bytes = 256
Actions.maximum_session_target_entries = 15

local known_actions = {
  ["command-palette"] = true,
  ["close-pane"] = true,
  ["new-tab"] = true,
  ["new-window"] = true,
  ["next-tab"] = true,
  ["open-configuration"] = true,
  ["reload-config"] = true,
  ["move-session-new-window"] = true,
  ["move-session-next-window"] = true,
  ["move-session-select-window"] = true,
  ["duplicate-session-new-window"] = true,
  ["duplicate-session-next-window"] = true,
  ["duplicate-session-select-window"] = true,
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
  { action = "move-session-select-window", title = "Move Session to Window…", description = "Choose a Kiwi window for the active live terminal session." },
  { action = "duplicate-session-new-window", title = "Duplicate Session to New Window", description = "Open a fresh terminal session in a new window." },
  { action = "duplicate-session-select-window", title = "Duplicate Session to Window…", description = "Choose a Kiwi window for a fresh terminal session." },
  { action = "open-configuration", title = "Open Configuration", description = "Open the active Kiwi configuration as text." },
  { action = "reload-config", title = "Reload Configuration", description = "Reload Kiwi's configuration and trusted theme data." },
}

local default_specs = {
  "ctrl+tab=next-tab",
  "ctrl+shift+t=new-tab",
  "ctrl+shift+n=new-window",
  "ctrl+shift+m=move-session-new-window",
  "ctrl+shift+alt+m=move-session-select-window",
  "ctrl+shift+d=duplicate-session-new-window",
  "ctrl+shift+alt+d=duplicate-session-select-window",
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

local function valid_utf8(value)
  local valid = true
  local decoder = Utf8.Decoder.new(function(_, _, replaced)
    if replaced then valid = false end
  end)
  for index = 1, #value do decoder:feed_byte(value:byte(index)) end
  decoder:finish()
  return valid
end

local function valid_palette_text(value, maximum, required)
  if type(value) ~= "string" or #value > maximum or (required and #value == 0) or value:find("\0", 1, true) or not valid_utf8(value) then
    return false
  end
  for index = 1, #value do
    local byte = value:byte(index)
    if byte < 0x20 or byte == 0x7f then return false end
  end
  return true
end

function Actions.session_target_index(action)
  if type(action) ~= "string" then return nil end
  local index = action:match("^session%-target%-(%d+)$")
  index = index and tonumber(index) or nil
  if index == nil or index < 1 or index > Actions.maximum_session_target_entries or index % 1 ~= 0 then return nil end
  return index
end

function Actions.session_target_entries(targets, operation)
  assert(type(targets) == "table" and #targets > 0 and #targets <= Actions.maximum_session_target_entries, "session target chooser needs one through " .. Actions.maximum_session_target_entries .. " targets")
  assert(operation == "move" or operation == "duplicate", "session target chooser needs a known operation")
  local entries = {}
  for index, target in ipairs(targets) do
    assert(type(target) == "table" and valid_palette_text(target.title, Actions.maximum_palette_title_bytes, true), "session target chooser has an invalid target title")
    entries[index] = {
      action = "session-target-" .. index,
      description = operation == "move" and "Move the active live terminal session here." or "Create a fresh terminal session here.",
      title = target.title,
    }
  end
  return entries
end

local function palette_parse_error(line, message)
  error("configuration line " .. line .. " command-palette-entry " .. message)
end

local function parse_palette_value(value, index, line)
  local size = #value
  if value:sub(index, index) ~= '"' then
    local comma = value:find(",", index, true)
    local stop = comma and comma - 1 or size
    local parsed = trim(value:sub(index, stop))
    if parsed == "" then palette_parse_error(line, "has an empty field") end
    return parsed, comma and comma + 1 or size + 1
  end
  local output = {}
  index = index + 1
  while index <= size do
    local byte = value:sub(index, index)
    if byte == '"' then
      index = index + 1
      while index <= size and value:sub(index, index):match("%s") do index = index + 1 end
      if index <= size and value:sub(index, index) ~= "," then palette_parse_error(line, "has text after a quoted field") end
      return table.concat(output), index <= size and index + 1 or size + 1
    end
    if byte == "\\" then
      index = index + 1
      local escaped = value:sub(index, index)
      if escaped ~= '"' and escaped ~= "\\" then palette_parse_error(line, "has an unsupported quoted-field escape") end
      output[#output + 1] = escaped
    else
      output[#output + 1] = byte
    end
    index = index + 1
  end
  palette_parse_error(line, "has an unterminated quoted field")
end

function Actions.parse_palette_entry(value, line)
  assert(type(value) == "string", "command-palette-entry must be a string")
  line = tostring(line or "?")
  value = trim(value)
  if value == "" then return { clear = true } end
  if #value > Actions.maximum_palette_entry_bytes then palette_parse_error(line, "exceeds " .. Actions.maximum_palette_entry_bytes .. " bytes") end
  local fields = {}
  local index = 1
  while index <= #value do
    while index <= #value and value:sub(index, index):match("%s") do index = index + 1 end
    local start = index
    while index <= #value and value:sub(index, index):match("[a-z]") do index = index + 1 end
    local name = value:sub(start, index - 1)
    while index <= #value and value:sub(index, index):match("%s") do index = index + 1 end
    if name == "" or value:sub(index, index) ~= ":" then palette_parse_error(line, "needs field:value pairs") end
    if name ~= "title" and name ~= "description" and name ~= "action" then palette_parse_error(line, "has an unknown field: " .. name) end
    if fields[name] ~= nil then palette_parse_error(line, "repeats the " .. name .. " field") end
    index = index + 1
    while index <= #value and value:sub(index, index):match("%s") do index = index + 1 end
    local parsed
    parsed, index = parse_palette_value(value, index, line)
    if index > #value and value:sub(-1) == "," then palette_parse_error(line, "has a trailing comma") end
    fields[name] = parsed
  end
  if fields.title == nil or fields.action == nil then palette_parse_error(line, "needs title and action fields") end
  if not valid_palette_text(fields.title, Actions.maximum_palette_title_bytes, true) then palette_parse_error(line, "has an invalid title") end
  local description = fields.description or ""
  if not valid_palette_text(description, Actions.maximum_palette_description_bytes, false) then palette_parse_error(line, "has an invalid description") end
  if known_actions[fields.action] ~= true or fields.action == "command-palette" then palette_parse_error(line, "names an unavailable action") end
  return { action = fields.action, description = description, title = fields.title }
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
  local steps = {}
  local index = 1
  while index <= #chord do
    local separator = chord:find(">", index, true)
    local finish = separator and separator - 1 or #chord
    local segment = trim(chord:sub(index, finish))
    if segment == "" then error("configuration line " .. line .. " has an empty keybinding sequence step") end
    local key, modifiers = parse_chord(segment, line)
    steps[#steps + 1] = { key = key, modifiers = modifiers }
    if #steps > Actions.maximum_sequence_steps then
      error("configuration line " .. line .. " keybinding sequences support at most " .. Actions.maximum_sequence_steps .. " steps")
    end
    if separator == nil then break end
    index = separator + 1
    if index > #chord then error("configuration line " .. line .. " has an empty keybinding sequence step") end
  end
  if action ~= "none" and known_actions[action] ~= true then
    error("configuration line " .. line .. " names an unknown keybinding action: " .. action)
  end
  local chords = {}
  for step_index, step in ipairs(steps) do chords[step_index] = canonical_chord(step.key, step.modifiers) end
  return {
    action = action,
    chord = table.concat(chords, ">"),
    steps = steps,
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
  local root = { children = {} }
  local function node_empty(node)
    return node.action == nil and next(node.children) == nil
  end
  local function binding_steps(parsed, line)
    assert(type(parsed.steps) == "table" and #parsed.steps > 0 and #parsed.steps <= Actions.maximum_sequence_steps, "configuration line " .. tostring(line or "?") .. " has an invalid keybinding sequence")
    local values = {}
    for index, step in ipairs(parsed.steps) do
      local key = key_code(step.key, keymap)
      if key == nil then error("configuration line " .. tostring(line or "?") .. " uses an unavailable keybinding key") end
      values[index] = signature(key, modifier_mask(step.modifiers, keymap))
    end
    return values
  end
  local function apply(specification, line)
    local parsed = type(specification) == "string" and Actions.parse(specification, line) or specification
    if parsed.clear then
      root = { children = {} }
      return
    end
    local steps = binding_steps(parsed, line)
    if parsed.action == "none" then
      local node = root
      local ancestors = { root }
      for _, binding in ipairs(steps) do
        node = node.children[binding]
        if node == nil then return end
        ancestors[#ancestors + 1] = node
      end
      node.action = nil
      for index = #steps, 1, -1 do
        local child = ancestors[index + 1]
        if not node_empty(child) then break end
        ancestors[index].children[steps[index]] = nil
      end
    else
      local node = root
      for index, binding in ipairs(steps) do
        if node.action ~= nil then error("configuration line " .. tostring(line or "?") .. " conflicts with a shorter keybinding sequence") end
        local child = node.children[binding]
        if child == nil then
          child = { children = {} }
          node.children[binding] = child
        end
        node = child
        if index == #steps and next(node.children) ~= nil then
          error("configuration line " .. tostring(line or "?") .. " conflicts with a longer keybinding sequence")
        end
      end
      node.action = parsed.action
    end
  end
  for _, specification in ipairs(default_specs) do apply(specification, "default") end
  if #configured > Actions.maximum_bindings then error("configured keybindings exceed " .. Actions.maximum_bindings) end
  for index, specification in ipairs(configured) do apply(specification, "keybind " .. index) end
  return setmetatable({ known_modifier_mask = known_modifier_mask, root = root }, { __index = Actions })
end

function Actions:reset_sequence()
  self.sequence_node = nil
  self.sequence_deadline = nil
end

function Actions:lookup(key, modifiers, now)
  local normalized = bit.band(modifiers or 0, self.known_modifier_mask)
  local binding = signature(key, normalized)
  if self.sequence_deadline ~= nil and now ~= nil and now >= self.sequence_deadline then self:reset_sequence() end
  local node
  if self.sequence_node ~= nil then
    node = self.sequence_node.children[binding]
    if node ~= nil then
      if node.action ~= nil then
        local action = node.action
        self:reset_sequence()
        return action
      end
      self.sequence_node = node
      self.sequence_deadline = now and now + Actions.sequence_timeout_seconds or nil
      return nil, "pending"
    end
    self:reset_sequence()
  end
  node = self.root.children[binding]
  if node == nil then return nil end
  if node.action ~= nil then return node.action end
  self.sequence_node = node
  self.sequence_deadline = now and now + Actions.sequence_timeout_seconds or nil
  return nil, "pending"
end

function Actions:bindings_view()
  local values = {}
  local function collect(node, path)
    if node.action ~= nil then values[#values + 1] = { action = node.action, binding = table.concat(path, ">") } end
    for binding, child in pairs(node.children) do
      path[#path + 1] = binding
      collect(child, path)
      path[#path] = nil
    end
  end
  collect(self.root, {})
  table.sort(values, function(left, right) return left.binding < right.binding end)
  return values
end

function Actions.names()
  local names = {}
  for name in pairs(known_actions) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function Actions.palette_entries(configured)
  configured = configured or {}
  assert(type(configured) == "table", "configured command-palette entries must be a table")
  local entries = {}
  for index, entry in ipairs(palette_catalog) do
    entries[index] = {
      action = entry.action,
      description = entry.description,
      title = entry.title,
    }
  end
  for _, entry in ipairs(configured) do
    assert(type(entry) == "table", "configured command-palette entry must be a table")
    if entry.clear then
      entries = {}
    else
      assert(type(entry.action) == "string" and known_actions[entry.action] == true and entry.action ~= "command-palette", "configured command-palette entry names an unavailable action")
      assert(valid_palette_text(entry.title, Actions.maximum_palette_title_bytes, true), "configured command-palette title is invalid")
      assert(valid_palette_text(entry.description, Actions.maximum_palette_description_bytes, false), "configured command-palette description is invalid")
      if #entries >= Actions.maximum_palette_entries then error("configured command-palette entries exceed " .. Actions.maximum_palette_entries) end
      entries[#entries + 1] = {
        action = entry.action,
        description = entry.description,
        title = entry.title,
      }
    end
  end
  return entries
end

return Actions
