local serializer = { VERSION = 1 }

local function error_value(code, message)
  return { code = code, message = message }
end

local function is_finite(value)
  return value == value and value ~= math.huge and value ~= -math.huge
end

local function encode_string(value)
  local output = { '"' }
  for index = 1, #value do
    local byte = string.byte(value, index)
    if byte == 34 then
      output[#output + 1] = '\\"'
    elseif byte == 92 then
      output[#output + 1] = "\\\\"
    elseif byte == 8 then
      output[#output + 1] = "\\b"
    elseif byte == 9 then
      output[#output + 1] = "\\t"
    elseif byte == 10 then
      output[#output + 1] = "\\n"
    elseif byte == 12 then
      output[#output + 1] = "\\f"
    elseif byte == 13 then
      output[#output + 1] = "\\r"
    elseif byte < 32 then
      output[#output + 1] = string.format("\\u%04x", byte)
    else
      output[#output + 1] = string.char(byte)
    end
  end
  output[#output + 1] = '"'
  return table.concat(output)
end

local function encode_number(value)
  if not is_finite(value) then
    return nil, error_value("invalid_number", "numbers must be finite")
  end
  if value == 0 then
    return "0"
  end
  if value == math.floor(value) then
    return string.format("%.0f", value)
  end
  return string.format("%.17g", value):gsub("E", "e")
end

local function table_shape(value)
  local count = 0
  local max_index = 0
  local has_number_key = false
  local has_string_key = false
  for key in pairs(value) do
    local key_type = type(key)
    if key_type == "number" then
      if not is_finite(key) or key ~= math.floor(key) or key < 1 then
        return nil, error_value("invalid_table_shape", "array indices must be positive integers")
      end
      has_number_key = true
      if key > max_index then
        max_index = key
      end
    elseif key_type == "string" then
      has_string_key = true
    else
      return nil, error_value("unsupported_key_type", "table keys must be strings or array indices")
    end
    count = count + 1
  end
  if has_number_key then
    if has_string_key or max_index ~= count then
      return nil,
        error_value("invalid_table_shape", "tables must be contiguous arrays or string-keyed maps")
    end
    return "array", max_index
  end
  return "map"
end

local function encode_value(value, active, depth, max_depth)
  local value_type = type(value)
  if value_type == "nil" then
    return "null"
  end
  if value_type == "boolean" then
    return value and "true" or "false"
  end
  if value_type == "number" then
    return encode_number(value)
  end
  if value_type == "string" then
    return encode_string(value)
  end
  if value_type ~= "table" then
    return nil, error_value("unsupported_type", "cannot serialize " .. value_type)
  end
  if active[value] then
    return nil, error_value("cyclic_table", "cannot serialize cyclic table")
  end
  if depth >= max_depth then
    return nil, error_value("max_depth_exceeded", "serializer nesting limit exceeded")
  end

  active[value] = true
  local shape, length_or_error = table_shape(value)
  if not shape then
    active[value] = nil
    return nil, length_or_error
  end

  local output = {}
  if shape == "array" then
    for index = 1, length_or_error do
      local encoded, err = encode_value(value[index], active, depth + 1, max_depth)
      if not encoded then
        active[value] = nil
        return nil, err
      end
      output[#output + 1] = encoded
    end
    active[value] = nil
    return "[" .. table.concat(output, ",") .. "]"
  end

  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local encoded, err = encode_value(value[key], active, depth + 1, max_depth)
    if not encoded then
      active[value] = nil
      return nil, err
    end
    output[#output + 1] = encode_string(key) .. ":" .. encoded
  end
  active[value] = nil
  return "{" .. table.concat(output, ",") .. "}"
end

function serializer.encode(value, options)
  options = options or {}
  local max_depth = options.max_depth or 64
  if type(max_depth) ~= "number" or max_depth ~= math.floor(max_depth) or max_depth < 1 then
    return nil, error_value("invalid_max_depth", "max_depth must be a positive integer")
  end
  return encode_value(value, {}, 0, max_depth)
end

return serializer
