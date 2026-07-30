local Config = require("terminal.config")
local Errors = require("runtime.errors")
local Row = require("terminal.row")

local Scrollback = {}
local scrollback_mt = {}
scrollback_mt.__index = scrollback_mt

Scrollback.contract = {
  at = "at(index) -> row | nil, error",
  clear = "clear()",
  new = "new(limit) -> scrollback | nil, error",
  push = "push(row) -> true | nil, error",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function physical_index(scrollback, index)
  return ((scrollback.first + index - 2) % scrollback.limit) + 1
end

function Scrollback.new(limit)
  if limit == nil then
    return config_error("scrollback limit must be provided")
  end
  local config, config_error_value = Config.new({ scrollback_limit = limit })
  if not config then
    return nil, config_error_value
  end
  return setmetatable({
    count = 0,
    entries = {},
    first = 1,
    limit = config.scrollback_limit,
  }, scrollback_mt)
end

function scrollback_mt:push(row)
  local copy, copy_error = Row.copy(row)
  if not copy then
    return nil, copy_error
  end
  if self.limit == 0 then
    return true
  end
  local index
  if self.count < self.limit then
    index = physical_index(self, self.count + 1)
    self.count = self.count + 1
  else
    index = self.first
    self.first = (self.first % self.limit) + 1
  end
  self.entries[index] = copy
  return true
end

function scrollback_mt:at(index)
  if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > self.count then
    return config_error("scrollback index must reference a stored row", { provided = index })
  end
  return Row.copy(self.entries[physical_index(self, index)])
end

function scrollback_mt:clear()
  self.count = 0
  self.entries = {}
  self.first = 1
end

return Scrollback
