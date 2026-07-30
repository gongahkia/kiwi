local ordered = {}

local function is_finite_number(value)
  return value == value and value ~= math.huge and value ~= -math.huge
end

function ordered.sorted_keys(source)
  if type(source) ~= "table" then
    return nil, { code = "invalid_source", message = "expected table" }
  end

  local keys = {}
  for key in pairs(source) do
    local key_type = type(key)
    if key_type == "number" then
      if not is_finite_number(key) then
        return nil, { code = "unsupported_key", message = "numeric key must be finite" }
      end
    elseif key_type ~= "string" then
      return nil, { code = "unsupported_key_type", message = "keys must be numbers or strings" }
    end
    keys[#keys + 1] = key
  end

  table.sort(keys, function(left, right)
    local left_type = type(left)
    local right_type = type(right)
    if left_type ~= right_type then
      return left_type == "number"
    end
    return left < right
  end)
  return keys
end

return ordered
