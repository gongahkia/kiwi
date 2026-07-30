local Errors = require("runtime.errors")

local Binary = {}

Binary.contract = {
  read_u8 = "read_u8(bytes, offset?) -> value, next_offset | nil, error",
  read_u16 = "read_u16(bytes, offset?) -> value, next_offset | nil, error",
  read_u32 = "read_u32(bytes, offset?) -> value, next_offset | nil, error",
  u8 = "u8(value) -> bytes | nil, error",
  u16 = "u16(value) -> bytes | nil, error",
  u32 = "u32(value) -> bytes | nil, error",
}

local limits = {
  u8 = 0xFF,
  u16 = 0xFFFF,
  u32 = 0xFFFFFFFF,
}

local function unsigned(value, name)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > limits[name] then
    return nil,
      Errors.new(
        "config_error",
        name .. " value must be an unsigned integer in range",
        { provided = value }
      )
  end
  return value
end

local function offset_value(offset)
  local actual = offset or 1
  if type(actual) ~= "number" or actual % 1 ~= 0 or actual < 1 then
    return nil,
      Errors.new("config_error", "binary offset must be a positive integer", { provided = offset })
  end
  return actual
end

local function read(bytes, offset, width, name)
  if type(bytes) ~= "string" then
    return nil, Errors.new("config_error", "binary input must be bytes", { provided = bytes })
  end
  local start, offset_error = offset_value(offset)
  if not start then
    return nil, offset_error
  end
  if start + width - 1 > #bytes then
    return nil,
      Errors.new("recording_corrupt", "truncated " .. name, {
        available = math.max(0, #bytes - start + 1),
        offset = start,
      })
  end
  return start
end

function Binary.u8(value)
  local actual, value_error = unsigned(value, "u8")
  if not actual then
    return nil, value_error
  end
  return string.char(actual)
end

function Binary.u16(value)
  local actual, value_error = unsigned(value, "u16")
  if not actual then
    return nil, value_error
  end
  return string.char(math.floor(actual / 0x100), actual % 0x100)
end

function Binary.u32(value)
  local actual, value_error = unsigned(value, "u32")
  if not actual then
    return nil, value_error
  end
  return string.char(
    math.floor(actual / 0x1000000) % 0x100,
    math.floor(actual / 0x10000) % 0x100,
    math.floor(actual / 0x100) % 0x100,
    actual % 0x100
  )
end

function Binary.read_u8(bytes, offset)
  local start, read_error = read(bytes, offset, 1, "u8")
  if not start then
    return nil, read_error
  end
  return bytes:byte(start), start + 1
end

function Binary.read_u16(bytes, offset)
  local start, read_error = read(bytes, offset, 2, "u16")
  if not start then
    return nil, read_error
  end
  return bytes:byte(start) * 0x100 + bytes:byte(start + 1), start + 2
end

function Binary.read_u32(bytes, offset)
  local start, read_error = read(bytes, offset, 4, "u32")
  if not start then
    return nil, read_error
  end
  return bytes:byte(start) * 0x1000000
    + bytes:byte(start + 1) * 0x10000
    + bytes:byte(start + 2) * 0x100
    + bytes:byte(start + 3),
    start + 4
end

return Binary
