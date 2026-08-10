local Registry = {}
Registry.__index = Registry
local Budgets = require("kiwi.renderer.pass_budgets")

local function fail(message)
  error("render pass registry: " .. message, 3)
end

local function validate_names(kind, names)
  if type(names) ~= "table" then
    fail(kind .. " declarations must be a table")
  end
  local seen = {}
  for _, name in ipairs(names) do
    if type(name) ~= "string" or #name == 0 then
      fail(kind .. " declarations must contain non-empty names")
    end
    if seen[name] then
      fail(kind .. " declarations must not repeat " .. name)
    end
    seen[name] = true
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
  if pass.resize ~= nil and type(pass.resize) ~= "function" then
    fail("pass " .. pass.name .. " resize callback must be a function")
  end
  if pass.budget ~= nil then Budgets.copy(pass.budget, "pass " .. pass.name .. " budget") end
  validate_names("read resource", pass.reads)
  validate_names("write resource", pass.writes)
  validate_names("dependency", pass.after)
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

local function find_cycle(passes, by_name)
  local visiting = {}
  local visited = {}
  local path = {}
  local path_indexes = {}
  local function visit(pass)
    if visiting[pass.name] then
      local cycle = {}
      for index = path_indexes[pass.name], #path do cycle[#cycle + 1] = path[index].name end
      cycle[#cycle + 1] = pass.name
      return cycle
    end
    if visited[pass.name] then return nil end
    visiting[pass.name] = true
    path[#path + 1] = pass
    path_indexes[pass.name] = #path
    for _, name in ipairs(pass.after) do
      local cycle = visit(by_name[name])
      if cycle then return cycle end
    end
    path_indexes[pass.name] = nil
    path[#path] = nil
    visiting[pass.name] = nil
    visited[pass.name] = true
    return nil
  end
  for _, pass in ipairs(ordered_passes(passes)) do
    local cycle = visit(pass)
    if cycle then return cycle end
  end
end

local function graph_order(passes)
  local by_name = {}
  local indegree = {}
  local dependents = {}
  for _, pass in ipairs(passes) do
    by_name[pass.name] = pass
    indegree[pass.name] = 0
    dependents[pass.name] = {}
  end
  for _, pass in ipairs(passes) do
    for _, dependency in ipairs(pass.after) do
      if by_name[dependency] == nil then
        fail("pass " .. pass.name .. " depends on missing pass " .. dependency)
      end
      indegree[pass.name] = indegree[pass.name] + 1
      dependents[dependency][#dependents[dependency] + 1] = pass
    end
  end
  local ready = {}
  for _, pass in ipairs(passes) do
    if indegree[pass.name] == 0 then ready[#ready + 1] = pass end
  end
  local ordered = {}
  local parallel_groups = {}
  while #ready > 0 do
    ready = ordered_passes(ready)
    local current = ready
    ready = {}
    parallel_groups[#parallel_groups + 1] = current
    for _, pass in ipairs(current) do
      ordered[#ordered + 1] = pass
      for _, dependent in ipairs(dependents[pass.name]) do
        indegree[dependent.name] = indegree[dependent.name] - 1
        if indegree[dependent.name] == 0 then ready[#ready + 1] = dependent end
      end
    end
  end
  if #ordered ~= #passes then
    local cycle = find_cycle(passes, by_name)
    fail("dependency cycle: " .. table.concat(cycle or {}, " -> "))
  end
  return ordered, parallel_groups
end

function Registry.new(options)
  options = options or {}
  assert(options.on_optional_failure == nil or type(options.on_optional_failure) == "function", "optional pass failure handler must be a function")
  return setmetatable({
    passes = {},
    names = {},
    initialized = {},
    parallel_groups = {},
    metrics = options.metrics,
    on_optional_failure = options.on_optional_failure,
    activity = { active = nil, last = nil },
    state = "registering",
  }, Registry)
end

function Registry:run_pass(pass, phase, callback)
  local activity = { extension = pass.extension, name = pass.name, phase = phase }
  self.activity.active = activity
  self.activity.last = activity
  local ok, message = xpcall(callback, debug.traceback)
  self.activity.active = nil
  return ok, message
end

function Registry:activity_snapshot()
  local function copy(item)
    if item == nil then return nil end
    return { extension = item.extension, name = item.name, phase = item.phase }
  end
  return { active = copy(self.activity.active), last = copy(self.activity.last) }
end

function Registry.validate(passes)
  local names = {}
  for _, pass in ipairs(passes) do
    validate_pass(pass)
    if names[pass.name] then fail("pass " .. pass.name .. " is already registered") end
    names[pass.name] = true
  end
  return graph_order(passes)
end

function Registry:assert_state(expected, operation)
  if self.state ~= expected then
    fail(operation .. " is invalid while registry is " .. self.state)
  end
end

function Registry:register(pass)
  self:assert_state("registering", "registration")
  local ok, message = pcall(validate_pass, pass)
  if not ok then
    self.last_error = tostring(message)
    error(message, 0)
  end
  if self.names[pass.name] then
    self.last_error = "pass " .. pass.name .. " is already registered"
    fail(self.last_error)
  end
  self.names[pass.name] = true
  self.passes[#self.passes + 1] = pass
end

function Registry:contain_optional_failure(pass, phase, message)
  if not pass.extension or self.on_optional_failure == nil then return false end
  local ok, handler_message = xpcall(function()
    self.on_optional_failure(pass, phase, message)
  end, debug.traceback)
  if not ok then
    fail("optional pass " .. pass.name .. " " .. phase .. " failure handler failed: " .. handler_message)
  end
  return true
end

function Registry:initialize(renderer)
  self:assert_state("registering", "initialization")
  local ok, ordered, parallel_groups = pcall(Registry.validate, self.passes)
  if not ok then
    self.last_error = tostring(ordered)
    error(ordered, 0)
  end
  self.state = "initializing"
  for _, pass in ipairs(ordered) do
    self.initialized[#self.initialized + 1] = pass
    pass.lifecycle = "initializing"
    if pass.initialize then
      local ok, message = self:run_pass(pass, "initialization", function() pass:initialize(renderer) end)
      if not ok then
        if self:contain_optional_failure(pass, "initialization", message) then
          pass.lifecycle = "disabled"
        else
          pass.lifecycle = "failed"
          self:shutdown(renderer)
          fail("pass " .. pass.name .. " initialization failed: " .. message)
        end
      end
    end
    if not pass.disabled then pass.lifecycle = "ready" end
  end
  self.passes = ordered
  self.parallel_groups = parallel_groups
  self.state = "ready"
end

function Registry:encode(renderer, encoder, view, model)
  self:assert_state("ready", "encoding")
  for _, pass in ipairs(self.passes) do
    if not pass.disabled then
      local function encode()
        local ok, message = self:run_pass(pass, "encoding", function() pass:encode(renderer, encoder, view, model) end)
        if not ok then
          if not self:contain_optional_failure(pass, "encoding", message) then
            fail("pass " .. pass.name .. " encoding failed: " .. message)
          end
        end
      end
      if self.metrics then self.metrics:measure(pass.name, "encode", encode) else encode() end
    end
  end
end

function Registry:prepare(renderer, model)
  self:assert_state("ready", "preparation")
  for _, pass in ipairs(self.passes) do
    if not pass.disabled then
      local function prepare()
        if pass.prepare then
          local ok, message = self:run_pass(pass, "preparation", function() pass:prepare(renderer, model) end)
          if not ok then
            if not self:contain_optional_failure(pass, "preparation", message) then
              fail("pass " .. pass.name .. " preparation failed: " .. message)
            end
          end
        end
      end
      if self.metrics then self.metrics:measure(pass.name, "prepare", prepare) else prepare() end
    end
  end
end

function Registry:begin_frame()
  if self.metrics then self.metrics:begin_frame() end
end

function Registry:end_frame()
  if self.metrics then self.metrics:end_frame() end
end

function Registry:reset_metrics()
  if self.metrics then self.metrics:reset() end
end

function Registry:resize(renderer, previous, current)
  self:assert_state("ready", "resize")
  for _, pass in ipairs(self.passes) do
    if not pass.disabled and pass.resize then
      local ok, message = self:run_pass(pass, "resize", function() pass:resize(renderer, previous, current) end)
      if not ok and not self:contain_optional_failure(pass, "resize", message) then
        fail("pass " .. pass.name .. " resize failed: " .. message)
      end
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
      local ok, message = self:run_pass(pass, "shutdown", function() pass:shutdown(renderer) end)
      if not ok and not self:contain_optional_failure(pass, "shutdown", message) and first_error == nil then
        first_error = "pass " .. pass.name .. " shutdown failed: " .. message
      end
    end
    if self.metrics then self.metrics:remove(pass.name) end
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
