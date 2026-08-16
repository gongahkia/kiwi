local bit = require("bit")
local Utf8 = require("kiwi.terminal.utf8")

local Keyboard = {}

local escape = "\27"

local navigation = {
  [260] = "[2~",
  [261] = "[3~",
  [266] = "[5~",
  [267] = "[6~",
  [268] = "[H",
  [269] = "[F",
}

local arrows = {
  [262] = "C",
  [263] = "D",
  [264] = "B",
  [265] = "A",
}

local function kitty_flag(modes, flag)
  return modes and bit.band(modes.keyboard_flags or 0, flag) ~= 0
end

local function kitty_modifier(modifiers, glfw)
  local value = 1
  if bit.band(modifiers, glfw.mod_shift) ~= 0 then value = value + 1 end
  if bit.band(modifiers, glfw.mod_alt) ~= 0 then value = value + 2 end
  if bit.band(modifiers, glfw.mod_control) ~= 0 then value = value + 4 end
  if bit.band(modifiers, glfw.mod_super) ~= 0 then value = value + 8 end
  return value
end

local function kitty_event_type(action, glfw)
  if action == glfw.press then return 1 end
  if action == glfw.repeat_action then return 2 end
  if action == glfw.release then return 3 end
end

local function kitty_parameter(modifiers, action, modes, glfw)
  local modifier = kitty_modifier(modifiers, glfw)
  if kitty_flag(modes, 2) then return string.format("%d:%d", modifier, kitty_event_type(action, glfw)) end
  if modifier == 1 then return nil end
  return tostring(modifier)
end

local function kitty_sequence(codepoint, modifiers, action, modes, glfw)
  local parameter = kitty_parameter(modifiers, action, modes, glfw)
  if parameter == nil then return string.format("\27[%du", codepoint) end
  return string.format("\27[%d;%su", codepoint, parameter)
end

local function modified_sequence(parameter, final, modifiers, action, modes, glfw)
  local modifier = kitty_parameter(modifiers, action, modes, glfw)
  if modifier == nil then return string.format("\27[%s%s", parameter, final) end
  return string.format("\27[%s;%s%s", parameter, modifier, final)
end

local function cursor_sequence(final, modifiers, application_cursor, action, modes, glfw)
  local modifier = kitty_parameter(modifiers, action, modes, glfw)
  if modifier == nil then return escape .. (application_cursor and "O" or "[") .. final end
  return string.format("\27[1;%s%s", modifier, final)
end

local function printable_key_code(key)
  if key >= string.byte("A") and key <= string.byte("Z") then return key + 0x20 end
  if key >= 0x20 and key <= 0x7e then return key end
end

local function function_key_sequence(key, modifiers, action, modes, glfw)
  local f1_to_f4 = { [glfw.key_f1] = "P", [glfw.key_f2] = "Q", [glfw.key_f3] = "R", [glfw.key_f4] = "S" }
  local f5_to_f12 = {
    [glfw.key_f5] = 15, [glfw.key_f6] = 17, [glfw.key_f7] = 18, [glfw.key_f8] = 19,
    [glfw.key_f9] = 20, [glfw.key_f10] = 21, [glfw.key_f11] = 23, [glfw.key_f12] = 24,
  }
  if f1_to_f4[key] then return cursor_sequence(f1_to_f4[key], modifiers, true, action, modes, glfw) end
  if f5_to_f12[key] then return modified_sequence(f5_to_f12[key], "~", modifiers, action, modes, glfw) end
end

local function enhanced_functional_key(key, modifiers, action, modes, glfw)
  local cursor = arrows[key]
  if cursor then return cursor_sequence(cursor, modifiers, false, action, modes, glfw) end
  if key == glfw.key_home then return cursor_sequence("H", modifiers, false, action, modes, glfw) end
  if key == glfw.key_end then return cursor_sequence("F", modifiers, false, action, modes, glfw) end
  if navigation[key] then
    local parameter, final = navigation[key]:match("^%[([^~]+)(~)$")
    return modified_sequence(parameter, final, modifiers, action, modes, glfw)
  end
  return function_key_sequence(key, modifiers, action, modes, glfw)
end

local function all_keys_codepoint(key, glfw)
  local printable = printable_key_code(key)
  if printable then return printable end
  if key == glfw.key_escape then return 27 end
  if key == glfw.key_enter then return 13 end
  if key == glfw.key_tab then return 9 end
  if key == glfw.key_backspace then return 127 end
end

