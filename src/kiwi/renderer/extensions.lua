local PassApi = require("kiwi.renderer.pass_api")
local PassRegistry = require("kiwi.renderer.pass_registry")

local Extensions = {}
Extensions.__index = Extensions

local function valid_module_name(name)
  return type(name) == "string" and name:match("^[%a_][%w_%.]*$") ~= nil
end

local function copy_diagnostic(item)
  return { extension = item.extension, pass = item.pass, phase = item.phase, message = item.message }
end

function Extensions.new(options)
  options = options or {}
  local limit = options.diagnostic_limit or 32
  local pass_limit = options.pass_limit or 32
  assert(type(limit) == "number" and limit >= 1 and limit % 1 == 0, "extension diagnostic limit must be a positive integer")
  assert(type(pass_limit) == "number" and pass_limit >= 1 and pass_limit % 1 == 0, "extension pass limit must be a positive integer")
  assert(options.enabled == nil or type(options.enabled) == "boolean", "extension enablement must be a boolean")
  return setmetatable({
    enabled = options.enabled ~= false,
    diagnostic_limit = limit,
    pass_limit = pass_limit,
    diagnostics = {},
    disabled = {},
  }, Extensions)
end

function Extensions:record(extension, pass, phase, message)
  local text = tostring(message)
  if #text > 4096 then text = text:sub(1, 4096) .. " [truncated]" end
  local item = { extension = extension or "unknown", pass = pass, phase = phase, message = text }
  self.diagnostics[#self.diagnostics + 1] = item
  while #self.diagnostics > self.diagnostic_limit do table.remove(self.diagnostics, 1) end
  return item
end

function Extensions:snapshot()
  local diagnostics = {}
  for index, item in ipairs(self.diagnostics) do diagnostics[index] = copy_diagnostic(item) end
  local disabled = {}
  for name, value in pairs(self.disabled) do disabled[name] = value end
  return { enabled = self.enabled, diagnostics = diagnostics, disabled = disabled }
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
    local ok, message = xpcall(function()
      local callback
      callback, identity = registration_callback(registration, index)
      callback(api)
      local candidate = {}
      for _, pass in ipairs(core_passes) do candidate[#candidate + 1] = pass end
      for _, pass in ipairs(accepted) do candidate[#candidate + 1] = pass end
      for _, pass in ipairs(api.passes) do candidate[#candidate + 1] = pass end
      assert(#accepted + #api.passes <= self.pass_limit, "extension pass limit " .. self.pass_limit .. " exceeded")
      PassRegistry.validate(candidate)
    end, debug.traceback)
    if ok then
      for _, pass in ipairs(api.passes) do accepted[#accepted + 1] = pass end
    else
      self:record(identity, nil, "registration", message)
    end
  end
  return accepted
end

function Extensions:disable_pass(pass, phase, message)
  pass.disabled = true
  pass.lifecycle = "disabled"
  self.disabled[pass.name] = true
  self:record(pass.extension or "core", pass.name, phase, message)
end

return Extensions
