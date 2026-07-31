local Errors = require("runtime.errors")

local Manifest = {}

Manifest.api_version = 1
Manifest.contract = {
  copy = "copy(manifest) -> effect_manifest",
  normalise = "normalise(manifest) -> effect_manifest | nil, error",
}

local capabilities = {
  cell_transform = true,
  draw_after = true,
  draw_before = true,
  interactive_time = true,
  persistent_canvas = true,
  post_process = true,
  row_transform = true,
  terminal_events = true,
}

local determinism = {
  deterministic = true,
  interactive = true,
  static = true,
}

local parameter_types = {
  boolean = true,
  enum = true,
  integer = true,
  number = true,
  string = true,
}

local function load_error(message, detail)
  return nil, Errors.new("effect_load_error", message, detail)
end

local function finite_number(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function integer(value)
  return finite_number(value) and value % 1 == 0
end

local function scalar(value)
  if type(value) == "string" or type(value) == "boolean" then
    return true
  end
  return finite_number(value)
end

local function dense_array(value, name)
  if type(value) ~= "table" then
    return load_error(name .. " must be an array")
  end
  local length = #value
  for key in pairs(value) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
      return load_error(name .. " must be a dense array")
    end
  end
  return length
end

local function valid_semver(value)
  if type(value) ~= "string" or #value == 0 or #value > 32 then
    return nil
  end
  local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
  if not major then
    return nil
  end
  for _, component in ipairs({ major, minor, patch }) do
    if #component > 1 and component:sub(1, 1) == "0" then
      return nil
    end
  end
  return true
end

local function copy_parameter(schema)
  local result = { default = schema.default, type = schema.type }
  if schema.min ~= nil then
    result.min = schema.min
  end
  if schema.max ~= nil then
    result.max = schema.max
  end
  if schema.max_length ~= nil then
    result.max_length = schema.max_length
  end
  if schema.values ~= nil then
    result.values = {}
    for index, value in ipairs(schema.values) do
      result.values[index] = value
    end
  end
  return result
end

function Manifest.copy(manifest)
  local copy = {
    api_version = manifest.api_version,
    capabilities = {},
    determinism = manifest.determinism,
    id = manifest.id,
    parameters = {},
    version = manifest.version,
  }
  for index, capability in ipairs(manifest.capabilities) do
    copy.capabilities[index] = capability
  end
  for name, schema in pairs(manifest.parameters) do
    copy.parameters[name] = copy_parameter(schema)
  end
  return copy
end

local function no_unknown_fields(value, allowed, name)
  for field in pairs(value) do
    if not allowed[field] then
      return load_error(name .. " contains an unsupported field", { field = field })
    end
  end
  return true
end

local function number_schema(schema, name, integer_only)
  local allowed = { default = true, max = true, min = true, type = true }
  local accepted, accepted_error = no_unknown_fields(schema, allowed, "effect parameter " .. name)
  if not accepted then
    return nil, accepted_error
  end
  local valid = integer_only and integer or finite_number
  if not valid(schema.default) then
    return load_error("effect parameter " .. name .. " default is invalid")
  end
  if schema.min ~= nil and not valid(schema.min) then
    return load_error("effect parameter " .. name .. " minimum is invalid")
  end
  if schema.max ~= nil and not valid(schema.max) then
    return load_error("effect parameter " .. name .. " maximum is invalid")
  end
  if schema.min ~= nil and schema.max ~= nil and schema.min > schema.max then
    return load_error("effect parameter " .. name .. " minimum exceeds maximum")
  end
  if
    (schema.min ~= nil and schema.default < schema.min)
    or (schema.max ~= nil and schema.default > schema.max)
  then
    return load_error("effect parameter " .. name .. " default is outside bounds")
  end
  return copy_parameter(schema)
end

local function boolean_schema(schema, name)
  local accepted, accepted_error =
    no_unknown_fields(schema, { default = true, type = true }, "effect parameter " .. name)
  if not accepted then
    return nil, accepted_error
  end
  if type(schema.default) ~= "boolean" then
    return load_error("effect parameter " .. name .. " default is invalid")
  end
  return copy_parameter(schema)
end

local function string_schema(schema, name)
  local accepted, accepted_error = no_unknown_fields(
    schema,
    { default = true, max_length = true, type = true },
    "effect parameter " .. name
  )
  if not accepted then
    return nil, accepted_error
  end
  if type(schema.default) ~= "string" then
    return load_error("effect parameter " .. name .. " default is invalid")
  end
  if schema.max_length ~= nil then
    if not integer(schema.max_length) or schema.max_length < 0 or schema.max_length > 65536 then
      return load_error("effect parameter " .. name .. " maximum length is invalid")
    end
    if #schema.default > schema.max_length then
      return load_error("effect parameter " .. name .. " default exceeds maximum length")
    end
  end
  return copy_parameter(schema)
end

local function enum_schema(schema, name)
  local accepted, accepted_error = no_unknown_fields(
    schema,
    { default = true, type = true, values = true },
    "effect parameter " .. name
  )
  if not accepted then
    return nil, accepted_error
  end
  local length, length_error = dense_array(schema.values, "effect parameter " .. name .. " values")
  if not length then
    return nil, length_error
  end
  if length == 0 or length > 256 then
    return load_error("effect parameter " .. name .. " values length is invalid")
  end
  if not scalar(schema.default) then
    return load_error("effect parameter " .. name .. " default is invalid")
  end
  local found = false
  local seen = {}
  for _, value in ipairs(schema.values) do
    if not scalar(value) then
      return load_error("effect parameter " .. name .. " enum value is invalid")
    end
    local key = type(value) .. "\0" .. tostring(value)
    if seen[key] then
      return load_error("effect parameter " .. name .. " enum values must be unique")
    end
    seen[key] = true
    if value == schema.default then
      found = true
    end
  end
  if not found then
    return load_error("effect parameter " .. name .. " default is not an enum value")
  end
  return copy_parameter(schema)
end

local function parameter_schema(name, schema)
  if type(name) ~= "string" or name == "" or #name > 64 then
    return load_error(
      "effect parameter name must be a non-empty bounded string",
      { provided = name }
    )
  end
  if
    type(schema) ~= "table"
    or type(schema.type) ~= "string"
    or not parameter_types[schema.type]
  then
    return load_error("effect parameter " .. name .. " type is unsupported")
  end
  if schema.type == "number" then
    return number_schema(schema, name, false)
  end
  if schema.type == "integer" then
    return number_schema(schema, name, true)
  end
  if schema.type == "boolean" then
    return boolean_schema(schema, name)
  end
  if schema.type == "string" then
    return string_schema(schema, name)
  end
  return enum_schema(schema, name)
end

function Manifest.normalise(manifest)
  if type(manifest) ~= "table" then
    return load_error("effect manifest must be a table")
  end
  local accepted, accepted_error = no_unknown_fields(manifest, {
    api_version = true,
    capabilities = true,
    determinism = true,
    id = true,
    parameters = true,
    version = true,
  }, "effect manifest")
  if not accepted then
    return nil, accepted_error
  end
  if type(manifest.id) ~= "string" or manifest.id == "" or #manifest.id > 128 then
    return load_error("effect manifest requires a non-empty bounded id")
  end
  if not valid_semver(manifest.version) then
    return load_error("effect manifest version must be canonical stable SemVer")
  end
  if manifest.api_version ~= Manifest.api_version then
    return load_error(
      "effect manifest API version is unsupported",
      { provided = manifest.api_version }
    )
  end
  if type(manifest.determinism) ~= "string" or not determinism[manifest.determinism] then
    return load_error("effect manifest determinism is unsupported")
  end
  local capability_length, capability_error =
    dense_array(manifest.capabilities, "effect manifest capabilities")
  if not capability_length then
    return nil, capability_error
  end
  if capability_length > 16 then
    return load_error("effect manifest has too many capabilities")
  end
  local normalised = {
    api_version = Manifest.api_version,
    capabilities = {},
    determinism = manifest.determinism,
    id = manifest.id,
    parameters = {},
    version = manifest.version,
  }
  local seen_capabilities = {}
  for index, capability in ipairs(manifest.capabilities) do
    if type(capability) ~= "string" or not capabilities[capability] then
      return load_error("effect manifest capability is unsupported", { provided = capability })
    end
    if seen_capabilities[capability] then
      return load_error("effect manifest capabilities must be unique", { provided = capability })
    end
    seen_capabilities[capability] = true
    normalised.capabilities[index] = capability
  end
  if seen_capabilities.interactive_time and manifest.determinism ~= "interactive" then
    return load_error("interactive time requires interactive determinism")
  end
  if type(manifest.parameters) ~= "table" then
    return load_error("effect manifest parameters must be a table")
  end
  local count = 0
  for name, schema in pairs(manifest.parameters) do
    count = count + 1
    if count > 64 then
      return load_error("effect manifest has too many parameters")
    end
    local normalised_schema, schema_error = parameter_schema(name, schema)
    if not normalised_schema then
      return nil, schema_error
    end
    normalised.parameters[name] = normalised_schema
  end
  return normalised
end

return Manifest