local function kitty_key(key, action, modifiers, modes, glfw)
  local all_keys = kitty_flag(modes, 8)
  local event_types = kitty_flag(modes, 2)
  if action == glfw.release and not event_types then return nil end
  if all_keys then
    local codepoint = all_keys_codepoint(key, glfw)
    if codepoint then
      return { bytes = kitty_sequence(codepoint, modifiers, action, modes, glfw), suppress_text = action ~= glfw.release }
    end
    local functional = enhanced_functional_key(key, modifiers, action, modes, glfw)
    if functional then return { bytes = functional } end
    return nil
  end
  local printable = printable_key_code(key)
  if printable and bit.band(modifiers, glfw.mod_alt + glfw.mod_control + glfw.mod_super) ~= 0 then
    return { bytes = kitty_sequence(printable, modifiers, action, modes, glfw), suppress_text = true }
  end
  if key == glfw.key_escape then
    return { bytes = kitty_sequence(27, modifiers, action, modes, glfw) }
  end
  if arrows[key] then return { bytes = cursor_sequence(arrows[key], modifiers, modes and modes.application_cursor, action, modes, glfw) } end
  if key == glfw.key_home then return { bytes = cursor_sequence("H", modifiers, modes and modes.application_cursor, action, modes, glfw) } end
  if key == glfw.key_end then return { bytes = cursor_sequence("F", modifiers, modes and modes.application_cursor, action, modes, glfw) } end
  if navigation[key] then
    local prefix, final = navigation[key]:match("^%[([^~]+)(~)$")
    return { bytes = modified_sequence(prefix, final, modifiers, action, modes, glfw) }
  end
  local function_key = function_key_sequence(key, modifiers, action, modes, glfw)
  if function_key then return { bytes = function_key } end
end

function Keyboard.text(codepoint, modes)
  if kitty_flag(modes, 8) then return nil end
  if codepoint < 0x20 or codepoint == 0x7f then
    return nil
  end
  return Utf8.encode(codepoint)
end

function Keyboard.key(key, action, modifiers, modes, glfw)
  local enhanced = kitty_flag(modes, 1) or kitty_flag(modes, 2) or kitty_flag(modes, 8)
  local local_actions_allowed = not kitty_flag(modes, 8)
  if action ~= glfw.press and action ~= glfw.repeat_action and action ~= glfw.release then
    return nil
  end
  if action == glfw.release and not (enhanced and kitty_flag(modes, 2)) then return nil end
  if action == glfw.release then return kitty_key(key, action, modifiers, modes, glfw) end
  if local_actions_allowed and bit.band(modifiers, glfw.mod_control + glfw.mod_alt) == glfw.mod_control + glfw.mod_alt then
    local direction = bit.band(modifiers, glfw.mod_shift) ~= 0 and "next" or "previous"
    local role = ({ [string.byte("P")] = "prompt", [string.byte("C")] = "command", [string.byte("O")] = "output" })[key]
    if role then return { local_action = "region_" .. direction .. "_" .. role, suppress_text = true } end
  end
  if local_actions_allowed and bit.band(modifiers, glfw.mod_control) ~= 0 and bit.band(modifiers, glfw.mod_shift) ~= 0 then
    if key == string.byte("C") then return action == glfw.press and { local_action = "copy", suppress_text = true } or { suppress_text = true } end
    if key == string.byte("V") then return action == glfw.press and { local_action = "paste", suppress_text = true } or { suppress_text = true } end
    if key == string.byte("F") then return action == glfw.press and { local_action = "search_begin", suppress_text = true } or { suppress_text = true } end
    if key == string.byte("G") then return action == glfw.press and { local_action = "search_next", suppress_text = true } or { suppress_text = true } end
    if key == string.byte("R") then return action == glfw.press and { local_action = "search_previous", suppress_text = true } or { suppress_text = true } end
    if key == string.byte("O") then return action == glfw.press and { local_action = "open_hyperlink", suppress_text = true } or { suppress_text = true } end
  end
  if enhanced then
    local encoded = kitty_key(key, action, modifiers, modes, glfw)
    if encoded then return encoded end
    if action == glfw.release then return nil end
  end
  if local_actions_allowed and bit.band(modifiers, glfw.mod_shift) ~= 0 and key == glfw.key_page_up then
    return { local_action = "scroll_up" }
  end
  if local_actions_allowed and bit.band(modifiers, glfw.mod_shift) ~= 0 and key == glfw.key_page_down then
    return { local_action = "scroll_down" }
  end
  if bit.band(modifiers, glfw.mod_control) ~= 0 and key >= string.byte("A") and key <= string.byte("Z") then
    return { bytes = string.char(key - string.byte("A") + 1) }
  end
  if key == glfw.key_enter then
    return { bytes = "\r" }
  end
  if key == glfw.key_backspace then
    return { bytes = "\127" }
  end
  if key == glfw.key_tab then
    return { bytes = "\t" }
  end
  if key == glfw.key_escape then
    return { bytes = escape }
  end
  if arrows[key] then
    return { bytes = escape .. ((modes and modes.application_cursor) and "O" or "[") .. arrows[key] }
  end
  if navigation[key] then
    return { bytes = escape .. navigation[key] }
  end
  if bit.band(modifiers, glfw.mod_alt) ~= 0 and key >= string.byte("A") and key <= string.byte("Z") then
    return { bytes = escape }
  end
  return nil
end

return Keyboard
