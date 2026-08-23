-- Host-owned policy for terminal escape-sequence effects. Terminal state only
-- requests effects; this boundary decides whether a configured host may submit
-- them to the desktop.
local Effects = {}
Effects.__index = Effects

Effects.maximum_notification_bytes = 1024
Effects.maximum_diagnostics = 32

local policies = { off = true, system = true }
local command_finish_policies = { always = true, never = true, unfocused = true }
local statuses = {
  disabled = true,
  invalid = true,
  rejected = true,
  submitted = true,
  unavailable = true,
}

local function valid_text(value, maximum)
  return type(value) == "string" and #value <= maximum
    and not value:find("\0", 1, true) and not value:find("\r", 1, true) and not value:find("\n", 1, true)
end

local function valid_progress(value)
  if type(value) ~= "table" or type(value.state) ~= "number" or value.state % 1 ~= 0 or value.state < 0 or value.state > 4 then return false end
  if value.progress == nil then return value.state ~= 1 end
  return type(value.progress) == "number" and value.progress % 1 == 0 and value.progress >= 0 and value.progress <= 100
end

local function valid_timestamp(value)
  return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function source_key(self, context)
  if type(context) == "table" and type(context.source) == "table" then return context.source end
  return self.default_source
end

local function command_completion_body(exit_status)
  if exit_status == nil or exit_status == 0 then return "A terminal command finished." end
  return "A terminal command finished with exit status " .. exit_status .. "."
end

local function submit(callback, ...)
  if type(callback) ~= "function" then return false, "unavailable" end
  local invoked, accepted = pcall(callback, ...)
  if not invoked or accepted ~= true then return false, "rejected" end
  return true, "submitted"
end

function Effects.new(configuration, host, window)
  assert(type(configuration) == "table", "host effects need configuration")
  assert(type(host) == "table", "host effects need a host")
  assert(policies[configuration.osc9_notifications] == true, "host effects need an OSC 9 notification policy")
  assert(policies[configuration.osc9_progress] == true, "host effects need an OSC 9 progress policy")
  assert(command_finish_policies[configuration.notify_on_command_finish] == true, "host effects need a command-finish notification policy")
  assert(type(configuration.notify_on_command_finish_after) == "number"
    and configuration.notify_on_command_finish_after % 1 == 0
    and configuration.notify_on_command_finish_after >= 0
    and configuration.notify_on_command_finish_after <= 86400,
    "host effects need a bounded command-finish notification threshold")
  return setmetatable({
    command_starts = setmetatable({}, { __mode = "k" }),
    configuration = configuration,
    default_source = {},
    diagnostics = {},
    host = host,
    progress = 0,
    reported = {},
    window = window,
  }, Effects)
end

function Effects:consume_shell_marker(effect, context)
  local marker = effect.value
  if type(marker) ~= "table" or (marker.kind ~= "command_executed" and marker.kind ~= "command_finished") then return false end
  if marker.exit_status ~= nil and (type(marker.exit_status) ~= "number" or marker.exit_status % 1 ~= 0
    or marker.exit_status < 0 or marker.exit_status > 255) then
    local diagnostic, first_report = self:record("command-finish", "invalid")
    return true, "invalid", first_report, diagnostic
  end
  local now = type(context) == "table" and context.now or nil
  if not valid_timestamp(now) then
    local diagnostic, first_report = self:record("command-finish", "invalid")
    return true, "invalid", first_report, diagnostic
  end
  local source = source_key(self, context)
  if marker.kind == "command_executed" then
    self.command_starts[source] = now
    return true, "tracked", false
  end

  local started_at = self.command_starts[source]
  self.command_starts[source] = nil
  if started_at == nil or now < started_at then return true, "untracked", false end
  if self.configuration.notify_on_command_finish == "never" then return true, "disabled", false end
  if now - started_at < self.configuration.notify_on_command_finish_after then return true, "below-threshold", false end
  if self.configuration.notify_on_command_finish == "unfocused" and (type(context) ~= "table" or context.focused ~= false) then
    return true, "focused", false
  end
  local status
  if type(self.host.notify) ~= "function" then
    status = "unavailable"
  else
    _, status = submit(self.host.notify, self.window, "Kiwi terminal", command_completion_body(marker.exit_status))
  end
  local diagnostic, first_report = self:record("command-finish", status)
  return true, status, first_report, diagnostic
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

function Effects:consume(effect, context)
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
      local progress = effect.value.progress == nil and self.progress or effect.value.progress
      _, status = submit(self.host.set_progress, self.window, progress, effect.value.state)
      if status == "submitted" then
        if effect.value.state == 0 then
          self.progress = 0
        elseif effect.value.progress ~= nil then
          self.progress = effect.value.progress
        end
      end
    end
    local diagnostic, first_report = self:record("progress", status)
    return true, status, first_report, diagnostic
  end
  if effect.kind == "shell_marker" then return self:consume_shell_marker(effect, context) end
  return false
end

function Effects:snapshot()
  local diagnostics = {}
  for index, diagnostic in ipairs(self.diagnostics) do diagnostics[index] = { kind = diagnostic.kind, status = diagnostic.status } end
  return { diagnostics = diagnostics }
end

return Effects
