local Binary = require("recording.binary")
local Errors = require("runtime.errors")
local Format = require("recording.format")

local Inspect = {}

Inspect.contract = {
  escape_bytes = "escape_bytes(bytes, maximum?) -> display | nil, error",
  frame_line = "frame_line(index, elapsed_us, frame) -> line | nil, error",
}

local names = {
  [Format.kinds.OUTPUT] = "output",
  [Format.kinds.INPUT] = "input",
  [Format.kinds.RESIZE] = "resize",
  [Format.kinds.MARK] = "mark",
  [Format.kinds.CHECKPOINT] = "checkpoint",
  [Format.kinds.STATUS] = "status",
  [Format.kinds.EXIT] = "exit",
  [Format.kinds.CLOCK_ADVANCE] = "clock_advance",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function valid_nonnegative_integer(value, name)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 0 then
    return config_error(name .. " must be a non-negative integer", { provided = value })
  end
  return value
end

local function decimal_add_u32(value, amount)
  local digits = {}
  local carry = amount
  for index = #value, 1, -1 do
    local digit = value:byte(index) - string.byte("0")
    local addend = carry % 10
    carry = math.floor(carry / 10)
    local total = digit + addend
    if total >= 10 then
      total = total - 10
      carry = carry + 1
    end
    digits[index] = string.char(string.byte("0") + total)
  end
  while carry > 0 do
    table.insert(digits, 1, string.char(string.byte("0") + carry % 10))
    carry = math.floor(carry / 10)
  end
  return table.concat(digits)
end

local function frame_name(kind)
  return names[kind] or string.format("unknown_0x%02x", kind)
end

local function resize_summary(payload)
  if #payload ~= 16 then
    return "resize bytes=" .. #payload
  end
  local columns, offset = Binary.read_u32(payload)
  local rows
  rows, offset = Binary.read_u32(payload, offset)
  local pixel_width
  pixel_width, offset = Binary.read_u32(payload, offset)
  local pixel_height = Binary.read_u32(payload, offset)
  return string.format(
    "resize columns=%d rows=%d pixel_width=%d pixel_height=%d",
    columns,
    rows,
    pixel_width,
    pixel_height
  )
end

function Inspect.escape_bytes(bytes, maximum)
  if type(bytes) ~= "string" then
    return config_error("inspection bytes must be a string", { provided = bytes })
  end
  local limit = maximum or 64
  local valid_limit, limit_error = valid_nonnegative_integer(limit, "inspection byte limit")
  if not valid_limit then
    return nil, limit_error
  end
  local pieces = { '"' }
  local final = math.min(#bytes, valid_limit)
  for index = 1, final do
    local byte = bytes:byte(index)
    if byte == string.byte("\\") then
      pieces[#pieces + 1] = "\\\\"
    elseif byte == string.byte('"') then
      pieces[#pieces + 1] = '\\"'
    elseif byte >= 0x20 and byte <= 0x7E then
      pieces[#pieces + 1] = string.char(byte)
    else
      pieces[#pieces + 1] = string.format("\\x%02x", byte)
    end
  end
  pieces[#pieces + 1] = '"'
  if final < #bytes then
    pieces[#pieces + 1] = "..."
  end
  return table.concat(pieces)
end

function Inspect.frame_line(index, elapsed_us, frame)
  local valid_index, index_error = valid_nonnegative_integer(index, "frame index")
  if not valid_index then
    return nil, index_error
  end
  if type(elapsed_us) ~= "string" or not elapsed_us:match("^%d+$") then
    return config_error("elapsed terminal time must be decimal digits", { provided = elapsed_us })
  end
  if type(frame) ~= "table" then
    return config_error("inspection frame must be a table")
  end
  local kind, kind_error = valid_nonnegative_integer(frame.kind, "frame kind")
  if not kind or kind > 0xFF then
    return nil, kind_error or Errors.new("config_error", "frame kind exceeds one byte")
  end
  local delta_us, delta_error = valid_nonnegative_integer(frame.delta_us, "frame delta_us")
  if not delta_us or delta_us > 0xFFFFFFFF then
    return nil, delta_error or Errors.new("config_error", "frame delta_us exceeds u32")
  end
  if type(frame.payload) ~= "string" then
    return config_error("inspection frame payload must be bytes")
  end
  local elapsed = decimal_add_u32(elapsed_us, delta_us)
  local prefix = string.format("%d elapsed_us=%s delta_us=%d ", valid_index, elapsed, delta_us)
  if kind == Format.kinds.OUTPUT or kind == Format.kinds.INPUT then
    local display, display_error = Inspect.escape_bytes(frame.payload)
    if not display then
      return nil, display_error
    end
    return prefix .. frame_name(kind) .. " bytes=" .. #frame.payload .. " data=" .. display, elapsed
  end
  if kind == Format.kinds.RESIZE then
    return prefix .. resize_summary(frame.payload), elapsed
  end
  return prefix .. frame_name(kind) .. " bytes=" .. #frame.payload, elapsed
end

return Inspect
