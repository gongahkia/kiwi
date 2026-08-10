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

local function kitty_enabled(modes)
  return modes and bit.band(modes.keyboard_flags or 0, 1) ~= 0
end

local function kitty_modifier(modifiers, glfw)
  local value = 1
  if bit.band(modifiers, glfw.mod_shift) ~= 0 then value = value + 1 end
  if bit.band(modifiers, glfw.mod_alt) ~= 0 then value = value + 2 end
  if bit.band(modifiers, glfw.mod_control) ~= 0 then value = value + 4 end
  if bit.band(modifiers, glfw.mod_super) ~= 0 then value = value + 8 end
  return value
end

local function kitty_sequence(codepoint, modifiers, glfw)
  local modifier = kitty_modifier(modifiers, glfw)
  if modifier == 1 then return string.format("\27[%du", codepoint) end
  return string.format("\27[%d;%du", codepoint, modifier)
end

local function modified_sequence(parameter, final, modifiers, glfw)
  if kitty_modifier(modifiers, glfw) == 1 then return string.format("\27[%s%s", parameter, final) end
  return string.format("\27[%s;%d%s", parameter, kitty_modifier(modifiers, glfw), final)
end

local function cursor_sequence(final, modifiers, application_cursor, glfw)
  local modifier = kitty_modifier(modifiers, glfw)
  if modifier == 1 then return escape .. (application_cursor and "O" or "[") .. final end
  return string.format("\27[1;%d%s", modifier, final)
end

local function printable_key_code(key)
  if key >= string.byte("A") and key <= string.byte("Z") then return key + 0x20 end
  if key >= 0x20 and key <= 0x7e then return key end
end

local function function_key_sequence(key, modifiers, glfw)
  local f1_to_f4 = { [glfw.key_f1] = "P", [glfw.key_f2] = "Q", [glfw.key_f3] = "R", [glfw.key_f4] = "S" }
  local f5_to_f12 = {
    [glfw.key_f5] = 15, [glfw.key_f6] = 17, [glfw.key_f7] = 18, [glfw.key_f8] = 19,
    [glfw.key_f9] = 20, [glfw.key_f10] = 21, [glfw.key_f11] = 23, [glfw.key_f12] = 24,
  }
  if f1_to_f4[key] then return cursor_sequence(f1_to_f4[key], modifiers, true, glfw) end
  if f5_to_f12[key] then return modified_sequence(f5_to_f12[key], "~", modifiers, glfw) end
end

local function kitty_key(key, modifiers, modes, glfw)
  local printable = printable_key_code(key)
  if printable and bit.band(modifiers, glfw.mod_alt + glfw.mod_control + glfw.mod_super) ~= 0 then
    return { bytes = kitty_sequence(printable, modifiers, glfw), suppress_text = true }
  end
  if key == glfw.key_escape then
    return { bytes = kitty_sequence(27, modifiers, glfw) }
  end
  if arrows[key] then
    return { bytes = cursor_sequence(arrows[key], modifiers, modes and modes.application_cursor, glfw) }
  end
  if key == glfw.key_home then
    return { bytes = cursor_sequence("H", modifiers, modes and modes.application_cursor, glfw) }
  end
  if key == glfw.key_end then
    return { bytes = cursor_sequence("F", modifiers, modes and modes.application_cursor, glfw) }
  end
  if navigation[key] then
    local prefix, final = navigation[key]:match("^%[([^~]+)(~)$")
    return { bytes = modified_sequence(prefix, final, modifiers, glfw) }
  end
  local function_key = function_key_sequence(key, modifiers, glfw)
  if function_key then return { bytes = function_key } end
end

function Keyboard.text(codepoint)
  if codepoint < 0x20 or codepoint == 0x7f then
    return nil
  end
  return Utf8.encode(codepoint)
end

function Keyboard.key(key, action, modifiers, modes, glfw)
  if action ~= glfw.press and action ~= glfw.repeat_action then
    return nil
  end
  if kitty_enabled(modes) then
    local enhanced = kitty_key(key, modifiers, modes, glfw)
    if enhanced then return enhanced end
  end
  if bit.band(modifiers, glfw.mod_shift) ~= 0 and key == glfw.key_page_up then
    return { local_action = "scroll_up" }
  end
  if bit.band(modifiers, glfw.mod_shift) ~= 0 and key == glfw.key_page_down then
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
