local Errors = require("runtime.errors")

local Config = {}

Config.contract = {
  new = "new(options?) -> immutable_config | nil, error",
}

local defaults = {
  columns = 80,
  compatibility_profile = "stanczyk-basic-v1",
  rows = 24,
  scrollback_limit = 1000,
}

local limits = {
  columns = 1000,
  rows = 1000,
  scrollback_limit = 100000,
}

local allowed_options = {
  columns = true,
  compatibility_profile = true,
  rows = true,
  scrollback_limit = true,
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function bounded_integer(value, name, minimum, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < minimum or value > maximum then
    return config_error(name .. " must be an integer from " .. minimum .. " to " .. maximum, {
      maximum = maximum,
      minimum = minimum,
      provided = value,
    })
  end
  return value
end

local function immutable(values)
  return setmetatable({}, {
    __index = values,
    __metatable = false,
    __newindex = function(_, key)
      error("terminal config is immutable: " .. tostring(key), 2)
    end,
  })
end

function Config.new(options)
  if options == nil then
    options = {}
  end
  if type(options) ~= "table" then
    return config_error("terminal config must be a table")
  end
  for name in pairs(options) do
    if not allowed_options[name] then
      return config_error("unknown terminal config option", { option = name })
    end
  end

  local requested_columns = options.columns
  if requested_columns == nil then
    requested_columns = defaults.columns
  end
  local columns, columns_error = bounded_integer(requested_columns, "columns", 1, limits.columns)
  if not columns then
    return nil, columns_error
  end
  local requested_rows = options.rows
  if requested_rows == nil then
    requested_rows = defaults.rows
  end
  local rows, rows_error = bounded_integer(requested_rows, "rows", 1, limits.rows)
  if not rows then
    return nil, rows_error
  end
  local requested_scrollback_limit = options.scrollback_limit
  if requested_scrollback_limit == nil then
    requested_scrollback_limit = defaults.scrollback_limit
  end
  local scrollback_limit, scrollback_error =
    bounded_integer(requested_scrollback_limit, "scrollback_limit", 0, limits.scrollback_limit)
  if not scrollback_limit then
    return nil, scrollback_error
  end
  local compatibility_profile = options.compatibility_profile
  if compatibility_profile == nil then
    compatibility_profile = defaults.compatibility_profile
  end
  if compatibility_profile ~= "stanczyk-basic-v1" then
    return config_error("unsupported compatibility profile", { provided = compatibility_profile })
  end

  return immutable({
    columns = columns,
    compatibility_profile = compatibility_profile,
    rows = rows,
    scrollback_limit = scrollback_limit,
  })
end

return Config
