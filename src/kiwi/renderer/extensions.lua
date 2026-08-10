local PassApi = require("kiwi.renderer.pass_api")
local PassRegistry = require("kiwi.renderer.pass_registry")

local Extensions = {}
Extensions.__index = Extensions

local function valid_module_name(name)
  return type(name) == "string" and name:match("^[%a_][%w_%.]*$") ~= nil
end

local function copy_diagnostic(item)
  local copy = { extension = item.extension, pass = item.pass, phase = item.phase, message = item.message }
  if item.requested then copy.requested = { kind = item.requested.kind, value = item.requested.value } end
  if item.limit then copy.limit = { kind = item.limit.kind, value = item.limit.value } end
  return copy
end

function Extensions.new(options)
  options = options or {}
  local limit = options.diagnostic_limit or 32
  local message_limit = options.diagnostic_message_limit or 4096
  local pass_limit = options.pass_limit or 32
  local animation_hz = options.animation_hz or 60
  assert(type(limit) == "number" and limit >= 1 and limit % 1 == 0, "extension diagnostic limit must be a positive integer")
  assert(type(message_limit) == "number" and message_limit >= 1 and message_limit % 1 == 0, "extension diagnostic message limit must be a positive integer")
  assert(type(pass_limit) == "number" and pass_limit >= 1 and pass_limit % 1 == 0, "extension pass limit must be a positive integer")
  assert(type(animation_hz) == "number" and animation_hz >= 1 / 60 and animation_hz <= 60, "extension animation rate must be between 1/60 and 60 Hz")
  assert(options.enabled == nil or type(options.enabled) == "boolean", "extension enablement must be a boolean")
  return setmetatable({
    enabled = options.enabled ~= false,
    diagnostic_limit = limit,
    diagnostic_message_limit = message_limit,
    pass_limit = pass_limit,
    minimum_animation_delay = 1 / animation_hz,
    diagnostics = {},
    disabled = {},
    animations = {},
  }, Extensions)
end

function Extensions:record(extension, pass, phase, message, details)
  local text = tostring(message)
  if #text > self.diagnostic_message_limit then text = text:sub(1, self.diagnostic_message_limit) .. " [truncated]" end
  local item = { extension = extension or "unknown", pass = pass, phase = phase, message = text }
  if details then
    item.requested = details.requested
    item.limit = details.limit
  end
  self.diagnostics[#self.diagnostics + 1] = item
  while #self.diagnostics > self.diagnostic_limit do table.remove(self.diagnostics, 1) end
  return item
end

function Extensions:snapshot()
  local diagnostics = {}
  for index, item in ipairs(self.diagnostics) do diagnostics[index] = copy_diagnostic(item) end
  local disabled = {}
  for name, value in pairs(self.disabled) do disabled[name] = value end
  local animations = {}
  for name, deadline in pairs(self.animations) do animations[name] = deadline end
  return {
    enabled = self.enabled,
    diagnostics = diagnostics,
    disabled = disabled,
    animations = animations,
    limits = {
      extension_passes = self.pass_limit,
      maximum_animation_hz = 1 / self.minimum_animation_delay,
      minimum_animation_delay_seconds = self.minimum_animation_delay,
      diagnostic_entries = self.diagnostic_limit,
      diagnostic_message_bytes = self.diagnostic_message_limit,
      extension_buffers = 0,
      extension_textures = 0,
      texture_dimension = 0,
      gpu_memory_bytes = 0,
      gpu_memory_accounting = "unavailable",
      extension_shader_failures = 0,
    },
  }
end

local function registration_callback(registration, index)
  if type(registration) == "function" then return registration, "registration-" .. index end
  assert(valid_module_name(registration), "extension module " .. tostring(registration) .. " is not a valid Lua module name")
  local module = require(registration)
  if type(module) == "function" then return module, registration end
  if type(module) == "table" and type(module.register) == "function" then return module.register, registration end
  error("extension module " .. registration .. " must return a registration function or { register = function }")
end

function Extensions:register(registrations, core_passes)
  assert(type(registrations) == "table" or registrations == nil, "extension registrations must be a table")
  assert(type(core_passes) == "table", "core passes must be a table")
  if not self.enabled then return {} end
  local accepted = {}
  for index, registration in ipairs(registrations or {}) do
    local api = PassApi.new()
    local identity = type(registration) == "string" and registration or "registration-" .. index
    local cap_violation
    local ok, message = xpcall(function()
      local callback
      callback, identity = registration_callback(registration, index)
      callback(api)
      local candidate = {}
      for _, pass in ipairs(core_passes) do candidate[#candidate + 1] = pass end
      for _, pass in ipairs(accepted) do candidate[#candidate + 1] = pass end
      for _, pass in ipairs(api.passes) do candidate[#candidate + 1] = pass end
      if #accepted + #api.passes > self.pass_limit then
        local overflow = api.passes[self.pass_limit - #accepted + 1] or api.passes[#api.passes]
        identity = overflow.extension or identity
        cap_violation = {
          pass = overflow.name,
          requested = { kind = "extension-passes", value = #accepted + #api.passes },
          limit = { kind = "extension-passes", value = self.pass_limit },
        }
        error("extension pass limit " .. self.pass_limit .. " exceeded")
      end
      PassRegistry.validate(candidate)
    end, debug.traceback)
    if ok then
      for _, pass in ipairs(api.passes) do accepted[#accepted + 1] = pass end
    else
      self:record(identity, cap_violation and cap_violation.pass or nil, "registration", message, cap_violation)
    end
  end
  return accepted
end

function Extensions:request_animation(pass, now, delay, schedule)
  assert(type(pass) == "table" and type(pass.name) == "string", "extension animation needs a registered pass")
  assert(type(schedule) == "function", "extension animation needs a scheduler")
  if pass.disabled then return nil, "extension pass " .. pass.name .. " is disabled" end
  local valid_delay = type(delay) == "number" and delay == delay and delay ~= math.huge and delay ~= -math.huge
  if not valid_delay or delay < self.minimum_animation_delay then
    local message = "extension animation request falls below the " .. string.format("%.6f", self.minimum_animation_delay) .. " second minimum delay"
    local requested_delay = valid_delay and delay or tostring(delay)
    self:record(pass.extension, pass.name, "animation", message, {
      requested = { kind = "animation-delay-seconds", value = requested_delay },
      limit = { kind = "minimum-animation-delay-seconds", value = self.minimum_animation_delay },
    })
    return nil, message
  end
  local deadline = schedule("extension", now, delay)
  self.animations[pass.name] = deadline
  return deadline
end

function Extensions:consume_animations(now)
  for name, deadline in pairs(self.animations) do
    if deadline <= now then self.animations[name] = nil end
  end
end

function Extensions:disable_pass(pass, phase, message)
  pass.disabled = true
  pass.lifecycle = "disabled"
  self.disabled[pass.name] = true
  self.animations[pass.name] = nil
  self:record(pass.extension or "core", pass.name, phase, message, {
    requested = { kind = "callback-failures", value = 1 },
    limit = { kind = "callback-failures", value = 1 },
  })
end

return Extensions
