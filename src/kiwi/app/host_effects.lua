-- Host-owned policy for terminal escape-sequence effects. Terminal state only
-- requests effects; this boundary decides whether a configured host may submit
-- them to the desktop.
local Effects = {}
Effects.__index = Effects

Effects.maximum_notification_bytes = 1024
Effects.maximum_diagnostics = 32

local policies = { off = true, system = true }
local statuses = { disabled = true, invalid = true, rejected = true, submitted = true, unavailable = true }

local function valid_text(value, maximum)
  return type(value) == "string" and #value <= maximum
    and not value:find("\0", 1, true) and not value:find("\r", 1, true) and not value:find("\n", 1, true)
end

local function valid_progress(value)
  return type(value) == "table"
    and type(value.progress) == "number" and value.progress % 1 == 0 and value.progress >= 0 and value.progress <= 100
    and type(value.state) == "number" and value.state % 1 == 0 and value.state >= 0 and value.state <= 4
end

function Effects.new(configuration, host, window)
  assert(type(configuration) == "table", "host effects need configuration")
  assert(type(host) == "table", "host effects need a host")
  assert(policies[configuration.osc9_notifications] == true, "host effects need an OSC 9 notification policy")
  assert(policies[configuration.osc9_progress] == true, "host effects need an OSC 9 progress policy")
  return setmetatable({
    configuration = configuration,
    diagnostics = {},
    host = host,
    reported = {},
    window = window,
  }, Effects)
end

function Effects:record(kind, status)
  assert(statuses[status] == true, "host effect status is invalid")
  local diagnostic = { kind = kind, status = status }
  if #self.diagnostics == Effects.maximum_diagnostics then table.remove(self.diagnostics, 1) end
  self.diagnostics[#self.diagnostics + 1] = diagnostic
  local key = kind .. ":" .. status
  local first_report = self.reported[key] == nil
  self.reported[key] = true
  return diagnostic, first_report
end

local function submit(callback, ...)
  if type(callback) ~= "function" then return false, "unavailable" end
  local invoked, accepted = pcall(callback, ...)
  if not invoked or accepted ~= true then return false, "rejected" end
  return true, "submitted"
end

function Effects:consume(effect)
  if type(effect) ~= "table" or type(effect.kind) ~= "string" then return false end
  if effect.kind == "notification_requested" then
    local status
    if self.configuration.osc9_notifications == "off" then
      status = "disabled"
    elseif not valid_text(effect.value and effect.value.body, Effects.maximum_notification_bytes) then
      status = "invalid"
    elseif type(self.host.notify) ~= "function" then
      status = "unavailable"
    else
      _, status = submit(self.host.notify, self.window, "Kiwi terminal", effect.value.body)
    end
    local diagnostic, first_report = self:record("notification", status)
    return true, status, first_report, diagnostic
  end
  if effect.kind == "progress_changed" then
    local status
    if self.configuration.osc9_progress == "off" then
      status = "disabled"
    elseif not valid_progress(effect.value) then
      status = "invalid"
    elseif type(self.host.set_progress) ~= "function" then
      status = "unavailable"
    else
      _, status = submit(self.host.set_progress, self.window, effect.value.progress, effect.value.state)
    end
    local diagnostic, first_report = self:record("progress", status)
    return true, status, first_report, diagnostic
  end
  return false
end

function Effects:snapshot()
  local diagnostics = {}
  for index, diagnostic in ipairs(self.diagnostics) do diagnostics[index] = { kind = diagnostic.kind, status = diagnostic.status } end
  return { diagnostics = diagnostics }
end

return Effects
