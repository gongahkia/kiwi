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
