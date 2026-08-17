local Window = require("kiwi.platform.window")

local Manager = {}
Manager.__index = Manager

local function positive_integer(value, name)
  assert(type(value) == "number" and value >= 1 and value % 1 == 0, name .. " must be a positive integer")
end

local function copy_options(options)
  local copy = {}
  for name, value in pairs(options) do copy[name] = value end
  return copy
end

function Manager.new(run_window, options, dependencies)
  assert(type(run_window) == "function", "live window manager needs a window controller")
  options = options or {}
  dependencies = dependencies or {}
  local maximum_windows = options.maximum_windows or tonumber(os.getenv("KIWI_MAX_WINDOWS")) or 16
  positive_integer(maximum_windows, "live window manager maximum windows")
  return setmetatable({
    controllers = {},
    maximum_windows = maximum_windows,
    options = options,
    run_window = run_window,
    window_api = dependencies.window_api or Window,
  }, Manager)
end

function Manager:window_count()
  return #self.controllers
end

function Manager:_start(options)
  if self:window_count() >= self.maximum_windows then return nil, "window-limit" end
  local controller = { options = options, state = "new" }
  controller.thread = coroutine.create(function()
    self.run_window(options)
  end)
  self.controllers[#self.controllers + 1] = controller
  return controller
end

function Manager:request_window(configuration_path)
  if self.options.record then return nil, "new windows are unavailable while --record is active" end
  local options = copy_options(self.options)
  options.application = self
  options.command = nil
  options.multi_window_smoke_requester = false
  options.workspace_smoke = false
  options.config = configuration_path or self.options.config
  local controller, reason = self:_start(options)
  if controller == nil then return nil, reason end
  return true
end

function Manager:await_events(window, timeout)
  assert(window ~= nil, "live window controller yielded without a native window")
  assert(type(timeout) == "number" and timeout >= 0, "live window controller yielded an invalid timeout")
  return coroutine.yield({ kind = "wait-events", timeout = timeout, window = window })
end

function Manager:_remove(index)
  table.remove(self.controllers, index)
end

function Manager:_resume(index)
  local controller = self.controllers[index]
  if controller == nil then return true end
  local ok, signal = coroutine.resume(controller.thread)
  if not ok then return nil, signal end
  if coroutine.status(controller.thread) == "dead" then
    self:_remove(index)
    return true
  end
  if type(signal) ~= "table" or signal.kind ~= "wait-events" or signal.window == nil or type(signal.timeout) ~= "number" or signal.timeout < 0 then
    return nil, "live window controller yielded an invalid scheduler signal"
  end
  controller.window = signal.window
  controller.timeout = signal.timeout
  controller.state = "waiting"
  return true
end

function Manager:_start_pending()
  local index = 1
  while index <= #self.controllers do
    if self.controllers[index].state == "new" then
      local resumed, reason = self:_resume(index)
      if not resumed then return nil, reason end
      if self.controllers[index] and self.controllers[index].state == "new" then
        return nil, "live window controller did not enter the event scheduler"
      end
      if self.controllers[index] == nil then
        -- The controller ended during initialization, so the next entry shifted into this index.
      else
        index = index + 1
      end
    else
      index = index + 1
    end
  end
  return true
end

function Manager:_wait_for_controllers()
  local windows = {}
  local timeout
  for _, controller in ipairs(self.controllers) do
    if controller.state == "waiting" then
      windows[#windows + 1] = controller.window
      timeout = timeout and math.min(timeout, controller.timeout) or controller.timeout
    end
  end
  if #windows == 0 then return true end
  -- GLFW owns one process-wide event queue, so controllers yield here rather than polling independently.
  self.window_api.wait_events_for(timeout or 0, windows)
  self.window_api.poll_events_for(windows)
  return true
end

function Manager:_run_controllers()
  local index = 1
  while index <= #self.controllers do
    if self.controllers[index].state == "waiting" then
      local resumed, reason = self:_resume(index)
      if not resumed then return nil, reason end
      if self.controllers[index] == nil then
        -- The controller ended after processing this application event turn.
      else
        index = index + 1
      end
    else
      index = index + 1
    end
  end
  return true
end

function Manager:run()
  if self.options.record and self.options.multi_window_smoke then error("--multi-window-smoke is unavailable while --record is active") end
  local initial = copy_options(self.options)
  initial.application = self
  initial.multi_window_smoke_requester = initial.multi_window_smoke == true
  local started, reason = self:_start(initial)
  if started == nil then error(reason) end
  while #self.controllers > 0 do
    local pending, pending_reason = self:_start_pending()
    if not pending then error(pending_reason) end
    local waited, wait_reason = self:_wait_for_controllers()
    if not waited then error(wait_reason) end
    local ran, run_reason = self:_run_controllers()
    if not ran then error(run_reason) end
  end
end

return Manager
