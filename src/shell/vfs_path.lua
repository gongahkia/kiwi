local Errors = require("runtime.errors")

local Path = {}

Path.contract = {
  normalise_limits = "normalise_limits(limits?) -> vfs_path_limits | nil, error",
  render = "render(components) -> canonical_path",
  resolve = "resolve(bytes, cwd_components, limits?) -> resolved_path | nil, error",
}

local default_limits = {
  max_canonical_path_bytes = 4096,
  max_component_bytes = 255,
  max_path_bytes = 4096,
  max_path_components = 64,
}

local allowed_limits = {
  max_canonical_path_bytes = true,
  max_component_bytes = true,
  max_path_bytes = true,
  max_path_components = true,
}

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function limit(value, name, default)
  if value == nil then
    return default
  end
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > default then
    return command_error(name .. " must be an integer within the supported bound", {
      limit = default,
      minimum = 1,
      provided = value,
    })
  end
  return value
end

function Path.normalise_limits(limits)
  if limits == nil then
    limits = {}
  end
  if type(limits) ~= "table" then
    return command_error("virtual filesystem path limits must be a table", {
      reason = "resource_limit",
    })
  end
  local has_unsupported_limit = false
  for name in pairs(limits) do
    if not allowed_limits[name] then
      has_unsupported_limit = true
    end
  end
  if has_unsupported_limit then
    return command_error("virtual filesystem path limit is unsupported", {
      reason = "resource_limit",
    })
  end
  local max_path_bytes, path_error = limit(
    limits.max_path_bytes,
    "virtual filesystem maximum path bytes",
    default_limits.max_path_bytes
  )
  if not max_path_bytes then
    return nil, path_error
  end
  local max_canonical_path_bytes, canonical_error = limit(
    limits.max_canonical_path_bytes,
    "virtual filesystem maximum canonical path bytes",
    default_limits.max_canonical_path_bytes
  )
  if not max_canonical_path_bytes then
    return nil, canonical_error
  end
  local max_component_bytes, component_error = limit(
    limits.max_component_bytes,
    "virtual filesystem maximum component bytes",
    default_limits.max_component_bytes
  )
  if not max_component_bytes then
    return nil, component_error
  end
  local max_path_components, components_error = limit(
    limits.max_path_components,
    "virtual filesystem maximum path components",
    default_limits.max_path_components
  )
  if not max_path_components then
    return nil, components_error
  end
  return {
    max_canonical_path_bytes = max_canonical_path_bytes,
    max_component_bytes = max_component_bytes,
    max_path_bytes = max_path_bytes,
    max_path_components = max_path_components,
  }
end

local function copy_components(components)
  local result = {}
  for index, component in ipairs(components) do
    result[index] = component:sub(1, #component)
  end
  return result
end

function Path.render(components)
  if #components == 0 then
    return "/"
  end
  return "/" .. table.concat(components, "/")
end

local function canonical_bytes(components)
  local total = 1
  for _, component in ipairs(components) do
    total = total + #component + 1
  end
  return total - 1
end

function Path.resolve(bytes, cwd_components, configuration)
  local limits, limits_error = Path.normalise_limits(configuration)
  if not limits then
    return nil, limits_error
  end
  if type(bytes) ~= "string" then
    return command_error("virtual filesystem path must be a byte string", {
      reason = "invalid_path_byte",
    })
  end
  if #bytes == 0 then
    return command_error("virtual filesystem path is empty", { reason = "empty_path" })
  end
  if #bytes > limits.max_path_bytes then
    return command_error("virtual filesystem path exceeds its byte limit", {
      limit = limits.max_path_bytes,
      reason = "path_too_large",
    })
  end
  if bytes:find("\0", 1, true) then
    return command_error("virtual filesystem path contains NUL", { reason = "invalid_path_byte" })
  end
  if type(cwd_components) ~= "table" then
    return command_error("virtual filesystem cwd components are invalid", { reason = "resource_limit" })
  end
  local absolute = bytes:byte(1) == 0x2F
  local components = absolute and {} or copy_components(cwd_components)
  local trailing_slash = #bytes > 1 and bytes:byte(#bytes) == 0x2F
  local index = 1
  while index <= #bytes do
    while index <= #bytes and bytes:byte(index) == 0x2F do
      index = index + 1
    end
    local start = index
    while index <= #bytes and bytes:byte(index) ~= 0x2F do
      index = index + 1
    end
    if start < index then
      local component = bytes:sub(start, index - 1)
      if #component > limits.max_component_bytes then
        return command_error("virtual filesystem component exceeds its byte limit", {
          limit = limits.max_component_bytes,
          reason = "component_too_large",
        })
      end
      if component == ".." then
        if #components > 0 then
          components[#components] = nil
        end
      elseif component ~= "." then
        if #components >= limits.max_path_components then
          return command_error("virtual filesystem path has too many components", {
            limit = limits.max_path_components,
            reason = "too_many_components",
          })
        end
        components[#components + 1] = component:sub(1, #component)
      end
    end
  end
  local canonical_path = Path.render(components)
  if #canonical_path > limits.max_canonical_path_bytes then
    return command_error("virtual filesystem canonical path exceeds its byte limit", {
      limit = limits.max_canonical_path_bytes,
      reason = "path_too_large",
    })
  end
  return {
    absolute = absolute,
    canonical_path = canonical_path,
    components = copy_components(components),
    trailing_slash = trailing_slash and #components > 0,
  }
end

return Path
