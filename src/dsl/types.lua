local ordered = require("src.util.ordered")

local types = {}
local type_values = setmetatable({}, { __mode = "k" })
local list_values = setmetatable({}, { __mode = "k" })
local definition_values = setmetatable({}, { __mode = "k" })

local function immutable_proxy(values, message)
  return setmetatable({}, {
    __index = values,
    __newindex = function()
      error(message, 2)
    end,
    __metatable = message,
  })
end

local function is_type(value)
  return type_values[value] ~= nil
end

local function immutable_list(items)
  local values = {}
  for index = 1, #items do
    values[index] = items[index]
  end
  return immutable_proxy(values, "immutable DSL type list")
end

local function immutable_type(values)
  local value = immutable_proxy(values, "immutable DSL type")
  type_values[value] = values
  return value
end

local function atomic_type(kind, name)
  return immutable_type({ kind = kind, name = name })
end

local function union_definition(name, arity, constructors)
  local value = immutable_proxy({ name = name, arity = arity }, "immutable DSL union definition")
  definition_values[value] = { constructors = constructors }
  return value
end

local primitives = {
  Bool = atomic_type("primitive", "Bool"),
  Float = atomic_type("primitive", "Float"),
  Int = atomic_type("primitive", "Int"),
  String = atomic_type("primitive", "String"),
  Unit = atomic_type("primitive", "Unit"),
}

local domains = {
  Angle = atomic_type("domain", "Angle"),
  Direction = atomic_type("domain", "Direction"),
  Distance = atomic_type("domain", "Distance"),
  Duration = atomic_type("domain", "Duration"),
  EntityId = atomic_type("domain", "EntityId"),
  HealthRatio = atomic_type("domain", "HealthRatio"),
  Position = atomic_type("domain", "Position"),
  Probability = atomic_type("domain", "Probability"),
  Region = atomic_type("domain", "Region"),
  Speed = atomic_type("domain", "Speed"),
  ThreatScore = atomic_type("domain", "ThreatScore"),
}

local quantity_units = {
  deg = domains.Angle,
  m = domains.Distance,
  ms = domains.Duration,
}

local definitions = {
  ContactClass = union_definition(
    "ContactClass",
    0,
    { "Unknown", "Civilian", "Hostile", "Friendly" }
  ),
  Option = union_definition("Option", 1, { "None", "Some" }),
  Result = union_definition("Result", 2, { "Err", "Ok" }),
  Stance = union_definition("Stance", 0, { "Standing", "Crouched", "Prone" }),
  Urgency = union_definition("Urgency", 0, { "Low", "Normal", "High", "Critical" }),
}

local named_unions = {}

local function validate_arguments(definition, arguments)
  if type(arguments) ~= "table" then
    return nil, { code = "invalid_union_arguments", message = "union arguments must be a list" }
  end
  local keys, err = ordered.sorted_keys(arguments)
  if not keys then
    return nil, err
  end
  if #keys ~= definition.arity then
    return nil, { code = "invalid_union_arity", message = "incorrect union type argument count" }
  end
  local copied = {}
  for index = 1, definition.arity do
    if keys[index] ~= index or not is_type(arguments[index]) then
      return nil,
        { code = "invalid_union_argument_type", message = "union arguments must be DSL types" }
    end
    copied[index] = arguments[index]
  end
  return copied
end

function types.is_type(value)
  return is_type(value)
end

function types.get(name)
  if type(name) ~= "string" then
    return nil, { code = "invalid_type_name", message = "type name must be a string" }
  end
  local value = primitives[name] or domains[name] or named_unions[name]
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

function types.function_type(argument, result)
  if not is_type(argument) then
    return nil,
      { code = "invalid_function_argument_type", message = "function argument must be a DSL type" }
  end
  if not is_type(result) then
    return nil,
      { code = "invalid_function_result_type", message = "function result must be a DSL type" }
  end
  return immutable_type({ kind = "function", argument = argument, result = result })
end

function types.union_type(name, arguments)
  local definition = definitions[name]
  if not definition then
    return nil, { code = "unknown_union_type", message = "unknown union type " .. tostring(name) }
  end
  local copied, err = validate_arguments(definition, arguments)
  if not copied then
    return nil, err
  end
  return immutable_type({
    kind = "union",
    definition = definition,
    arguments = immutable_list(copied),
  })
end

for _, name in ipairs({ "ContactClass", "Stance", "Urgency" }) do
  named_unions[name] = assert(types.union_type(name, {}))
end

function types.constructors(value)
  if not is_type(value) or value.kind ~= "union" then
    return nil, { code = "invalid_union_type", message = "expected union type" }
  end
  local definition = definition_values[value.definition]
  local constructors = {}
  for index = 1, #definition.constructors do
    constructors[index] = definition.constructors[index]
  end
  return constructors
end

local function types_equal(left, right)
  if left == right then
    return true
  end
  if left.kind ~= right.kind then
    return false
  end
  if left.kind == "function" then
    return types_equal(left.argument, right.argument) and types_equal(left.result, right.result)
  end
  if left.kind == "union" then
    if left.definition ~= right.definition then
      return false
    end
    for index = 1, left.definition.arity do
      if not types_equal(left.arguments[index], right.arguments[index]) then
        return false
      end
    end
    return true
  end
  return left.name == right.name
end

function types.equals(left, right)
  if not is_type(left) or not is_type(right) then
    return nil, { code = "invalid_type", message = "expected registered DSL types" }
  end
  return types_equal(left, right)
end

local function describe_type(value)
  if value.kind == "function" then
    local argument = describe_type(value.argument)
    if value.argument.kind == "function" then
      argument = "(" .. argument .. ")"
    end
    return argument .. " -> " .. describe_type(value.result)
  end
  if value.kind == "union" then
    local output = { value.definition.name }
    for index = 1, value.definition.arity do
      output[#output + 1] = describe_type(value.arguments[index])
    end
    return table.concat(output, " ")
  end
  return value.name
end

function types.describe(value)
  if not is_type(value) then
    return nil, { code = "invalid_type", message = "expected registered DSL type" }
  end
  return describe_type(value)
end

return types
