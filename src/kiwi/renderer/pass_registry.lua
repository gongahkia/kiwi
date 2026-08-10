local Registry = {}
Registry.__index = Registry

local function fail(message)
  error("render pass registry: " .. message, 3)
end

local function validate_names(kind, names)
  if type(names) ~= "table" then
    fail(kind .. " declarations must be a table")
  end
  for _, name in ipairs(names) do
    if type(name) ~= "string" or #name == 0 then
      fail(kind .. " declarations must contain non-empty names")
    end
  end
end

local function validate_pass(pass)
  if type(pass) ~= "table" then
    fail("pass registration must be a table")
  end
  if type(pass.name) ~= "string" or #pass.name == 0 then
    fail("pass needs a non-empty name")
  end
  if type(pass.order) ~= "number" or pass.order % 1 ~= 0 then
    fail("pass " .. pass.name .. " needs an integer order")
  end
  if type(pass.encode) ~= "function" then
    fail("pass " .. pass.name .. " needs an encode callback")
  end
  if pass.initialize ~= nil and type(pass.initialize) ~= "function" then
    fail("pass " .. pass.name .. " initialize callback must be a function")
  end
  if pass.shutdown ~= nil and type(pass.shutdown) ~= "function" then
    fail("pass " .. pass.name .. " shutdown callback must be a function")
  end
  validate_names("read resource", pass.reads)
  validate_names("write resource", pass.writes)
end

local function ordered_passes(passes)
  local ordered = {}
  for index, pass in ipairs(passes) do ordered[index] = pass end
  table.sort(ordered, function(left, right)
    if left.order == right.order then return left.name < right.name end
    return left.order < right.order
  end)
  return ordered
end

function Registry.new()
  return setmetatable({
    passes = {},
    names = {},
    initialized = {},
    state = "registering",
  }, Registry)
end

function Registry:assert_state(expected, operation)
  if self.state ~= expected then
    fail(operation .. " is invalid while registry is " .. self.state)
  end
end

function Registry:register(pass)
  self:assert_state("registering", "registration")
  validate_pass(pass)
  if self.names[pass.name] then
    fail("pass " .. pass.name .. " is already registered")
  end
  self.names[pass.name] = true
  self.passes[#self.passes + 1] = pass
end

function Registry:initialize(renderer)
  self:assert_state("registering", "initialization")
  self.state = "initializing"
  local ordered = ordered_passes(self.passes)
  for _, pass in ipairs(ordered) do
    self.initialized[#self.initialized + 1] = pass
    pass.lifecycle = "initializing"
    if pass.initialize then
      local ok, message = xpcall(function() pass:initialize(renderer) end, debug.traceback)
      if not ok then
        pass.lifecycle = "failed"
        self:shutdown(renderer)
        fail("pass " .. pass.name .. " initialization failed: " .. message)
      end
    end
    pass.lifecycle = "ready"
  end
  self.passes = ordered
  self.state = "ready"
end

function Registry:encode(renderer, encoder, view, model)
  self:assert_state("ready", "encoding")
  for _, pass in ipairs(self.passes) do
    local ok, message = xpcall(function() pass:encode(renderer, encoder, view, model) end, debug.traceback)
    if not ok then
      fail("pass " .. pass.name .. " encoding failed: " .. message)
    end
  end
end

function Registry:shutdown(renderer)
  if self.state == "destroyed" then
    return
  end
  local first_error
  for index = #self.initialized, 1, -1 do
    local pass = self.initialized[index]
    if pass.lifecycle ~= "shutdown" and pass.shutdown then
      local ok, message = xpcall(function() pass:shutdown(renderer) end, debug.traceback)
      if not ok and first_error == nil then first_error = "pass " .. pass.name .. " shutdown failed: " .. message end
    end
    pass.lifecycle = "shutdown"
  end
  self.initialized = {}
  self.state = "destroyed"
  if first_error then fail(first_error) end
end

function Registry:count()
  return #self.passes
end

return Registry
