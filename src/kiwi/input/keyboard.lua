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

local keypad = {
  [320] = { numeric = "0", application = "p" }, [321] = { numeric = "1", application = "q" },
  [322] = { numeric = "2", application = "r" }, [323] = { numeric = "3", application = "s" },
  [324] = { numeric = "4", application = "t" }, [325] = { numeric = "5", application = "u" },
  [326] = { numeric = "6", application = "v" }, [327] = { numeric = "7", application = "w" },
  [328] = { numeric = "8", application = "x" }, [329] = { numeric = "9", application = "y" },
  [330] = { numeric = ".", application = "n" }, [331] = { numeric = "/", application = "o" },
  [332] = { numeric = "*", application = "j" }, [333] = { numeric = "-", application = "m" },
  [334] = { numeric = "+", application = "k" }, [335] = { numeric = "\r", application = "M" },
  [336] = { numeric = "=", application = "X" },
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

local function associated_text(value)
  if value == nil then return nil end
  assert(type(value) == "table", "associated key text must be a table")
  local copy = {}
  for index, codepoint in ipairs(value) do
    assert(type(codepoint) == "number" and codepoint % 1 == 0 and codepoint >= 0x20 and codepoint <= 0x10ffff and not (codepoint >= 0xd800 and codepoint <= 0xdfff) and not (codepoint >= 0x7f and codepoint <= 0x9f), "associated key text must contain non-control Unicode scalars")
    copy[index] = codepoint
  end
  assert(#copy == #value, "associated key text must not be sparse")
  return #copy == 0 and nil or copy
end

local function kitty_sequence(codepoint, modifiers, action, modes, glfw, text)
  local parameter = kitty_parameter(modifiers, action, modes, glfw)
  if text and kitty_flag(modes, 8) and kitty_flag(modes, 16) then
    return string.format("\27[%d;%s;%su", codepoint, parameter or "", table.concat(text, ":"))
  end
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

local function modify_other_keys_level(modes)
  local level = modes and modes.modify_other_keys or 0
  return type(level) == "number" and level >= 1 and level <= 3 and level % 1 == 0 and level or 0
end

local function should_encode_modify_other_key(key, modifiers, modes, glfw)
  local level = modify_other_keys_level(modes)
  if level == 0 or printable_key_code(key) == nil then return false end
  local modifier_bits = glfw.mod_shift + glfw.mod_alt + glfw.mod_control + glfw.mod_super
  local active_modifiers = bit.band(modifiers, modifier_bits)
  if level == 3 then return true end
  if level == 2 then return active_modifiers ~= 0 end
  return bit.band(active_modifiers, glfw.mod_alt + glfw.mod_super) ~= 0
end

local function modify_other_keys_sequence(key, modifiers, glfw)
  return string.format("\27[27;%d;%d~", kitty_modifier(modifiers, glfw), printable_key_code(key))
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

local function keypad_sequence(key, modes)
  local value = keypad[key]
  if value == nil or kitty_flag(modes, 8) then return nil end
  if modes and modes.application_keypad then return escape .. "O" .. value.application end
  return value.numeric
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

local function kitty_key(key, action, modifiers, modes, glfw, options)
  local all_keys = kitty_flag(modes, 8)
  local event_types = kitty_flag(modes, 2)
  local text = options and associated_text(options.associated_text) or nil
  if action == glfw.release and not event_types then return nil end
  if all_keys then
    local codepoint = all_keys_codepoint(key, glfw)
    if codepoint then
      return { bytes = kitty_sequence(codepoint, modifiers, action, modes, glfw, text), suppress_text = action ~= glfw.release }
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

function Keyboard.text_sequence(codepoints, modes)
  if type(codepoints) ~= "table" then return nil end
  local text = {}
  for index, codepoint in ipairs(codepoints) do
    if type(codepoint) ~= "number" or codepoint % 1 ~= 0 or codepoint < 0x20 or codepoint > 0x10ffff or (codepoint >= 0xd800 and codepoint <= 0xdfff) or (codepoint >= 0x7f and codepoint <= 0x9f) then
      return nil
    end
    text[index] = codepoint
  end
  if #text == 0 or #text ~= #codepoints then return nil end
  if kitty_flag(modes, 8) then
    if kitty_flag(modes, 16) then return string.format("\27[0;;%su", table.concat(text, ":")) end
    return nil
  end
  local chunks = {}
  for index, codepoint in ipairs(text) do chunks[index] = Utf8.encode(codepoint) end
  return table.concat(chunks)
end

function Keyboard.text(codepoint, modes)
  return Keyboard.text_sequence({ codepoint }, modes)
end

function Keyboard.should_defer_text(key, action, modifiers, modes, glfw)
  return kitty_flag(modes, 8) and kitty_flag(modes, 16)
    and (action == glfw.press or action == glfw.repeat_action)
    and printable_key_code(key) ~= nil
    and bit.band(modifiers, glfw.mod_control + glfw.mod_super) == 0
end

function Keyboard.key(key, action, modifiers, modes, glfw, options)
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
    local encoded = kitty_key(key, action, modifiers, modes, glfw, options)
    if encoded then return encoded end
    if action == glfw.release then return nil end
  end
  if should_encode_modify_other_key(key, modifiers, modes, glfw) then
    return { bytes = modify_other_keys_sequence(key, modifiers, glfw), suppress_text = true }
  end
  local keypad_bytes = keypad_sequence(key, modes)
  if keypad_bytes then return { bytes = keypad_bytes, suppress_text = true } end
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
    return { bytes = modes and modes.backarrow and "\b" or "\127" }
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
