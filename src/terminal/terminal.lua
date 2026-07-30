local Errors = require("runtime.errors")

local Terminal = {}
local terminal_mt = {}
terminal_mt.__index = terminal_mt

Terminal.contract = {
  constructor = "new(config) -> terminal | nil, error",
  start = "start() -> nil, error",
  feed_output = "feed_output(bytes) -> nil, error",
  resize = "resize(columns, rows) -> nil, error",
  snapshot = "snapshot() -> nil, error",
  destroy = "destroy()",
}

function Terminal.new(config)
  if type(config) ~= "table" then
    return nil, Errors.new("config_error", "terminal config must be a table")
  end
  return setmetatable({ config = config, state = "bootstrap" }, terminal_mt)
end

function terminal_mt:start()
  return nil, Errors.new("internal_invariant_error", "terminal start is not implemented")
end

function terminal_mt:feed_output(bytes)
  if type(bytes) ~= "string" then
    return nil, Errors.new("config_error", "terminal output must be bytes")
  end
  return nil, Errors.new("internal_invariant_error", "terminal parser is not implemented")
end

function terminal_mt:resize(columns, rows)
  if type(columns) ~= "number" or type(rows) ~= "number" then
    return nil, Errors.new("config_error", "terminal dimensions must be numbers")
  end
  return nil, Errors.new("internal_invariant_error", "terminal resize is not implemented")
end

function terminal_mt:snapshot()
  return nil, Errors.new("internal_invariant_error", "terminal snapshot is not implemented")
end

function terminal_mt:destroy()
  self.state = "destroyed"
end

return Terminal
