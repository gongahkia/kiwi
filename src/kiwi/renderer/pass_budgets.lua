local Budgets = {}
Budgets.__index = Budgets

local fields = { "cpu_ms", "gpu_ticks", "allocation_bytes", "cadence_hz", "window" }
local maximum_window = 120
local maximum_warnings = 64

local function copy_table(source)
  local copy = {}
  for key, value in pairs(source or {}) do copy[key] = value end
  return copy
end

local function finite_number(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function fail(prefix, message)
  error((prefix or "pass budget") .. " " .. message, 3)
end

function Budgets.copy(declaration, prefix)
  if declaration == nil then return nil end
  if type(declaration) ~= "table" then fail(prefix, "must be a table") end
  local known = {}
  for _, field in ipairs(fields) do known[field] = true end
  for field in pairs(declaration) do
    if not known[field] then fail(prefix, "has unknown field " .. tostring(field)) end
  end
  local copy = {}
  local declared = 0
  for _, field in ipairs({ "cpu_ms", "gpu_ticks", "cadence_hz" }) do
    local value = declaration[field]
    if value ~= nil then
      if not finite_number(value) or value <= 0 then fail(prefix, field .. " must be a finite positive number") end
      copy[field] = value
      declared = declared + 1
    end
  end
  local allocation = declaration.allocation_bytes
  if allocation ~= nil then
    if not finite_number(allocation) or allocation < 0 or allocation % 1 ~= 0 then
      fail(prefix, "allocation_bytes must be a finite non-negative integer")
    end
    copy.allocation_bytes = allocation
    declared = declared + 1
  end
  if declared == 0 then fail(prefix, "must declare at least one budget dimension") end
  local window = declaration.window or 30
  if not finite_number(window) or window < 1 or window > maximum_window or window % 1 ~= 0 then
    fail(prefix, "window must be a finite positive integer no greater than " .. maximum_window)
  end
  copy.window = window
  return copy
end

local function new_dimension(limit, status, reason)
  return { limit = limit, status = status or "pending", reason = reason, values = {} }
end

local function new_state(name, declaration)
  local dimensions = {}
  if declaration.cpu_ms then dimensions.cpu_ms = new_dimension(declaration.cpu_ms) end
  if declaration.gpu_ticks then dimensions.gpu_ticks = new_dimension(declaration.gpu_ticks) end
  if declaration.allocation_bytes then
    dimensions.allocation_bytes = new_dimension(declaration.allocation_bytes, "unavailable", "pass allocation accounting is unavailable")
  end
  if declaration.cadence_hz then dimensions.cadence_hz = new_dimension(declaration.cadence_hz) end
  return { name = name, declaration = declaration, dimensions = dimensions, status = "pending" }
end

local function average(values)
  local total = 0
  for _, value in ipairs(values) do total = total + value end
  return #values == 0 and nil or total / #values
end

local function copy_dimension(dimension)
  local values = dimension.values
  return {
    limit = dimension.limit,
    status = dimension.status,
    reason = dimension.reason,
    latest = values[#values],
    average = average(values),
    sample_count = #values,
  }
end

local function aggregate_status(dimensions)
  local supported = false
  local pending = false
  for _, dimension in pairs(dimensions) do
    if dimension.status == "over-budget" then return "over-budget" end
    if dimension.status == "within-budget" then supported = true end
    if dimension.status == "pending" then pending = true end
  end
  if supported then return "within-budget" end
  if pending then return "pending" end
  return "unavailable"
end

local function copy_state(state, enabled)
  local dimensions = {}
  for name, dimension in pairs(state.dimensions) do
    dimensions[name] = copy_dimension(dimension)
    if not enabled then
      dimensions[name].status = "disabled"
      dimensions[name].reason = "pass budget accounting is disabled"
    end
  end
  return {
    name = state.name,
    declaration = copy_table(state.declaration),
    status = enabled and state.status or "disabled",
    dimensions = dimensions,
  }
end

local function sorted_states(states)
  local ordered = {}
  for _, state in pairs(states) do ordered[#ordered + 1] = state end
  table.sort(ordered, function(left, right) return left.name < right.name end)
  return ordered
end

function Budgets.new(options)
  options = options or {}
  local warning_limit = options.warning_limit or 64
  assert(finite_number(warning_limit) and warning_limit >= 1 and warning_limit <= maximum_warnings and warning_limit % 1 == 0, "pass budget warning limit must be a positive integer no greater than " .. maximum_warnings)
  return setmetatable({
    enabled = options.enabled == true,
    warning_limit = warning_limit,
    states = {},
    warnings = {},
    last_cadence_time = {},
    seen_gpu_frames = {},
  }, Budgets)
end

function Budgets:register(passes)
  assert(type(passes) == "table", "pass budget registration needs passes")
  for _, pass in ipairs(passes) do
    if pass.budget then self.states[pass.name] = new_state(pass.name, Budgets.copy(pass.budget, "pass " .. pass.name .. " budget")) end
  end
end

function Budgets:record(state, name, value, frame)
  local dimension = state.dimensions[name]
  local values = dimension.values
  values[#values + 1] = value
  while #values > state.declaration.window do table.remove(values, 1) end
  local mean = average(values)
  dimension.reason = nil
  dimension.status = mean > dimension.limit and "over-budget" or "within-budget"
  state.status = aggregate_status(state.dimensions)
  if dimension.status == "over-budget" then
    self.warnings[#self.warnings + 1] = {
      pass = state.name,
      dimension = name,
      frame = frame,
      sample = value,
      average = mean,
      limit = dimension.limit,
      window = #values,
    }
    while #self.warnings > self.warning_limit do table.remove(self.warnings, 1) end
  end
end

local function cpu_by_name(snapshot)
  local samples = {}
  for _, sample in ipairs(snapshot and snapshot.samples or {}) do samples[sample.name] = sample end
  return samples
end

local function gpu_by_name(snapshot)
  local samples = {}
  for _, sample in ipairs(snapshot and snapshot.samples or {}) do samples[sample.name] = sample end
  return samples
end

local function timed_passes(snapshot)
  local passes = {}
  for _, name in ipairs(snapshot and snapshot.timed_passes or {}) do passes[name] = true end
  return passes
end

function Budgets:observe(cpu_snapshot, gpu_snapshot, now)
  if not self.enabled then return end
  local cpu = cpu_by_name(cpu_snapshot)
  local gpu = gpu_by_name(gpu_snapshot)
  local timed = timed_passes(gpu_snapshot)
  local cpu_enabled = cpu_snapshot and cpu_snapshot.enabled == true
  local gpu_enabled = gpu_snapshot and gpu_snapshot.enabled == true
  local frame = cpu_snapshot and cpu_snapshot.frame or 0
  for _, state in ipairs(sorted_states(self.states)) do
    local declaration = state.declaration
    local cpu_sample = cpu[state.name]
    if declaration.cpu_ms then
      if cpu_sample then
        self:record(state, "cpu_ms", (cpu_sample.prepare_ms or 0) + (cpu_sample.encode_ms or 0), frame)
      elseif not cpu_enabled then
        state.dimensions.cpu_ms.status = "unavailable"
        state.dimensions.cpu_ms.reason = "CPU pass metrics are disabled"
      end
    end
    if declaration.cadence_hz and cpu_sample then
      local previous = self.last_cadence_time[state.name]
      self.last_cadence_time[state.name] = now
      if previous and finite_number(now) and now > previous then
        self:record(state, "cadence_hz", 1 / (now - previous), frame)
      end
    end
    if declaration.gpu_ticks then
      local gpu_sample = gpu[state.name]
      if not gpu_enabled then
        state.dimensions.gpu_ticks.status = "unavailable"
        state.dimensions.gpu_ticks.reason = gpu_snapshot and gpu_snapshot.status or "GPU timestamp instrumentation is disabled"
      elseif not timed[state.name] then
        state.dimensions.gpu_ticks.status = "unavailable"
        state.dimensions.gpu_ticks.reason = "pass has no GPU timestamp instrumentation"
      elseif gpu_sample and self.seen_gpu_frames[state.name] ~= gpu_sample.frame then
        self.seen_gpu_frames[state.name] = gpu_sample.frame
        self:record(state, "gpu_ticks", gpu_sample.gpu_ticks, gpu_sample.frame)
      end
    end
    state.status = aggregate_status(state.dimensions)
  end
end

function Budgets:pass_snapshot(name)
  local state = self.states[name]
  if state == nil then return { name = name, status = "unconfigured", declaration = {}, dimensions = {} } end
  return copy_state(state, self.enabled)
end

function Budgets:reset()
  self.warnings = {}
  self.last_cadence_time = {}
  self.seen_gpu_frames = {}
  for name, state in pairs(self.states) do self.states[name] = new_state(name, state.declaration) end
end

function Budgets:snapshot()
  local passes = {}
  for index, state in ipairs(sorted_states(self.states)) do passes[index] = copy_state(state, self.enabled) end
  local warnings = {}
  for index, warning in ipairs(self.warnings) do warnings[index] = copy_table(warning) end
  return { enabled = self.enabled, warnings = warnings, passes = passes }
end

return Budgets
