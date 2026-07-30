local Errors = require("runtime.errors")

local Metadata = {}
local null = {}

Metadata.null = null
Metadata.contract = {
  decode = "decode(canonical_json_bytes) -> metadata | nil, error",
  encode = "encode(metadata) -> canonical_json_bytes | nil, error",
  null = "null sentinel for canonical JSON null",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function corrupt_error(message, detail)
  return nil, Errors.new("recording_corrupt", message, detail)
end

local function continuation(byte)
  return byte ~= nil and byte >= 0x80 and byte <= 0xBF
end

local function in_range(byte, minimum, maximum)
  return byte ~= nil and byte >= minimum and byte <= maximum
end

local function valid_utf8(bytes)
  local index = 1
  while index <= #bytes do
    local first = bytes:byte(index)
    if first <= 0x7F then
      index = index + 1
    elseif first >= 0xC2 and first <= 0xDF and continuation(bytes:byte(index + 1)) then
      index = index + 2
    elseif
      first == 0xE0
      and in_range(bytes:byte(index + 1), 0xA0, 0xBF)
      and continuation(bytes:byte(index + 2))
    then
      index = index + 3
    elseif
      (first >= 0xE1 and first <= 0xEC or first >= 0xEE and first <= 0xEF)
      and continuation(bytes:byte(index + 1))
      and continuation(bytes:byte(index + 2))
    then
      index = index + 3
    elseif
      first == 0xED
      and in_range(bytes:byte(index + 1), 0x80, 0x9F)
      and continuation(bytes:byte(index + 2))
    then
      index = index + 3
    elseif
      first == 0xF0
      and in_range(bytes:byte(index + 1), 0x90, 0xBF)
      and continuation(bytes:byte(index + 2))
      and continuation(bytes:byte(index + 3))
    then
      index = index + 4
    elseif
      (first >= 0xF1 and first <= 0xF3)
      and continuation(bytes:byte(index + 1))
      and continuation(bytes:byte(index + 2))
      and continuation(bytes:byte(index + 3))
    then
      index = index + 4
    elseif
      first == 0xF4
      and in_range(bytes:byte(index + 1), 0x80, 0x8F)
      and continuation(bytes:byte(index + 2))
      and continuation(bytes:byte(index + 3))
    then
      index = index + 4
    else
      return false
    end
  end
  return true
end

local function escape_string(value)
  if not valid_utf8(value) then
    return config_error("metadata strings must be valid UTF-8")
  end
  local encoded = { '"' }
  for index = 1, #value do
    local byte = value:byte(index)
    if byte == string.byte('"') or byte == string.byte("\\") then
      encoded[#encoded + 1] = "\\" .. string.char(byte)
    elseif byte == 0x08 then
      encoded[#encoded + 1] = "\\b"
    elseif byte == 0x09 then
      encoded[#encoded + 1] = "\\t"
    elseif byte == 0x0A then
      encoded[#encoded + 1] = "\\n"
    elseif byte == 0x0C then
      encoded[#encoded + 1] = "\\f"
    elseif byte == 0x0D then
      encoded[#encoded + 1] = "\\r"
    elseif byte < 0x20 then
      encoded[#encoded + 1] = string.format("\\u%04x", byte)
    else
      encoded[#encoded + 1] = string.char(byte)
    end
  end
  encoded[#encoded + 1] = '"'
  return table.concat(encoded)
end

local function object_keys(value)
  local keys = {}
  for key in pairs(value) do
    if type(key) ~= "string" or not key:match("^[A-Za-z][A-Za-z0-9_]*$") then
      return config_error("metadata object keys must be ASCII identifiers", { provided = key })
    end
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function encode_value(value, active, depth)
  if value == null then
    return "null"
  end
  if type(value) == "string" then
    return escape_string(value)
  end
  if type(value) == "boolean" then
    return tostring(value)
  end
  if type(value) == "number" then
    if value ~= value or value % 1 ~= 0 or value < -0x80000000 or value > 0x7FFFFFFF then
      return config_error("metadata numbers must be signed 32-bit integers", { provided = value })
    end
    return tostring(value)
  end
  if type(value) ~= "table" then
    return config_error("metadata value type is unsupported", { provided = type(value) })
  end
  if active[value] then
    return config_error("metadata objects must not contain cycles")
  end
  if depth >= 16 then
    return config_error("metadata nesting exceeds the bootstrap limit")
  end
  active[value] = true
  local keys, keys_error = object_keys(value)
  if not keys then
    active[value] = nil
    return nil, keys_error
  end
  local fields = {}
  for index, key in ipairs(keys) do
    local encoded_key, key_error = escape_string(key)
    if not encoded_key then
      active[value] = nil
      return nil, key_error
    end
    local encoded_value, value_error = encode_value(value[key], active, depth + 1)
    if not encoded_value then
      active[value] = nil
      return nil, value_error
    end
    fields[index] = encoded_key .. ":" .. encoded_value
  end
  active[value] = nil
  return "{" .. table.concat(fields, ",") .. "}"
end

function Metadata.encode(metadata)
  if type(metadata) ~= "table" or metadata == null then
    return config_error("metadata must be an object")
  end
  return encode_value(metadata, {}, 0)
end

local parse_value

local function parse_string(bytes, index)
  local decoded = {}
  while index <= #bytes do
    local byte = bytes:byte(index)
    if byte == string.byte('"') then
      local value = table.concat(decoded)
      if not valid_utf8(value) then
        return corrupt_error("metadata string is not valid UTF-8")
      end
      return value, index + 1
    end
    if byte < 0x20 then
      return corrupt_error("metadata string contains an unescaped control byte")
    end
    if byte ~= string.byte("\\") then
      decoded[#decoded + 1] = string.char(byte)
      index = index + 1
    else
      local escaped = bytes:byte(index + 1)
      if escaped == nil then
        return corrupt_error("metadata string escape is truncated")
      end
      if escaped == string.byte('"') or escaped == string.byte("\\") then
        decoded[#decoded + 1] = string.char(escaped)
        index = index + 2
      elseif escaped == string.byte("b") then
        decoded[#decoded + 1] = "\8"
        index = index + 2
      elseif escaped == string.byte("t") then
        decoded[#decoded + 1] = "\t"
        index = index + 2
      elseif escaped == string.byte("n") then
        decoded[#decoded + 1] = "\n"
        index = index + 2
      elseif escaped == string.byte("f") then
        decoded[#decoded + 1] = "\f"
        index = index + 2
      elseif escaped == string.byte("r") then
        decoded[#decoded + 1] = "\r"
        index = index + 2
      elseif escaped == string.byte("u") then
        local hex = bytes:sub(index + 2, index + 5)
        if #hex ~= 4 or not hex:match("^00[0-9a-f][0-9a-f]$") then
          return corrupt_error("metadata unicode escape is not canonical")
        end
        local value = tonumber(hex:sub(3), 16)
        if value > 0x1F then
          return corrupt_error("metadata unicode escape is outside the control range")
        end
        decoded[#decoded + 1] = string.char(value)
        index = index + 6
      else
        return corrupt_error("metadata string escape is invalid")
      end
    end
  end
  return corrupt_error("metadata string is truncated")
end

local function parse_number(bytes, index)
  local start = index
  if bytes:byte(index) == string.byte("-") then
    index = index + 1
  end
  local first = bytes:byte(index)
  if first == string.byte("0") then
    index = index + 1
    local next_byte = bytes:byte(index)
    if next_byte ~= nil and next_byte >= string.byte("0") and next_byte <= string.byte("9") then
      return corrupt_error("metadata numbers must not use leading zeroes")
    end
  elseif first ~= nil and first >= string.byte("1") and first <= string.byte("9") then
    index = index + 1
    while true do
      local digit = bytes:byte(index)
      if digit == nil or digit < string.byte("0") or digit > string.byte("9") then
        break
      end
      index = index + 1
    end
  else
    return corrupt_error("metadata number is invalid")
  end
  local value = tonumber(bytes:sub(start, index - 1))
  if value == nil or value < -0x80000000 or value > 0x7FFFFFFF then
    return corrupt_error("metadata number is outside the supported range")
  end
  return value, index
end

local function parse_object(bytes, index, depth)
  if depth >= 16 then
    return corrupt_error("metadata nesting exceeds the bootstrap limit")
  end
  local object = {}
  index = index + 1
  if bytes:byte(index) == string.byte("}") then
    return object, index + 1
  end
  while true do
    if bytes:byte(index) ~= string.byte('"') then
      return corrupt_error("metadata object key is invalid")
    end
    local key
    key, index = parse_string(bytes, index + 1)
    if not key then
      return nil, index
    end
    if not key:match("^[A-Za-z][A-Za-z0-9_]*$") then
      return corrupt_error("metadata object key is outside the bootstrap profile")
    end
    if object[key] ~= nil then
      return corrupt_error("metadata object contains duplicate keys")
    end
    if bytes:byte(index) ~= string.byte(":") then
      return corrupt_error("metadata object is missing a colon")
    end
    local value
    value, index = parse_value(bytes, index + 1, depth + 1)
    if value == nil then
      return nil, index
    end
    object[key] = value
    local separator = bytes:byte(index)
    if separator == string.byte("}") then
      return object, index + 1
    end
    if separator ~= string.byte(",") then
      return corrupt_error("metadata object is missing a separator")
    end
    index = index + 1
  end
end

function parse_value(bytes, index, depth)
  local byte = bytes:byte(index)
  if byte == string.byte('"') then
    return parse_string(bytes, index + 1)
  end
  if byte == string.byte("{") then
    return parse_object(bytes, index, depth)
  end
  if bytes:sub(index, index + 3) == "true" then
    return true, index + 4
  end
  if bytes:sub(index, index + 4) == "false" then
    return false, index + 5
  end
  if bytes:sub(index, index + 3) == "null" then
    return null, index + 4
  end
  return parse_number(bytes, index)
end

function Metadata.decode(bytes)
  if type(bytes) ~= "string" then
    return config_error("metadata input must be bytes", { provided = bytes })
  end
  if bytes:byte(1) ~= string.byte("{") then
    return corrupt_error("metadata root must be an object")
  end
  local metadata, index = parse_object(bytes, 1, 0)
  if not metadata then
    return nil, index
  end
  if index ~= #bytes + 1 then
    return corrupt_error("metadata has trailing bytes")
  end
  local canonical, canonical_error = Metadata.encode(metadata)
  if not canonical then
    return nil, canonical_error
  end
  if canonical ~= bytes then
    return corrupt_error("metadata is not canonical")
  end
  return metadata
end

return Metadata
