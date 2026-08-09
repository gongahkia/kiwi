local Json = {}

local function escape(value)
  return value:gsub("[\\\"\b\f\n\r\t]", {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
  })
end

function Json.encode(value)
  local kind = type(value)
  if kind == "nil" then
    return "null"
  end
  if kind == "boolean" then
    return value and "true" or "false"
  end
  if kind == "number" then
    assert(value == value and value ~= math.huge and value ~= -math.huge, "JSON cannot encode non-finite numbers")
    return string.format("%.9g", value)
  end
  if kind == "string" then
    return "\"" .. escape(value) .. "\""
  end
  if kind ~= "table" then
    error("JSON cannot encode " .. kind)
  end

  local array = #value > 0
  if array then
    local items = {}
    for index = 1, #value do
      items[index] = Json.encode(value[index])
    end
    return "[" .. table.concat(items, ",") .. "]"
  end

  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  local items = {}
  for index, key in ipairs(keys) do
    items[index] = Json.encode(key) .. ":" .. Json.encode(value[key])
  end
  return "{" .. table.concat(items, ",") .. "}"
end

return Json
