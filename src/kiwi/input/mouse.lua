local bit = require("bit")
local Utf8 = require("kiwi.terminal.utf8")

local Mouse = {}
Mouse.__index = Mouse

local button_codes = { [0] = 0, [1] = 2, [2] = 1 }
local modifier_codes = {
  shift = 4,
  alt = 8,
  control = 16,
}

local function modifier_code(modifiers)
  local result = 0
  if bit.band(modifiers or 0, 0x0001) ~= 0 then result = result + modifier_codes.shift end
  if bit.band(modifiers or 0, 0x0004) ~= 0 then result = result + modifier_codes.alt end
  if bit.band(modifiers or 0, 0x0002) ~= 0 then result = result + modifier_codes.control end
  return result
end

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function sgr(code, column, row, release)
  return string.format("\27[<%d;%d;%d%s", code, column, row, release and "m" or "M")
end

local function tracking_mode(modes)
  local mode = modes and modes.mouse_tracking
  if mode == "x10" or mode == "normal" or mode == "button" or mode == "any" then return mode end
  return "none"
end

local function protocol(modes)
  local value = modes and modes.mouse_protocol
  if value == "x10" or value == "utf8" or value == "sgr" or value == "urxvt" then return value end
  return modes and modes.mouse_sgr and "sgr" or "x10"
end

local function valid_position(column, row, encoding)
  local maximum = encoding == "x10" and 223 or encoding == "utf8" and 2015 or 65535
  return type(column) == "number" and column % 1 == 0 and column >= 1 and column <= maximum
    and type(row) == "number" and row % 1 == 0 and row >= 1 and row <= maximum
end

local function encode(encoding, code, column, row, release)
  if encoding == "sgr" then return sgr(code, column, row, release) end
  if release then code = bit.band(code, 28) + 3 end
  if encoding == "urxvt" then return string.format("\27[%d;%d;%dM", code + 32, column, row) end
  if encoding == "utf8" then return "\27[M" .. string.char(code + 32) .. Utf8.encode(column + 32) .. Utf8.encode(row + 32) end
  return "\27[M" .. string.char(code + 32, column + 32, row + 32)
end

function Mouse.new()
  return setmetatable({ buttons = {}, last_column = nil, last_row = nil }, Mouse)
end

function Mouse:reset()
  self.buttons = {}
  self.last_column = nil
  self.last_row = nil
end

function Mouse:enabled(modes)
  return modes and tracking_mode(modes) ~= "none"
end

function Mouse:button(event, modes)
  local code = button_codes[event.button]
  if code == nil or (event.action ~= "press" and event.action ~= "release") then return nil end
  if event.action == "press" then self.buttons[event.button] = true else self.buttons[event.button] = nil end
  self.last_column = nil
  self.last_row = nil
  local encoding = protocol(modes)
  if not self:enabled(modes) or not valid_position(event.column, event.row, encoding) then return nil end
  if tracking_mode(modes) == "x10" and event.action == "release" then return nil end
  return encode(encoding, code + modifier_code(event.modifiers), event.column, event.row, event.action == "release")
end

function Mouse:motion(event, modes)
  local tracking = tracking_mode(modes)
  local encoding = protocol(modes)
  if not self:enabled(modes) or tracking == "x10" or tracking == "normal" or not valid_position(event.column, event.row, encoding) then return nil end
  if self.last_column == event.column and self.last_row == event.row then return nil end
  local button
  for index = 0, 2 do
    if self.buttons[index] then
      button = button_codes[index]
      break
    end
  end
  if tracking == "button" and button == nil then return nil end
  self.last_column = event.column
  self.last_row = event.row
  return encode(encoding, 32 + (button or 3) + modifier_code(event.modifiers), event.column, event.row, false)
end

function Mouse:wheel(event, modes)
  local encoding = protocol(modes)
  if not self:enabled(modes) or not valid_position(event.column, event.row, encoding) or not finite_number(event.delta) or event.delta == 0 then return nil end
  local count = math.min(16, math.max(1, math.floor(math.abs(event.delta) + 0.5)))
  local report = encode(encoding, (event.delta > 0 and 64 or 65) + modifier_code(event.modifiers), event.column, event.row, false)
  return string.rep(report, count)
end

function Mouse:focus(focused, modes)
  if not focused then self:reset() end
  if not modes or modes.focus_reporting ~= true then return nil end
  return focused and "\27[I" or "\27[O"
end

return Mouse
