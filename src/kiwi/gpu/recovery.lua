local Recovery = {}
Recovery.__index = Recovery

local function copy_adapter(adapter)
  adapter = adapter or {}
  return {
    backend = adapter.backend_name or adapter.backend or "unknown",
    device = adapter.device or "unknown",
    vendor = adapter.vendor or "unknown",
  }
end

local function copy_pass(activity)
  local pass = activity and (activity.active or activity.last)
  if not pass then return { name = "unavailable", phase = "unavailable" } end
  return { name = pass.name, phase = pass.phase, extension = pass.extension }
end

local function classify(reason)
  local text = tostring(reason or "unknown GPU error")
  if text == "zero-sized drawable" or text == "surface occluded" then return "wait" end
  if text:match("^surface acquire status ") or text:match("^surface present status ") then return "retry-surface" end
  if text:find("wgpu device lost", 1, true) or text:find("simulated device loss", 1, true) then return "device-loss" end
  if text:match("^native GPU error:") then return "fatal-native-error" end
  return "fatal-render-error"
end

local function bounded_message(value, limit)
  local text = tostring(value or "unknown GPU error")
  if #text <= limit then return text end
  return text:sub(1, limit) .. " [truncated]"
end

function Recovery.new(options)
  options = options or {}
  local history_limit = options.history_limit or 16
  local message_limit = options.message_limit or 2048
  local max_device_retries = options.max_device_retries or 1
  assert(type(history_limit) == "number" and history_limit >= 1 and history_limit % 1 == 0, "GPU recovery history limit must be a positive integer")
  assert(type(message_limit) == "number" and message_limit >= 1 and message_limit % 1 == 0, "GPU recovery message limit must be a positive integer")
  assert(type(max_device_retries) == "number" and max_device_retries >= 0 and max_device_retries % 1 == 0, "GPU recovery retry limit must be a non-negative integer")
  return setmetatable({
    history = {},
    history_limit = history_limit,
    message_limit = message_limit,
    max_device_retries = max_device_retries,
    device_retries = 0,
  }, Recovery)
end

function Recovery:decide(reason, context, activity)
  local kind = classify(reason)
  local action
  if kind == "wait" then
    action = "wait"
  elseif kind == "retry-surface" then
    action = "retry-surface"
  elseif kind == "device-loss" and self.device_retries < self.max_device_retries then
    self.device_retries = self.device_retries + 1
    action = "retry-device"
  else
    action = "exit"
  end
  local item = {
    action = action,
    adapter = copy_adapter(context and context.adapter_info),
    attempts = self.device_retries,
    kind = kind,
    message = bounded_message(reason, self.message_limit),
    pass = copy_pass(activity),
  }
  self.history[#self.history + 1] = item
  while #self.history > self.history_limit do table.remove(self.history, 1) end
  return item
end

function Recovery:snapshot()
  local history = {}
  for index, item in ipairs(self.history) do
    history[index] = {
      action = item.action,
      adapter = copy_adapter(item.adapter),
      attempts = item.attempts,
      kind = item.kind,
      message = item.message,
      pass = copy_pass({ active = item.pass }),
    }
  end
  return {
    device_retries = self.device_retries,
    history = history,
    limits = { device_retries = self.max_device_retries, diagnostic_entries = self.history_limit, diagnostic_message_bytes = self.message_limit },
    policy = "wait for zero-sized or occluded surfaces, retry one device loss by recreating the GPU context, and exit for a second loss or another native GPU error",
  }
end

function Recovery.format(item, max_device_retries)
  return string.format(
    "action=%s kind=%s attempt=%d/%d backend=%s vendor=%s adapter=%s pass=%s phase=%s: %s",
    item.action,
    item.kind,
    item.attempts,
    max_device_retries,
    item.adapter.backend,
    item.adapter.vendor,
    item.adapter.device,
    item.pass.name,
    item.pass.phase,
    item.message
  )
end

return Recovery
