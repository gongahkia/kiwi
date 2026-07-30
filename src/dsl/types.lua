local types = {}
local type_values = setmetatable({}, { __mode = "k" })

local function immutable_type(kind, name)
  local values = { kind = kind, name = name }
  local value = setmetatable({}, {
    __index = values,
    __newindex = function()
      error("DSL types are immutable", 2)
    end,
    __metatable = "immutable DSL type",
  })
  type_values[value] = values
  return value
end

local primitives = {
  Bool = immutable_type("primitive", "Bool"),
  Float = immutable_type("primitive", "Float"),
  Int = immutable_type("primitive", "Int"),
  String = immutable_type("primitive", "String"),
  Unit = immutable_type("primitive", "Unit"),
}

local domains = {
  Angle = immutable_type("domain", "Angle"),
  Direction = immutable_type("domain", "Direction"),
  Distance = immutable_type("domain", "Distance"),
  Duration = immutable_type("domain", "Duration"),
  EntityId = immutable_type("domain", "EntityId"),
  HealthRatio = immutable_type("domain", "HealthRatio"),
  Position = immutable_type("domain", "Position"),
  Probability = immutable_type("domain", "Probability"),
  Region = immutable_type("domain", "Region"),
  Speed = immutable_type("domain", "Speed"),
  ThreatScore = immutable_type("domain", "ThreatScore"),
}

local quantity_units = {
  deg = domains.Angle,
  m = domains.Distance,
  ms = domains.Duration,
}

function types.is_type(value)
  return type_values[value] ~= nil
end

function types.get(name)
  if type(name) ~= "string" then
    return nil, { code = "invalid_type_name", message = "type name must be a string" }
  end
  local value = primitives[name] or domains[name]
  if not value then
    return nil, { code = "unknown_type", message = "unknown type " .. name }
  end
  return value
end

function types.quantity_type(unit)
  if type(unit) ~= "string" then
    return nil, { code = "invalid_quantity_unit", message = "quantity unit must be a string" }
  end
  local value = quantity_units[unit]
  if not value then
    return nil, { code = "unknown_quantity_unit", message = "unknown quantity unit " .. unit }
  end
  return value
end

function types.equals(left, right)
  if not types.is_type(left) or not types.is_type(right) then
    return nil, { code = "invalid_type", message = "expected registered DSL types" }
  end
  return left == right
end

function types.describe(value)
  if not types.is_type(value) then
    return nil, { code = "invalid_type", message = "expected registered DSL type" }
  end
  return value.name
end

return types
