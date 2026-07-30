local Errors = require("runtime.errors")

local Metadata = {}
local null = {}

Metadata.null = null
Metadata.contract = {
  encode = "encode(metadata) -> canonical_json_bytes | nil, error",
  null = "null sentinel for canonical JSON null",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
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

return Metadata
