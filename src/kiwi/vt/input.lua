-- Host-neutral input adapter. A host supplies symbolic keys and button events;
-- this module emits only terminal bytes or a local-action token for the host
-- to decide how to handle.
local Keyboard = require("kiwi.input.keyboard")
local Mouse = require("kiwi.input.mouse")

local Input = {
  api_version = 1,
  actions = { press = "press", release = "release", repeat_key = "repeat" },
  modifiers = { shift = 0x0001, control = 0x0002, alt = 0x0004, super = 0x0008 },
}

local keyboard = {
  press = 1,
  release = 0,
  repeat_action = 2,
  mod_shift = Input.modifiers.shift,
  mod_control = Input.modifiers.control,
  mod_alt = Input.modifiers.alt,
  mod_super = Input.modifiers.super,
  key_escape = 256,
  key_enter = 257,
  key_tab = 258,
  key_backspace = 259,
  key_insert = 260,
  key_delete = 261,
  key_right = 262,
  key_left = 263,
  key_down = 264,
  key_up = 265,
  key_page_up = 266,
  key_page_down = 267,
  key_home = 268,
  key_end = 269,
  key_f1 = 290,
  key_f2 = 291,
  key_f3 = 292,
  key_f4 = 293,
  key_f5 = 294,
  key_f6 = 295,
  key_f7 = 296,
  key_f8 = 297,
  key_f9 = 298,
  key_f10 = 299,
  key_f11 = 300,
  key_f12 = 301,
  key_kp_0 = 320,
  key_kp_1 = 321,
  key_kp_2 = 322,
  key_kp_3 = 323,
  key_kp_4 = 324,
  key_kp_5 = 325,
  key_kp_6 = 326,
  key_kp_7 = 327,
  key_kp_8 = 328,
  key_kp_9 = 329,
  key_kp_decimal = 330,
  key_kp_divide = 331,
  key_kp_multiply = 332,
  key_kp_subtract = 333,
  key_kp_add = 334,
  key_kp_enter = 335,
  key_kp_equal = 336,
}

local named_keys = {
  escape = keyboard.key_escape,
  enter = keyboard.key_enter,
  tab = keyboard.key_tab,
  backspace = keyboard.key_backspace,
  insert = keyboard.key_insert,
  delete = keyboard.key_delete,
  right = keyboard.key_right,
  left = keyboard.key_left,
  down = keyboard.key_down,
  up = keyboard.key_up,
  page_up = keyboard.key_page_up,
  page_down = keyboard.key_page_down,
  home = keyboard.key_home,
  ["end"] = keyboard.key_end,
}
for index = 1, 12 do named_keys["f" .. index] = keyboard["key_f" .. index] end
for index = 0, 9 do named_keys["kp_" .. index] = keyboard["key_kp_" .. index] end
for _, name in ipairs({ "decimal", "divide", "multiply", "subtract", "add", "enter", "equal" }) do
  named_keys["kp_" .. name] = keyboard["key_kp_" .. name]
end

local actions = {
  press = keyboard.press,
  release = keyboard.release,
  repeat_key = keyboard.repeat_action,
}

local function key_code(value)
  if type(value) == "number" and value % 1 == 0 and value >= 0 then return value end
  if type(value) ~= "string" then return nil end
  if #value == 1 then return value:byte() end
  return named_keys[value]
end

local function key_variant(value, name)
  if value == nil then return nil end
  assert(type(value) == "number" and value % 1 == 0 and value >= 0x20 and value <= 0x10ffff and not (value >= 0xd800 and value <= 0xdfff) and not (value >= 0x7f and value <= 0x9f), name .. " must be a non-control Unicode scalar")
  return value
end

function Input.text(codepoint, modes)
  assert(type(codepoint) == "number" and codepoint % 1 == 0 and codepoint >= 0 and codepoint <= 0x10ffff, "input text needs a Unicode scalar")
  return Keyboard.text(codepoint, modes or {})
end

function Input.key(event, modes)
  assert(type(event) == "table", "input key event must be a table")
  local key = key_code(event.key)
  local action = actions[event.action]
  assert(key ~= nil, "input key is unknown")
  assert(action ~= nil, "input key action is invalid")
  local modifiers = event.modifiers or 0
  assert(type(modifiers) == "number" and modifiers % 1 == 0 and modifiers >= 0, "input key modifiers must be a non-negative integer")
  if event.associated_text ~= nil then assert(type(event.associated_text) == "table", "input associated key text must be a table") end
  return Keyboard.key(key, action, modifiers, modes or {}, keyboard, {
    associated_text = event.associated_text,
    layout_key = key_variant(event.layout_key, "input layout key"),
    shifted_key = key_variant(event.shifted_key, "input shifted key"),
    base_key = key_variant(event.base_key, "input base key"),
  })
end

function Input.new_mouse()
  return Mouse.new()
end

function Input.paste(bytes, modes)
  assert(type(bytes) == "string", "input paste needs a byte string")
  if modes and modes.bracketed_paste then return "\27[200~" .. bytes .. "\27[201~" end
  return bytes
end

return Input
