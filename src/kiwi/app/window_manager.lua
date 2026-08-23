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

local function clear_one_shot_smokes(options)
  options.automation_smoke = false
  options.cwd_smoke = false
  options.key_sequence_smoke = false
  options.menu_smoke = false
  options.palette_smoke = false
  options.toolbar_smoke = false
end

local function window_request(manager, request)
  if request == nil then return { kind = "standalone" } end
  if type(request) ~= "table" then return nil, "invalid-window-request" end
  if request.kind == "standalone" and request.source_controller_id == nil then
    return { kind = "standalone" }
  end
  if request.kind ~= "host-tab" then return nil, "invalid-window-request" end
  local source_controller_id = request.source_controller_id
  if type(source_controller_id) ~= "number" or source_controller_id < 1 or source_controller_id % 1 ~= 0 then
    return nil, "invalid-source-window"
  end
  if manager:controller(source_controller_id) == nil then return nil, "unknown-source-window" end
  return { kind = "host-tab", source_controller_id = source_controller_id }
end

function Manager.new(run_window, options, dependencies)
  assert(type(run_window) == "function", "live window manager needs a window controller")
  options = options or {}
  dependencies = dependencies or {}
  local maximum_windows = options.maximum_windows or tonumber(os.getenv("KIWI_MAX_WINDOWS")) or 16
  positive_integer(maximum_windows, "live window manager maximum windows")
  return setmetatable({
    controllers = {},
    layout_dirty = false,
    layout_path = dependencies.layout_path,
    layout_store = dependencies.layout_store,
    maximum_windows = maximum_windows,
    next_controller_id = 0,
    options = options,
    run_window = run_window,
    window_api = dependencies.window_api or Window,
  }, Manager)
end

function Manager:window_count()
  return #self.controllers
end

function Manager:controller(id)
  for _, controller in ipairs(self.controllers) do
    if controller.id == id then return controller end
  end
end

function Manager:_start(options)
  if self:window_count() >= self.maximum_windows then return nil, "window-limit" end
  self.next_controller_id = self.next_controller_id + 1
  options.controller_id = self.next_controller_id
  local controller = { id = options.controller_id, options = options, state = "new" }
  controller.thread = coroutine.create(function()
    self.run_window(options)
  end)
  self.controllers[#self.controllers + 1] = controller
  return controller
end

function Manager:register_controller(id, adapter)
  local controller = self:controller(id)
  if controller == nil then return nil, "unknown-window" end
  assert(type(adapter) == "table" and type(adapter.snapshot) == "function", "live window controller needs a layout snapshot adapter")
  controller.adapter = adapter
  self.layout_dirty = true
  return true
end

function Manager:unregister_controller(id)
  local controller = self:controller(id)
  if controller == nil then return nil, "unknown-window" end
  local registered = 0
  for _, item in ipairs(self.controllers) do
    if item.adapter then registered = registered + 1 end
  end
  if registered == 1 and controller.adapter then self.final_layout = self:snapshot() end
  controller.adapter = nil
  self.layout_dirty = true
  return true
end

function Manager:mark_layout_dirty()
  self.layout_dirty = true
end

function Manager:snapshot()
  local windows = {}
  for _, controller in ipairs(self.controllers) do
    if controller.adapter then
      local snapshot = controller.adapter.snapshot()
      assert(type(snapshot) == "table" and type(snapshot.geometry) == "table" and type(snapshot.workspace) == "table", "live window controller returned an invalid layout snapshot")
      windows[#windows + 1] = { geometry = snapshot.geometry, id = controller.id, workspace = snapshot.workspace }
    end
  end
  table.sort(windows, function(left, right) return left.id < right.id end)
  return { schema_version = 1, windows = windows }
end

function Manager:_write_layout()
  if not self.layout_dirty or not self.layout_store or self.options.layout_persistence == false then return true end
  local snapshot = self.final_layout or self:snapshot()
  local written, reason = self.layout_store.write(self.layout_path, snapshot)
  if not written then return nil, reason end
  self.final_layout = nil
  self.layout_dirty = false
  return true
end

function Manager:_read_layout()
  if not self.layout_store or self.options.layout_restore == false or self.options.record then return nil end
  local snapshot, reason = self.layout_store.load(self.layout_path)
  if snapshot then return snapshot end
  if reason ~= "missing" then io.stderr:write("Kiwi layout restore skipped: ", reason or "unavailable", "\n") end
  return nil
end

local function moved_window_geometry(adapter)
  local snapshot = adapter.snapshot()
  local geometry = snapshot.geometry
  return {
    height = geometry.height,
    width = geometry.width,
    x = math.max(-32768, math.min(32768, geometry.x + 36)),
    y = math.max(-32768, math.min(32768, geometry.y + 36)),
  }
end

function Manager:move_active_to_new_window(source_id)
  if self.options.record then return nil, "session moves are unavailable while --record is active" end
  local source = self:controller(source_id)
  if source == nil or source.adapter == nil then return nil, "unknown-window" end
  if self:window_count() >= self.maximum_windows then return nil, "window-limit" end
  local session, reason = source.adapter.begin_transfer()
  if session == nil then return nil, reason end
  local options = copy_options(self.options)
  options.application = self
  options.command = nil
  options.geometry = moved_window_geometry(source.adapter)
  options.moved_session = session
  options.host_tab = false
  options.host_tab_source_id = nil
  options.transfer_source_id = source.id
  options.workspace_smoke = false
  options.multi_window_smoke_requester = false
  options.session_move_smoke_requester = false
  local target, target_reason = self:_start(options)
  if target == nil then
    assert(source.adapter.restore_transfer(session))
    return nil, target_reason
  end
  self.layout_dirty = true
  return true
end

function Manager:move_active_to_next_window(source_id)
  if self.options.record then return nil, "session moves are unavailable while --record is active" end
  local source = self:controller(source_id)
  if source == nil or source.adapter == nil then return nil, "unknown-window" end
  local destination
  for _, candidate in ipairs(self.controllers) do
    if candidate.id ~= source.id and candidate.adapter then destination = candidate break end
  end
  if destination == nil then return nil, "no-other-window" end
  local session, reason = source.adapter.begin_transfer()
  if session == nil then return nil, reason end
  local accepted, accept_reason = destination.adapter.accept_transfer(session)
  if not accepted then
    assert(source.adapter.restore_transfer(session))
    return nil, accept_reason
  end
  assert(source.adapter.complete_transfer(session))
  self.layout_dirty = true
  return true
end

function Manager:duplicate_active_to_next_window(source_id)
  if self.options.record then return nil, "session duplication is unavailable while --record is active" end
  local source = self:controller(source_id)
  if source == nil or source.adapter == nil then return nil, "unknown-window" end
  local destination
  for _, candidate in ipairs(self.controllers) do
    if candidate.id ~= source.id and candidate.adapter then destination = candidate break end
  end
  if destination == nil then return nil, "no-other-window" end
  local session, session_reason = source.adapter.new_session()
  if session == nil then return nil, session_reason or "session-create-failed" end
  local accepted, reason = destination.adapter.accept_transfer(session)
  if not accepted then source.adapter.destroy_session(session); return nil, reason end
  self.layout_dirty = true
  return true
end

function Manager:confirm_transfer(target_id)
  local target = self:controller(target_id)
  if target == nil or target.options.transfer_source_id == nil or target.options.moved_session == nil then return nil, "unknown-transfer" end
  local source = self:controller(target.options.transfer_source_id)
  if source == nil or source.adapter == nil then return nil, "transfer-source-closed" end
  assert(source.adapter.complete_transfer(target.options.moved_session))
  target.options.transfer_confirmed = true
  self.layout_dirty = true
  return true
end

function Manager:_restore_failed_transfer(controller)
  if controller.options.transfer_confirmed or controller.options.moved_session == nil or controller.options.transfer_source_id == nil then return end
  local source = self:controller(controller.options.transfer_source_id)
  if source and source.adapter then
    local restored = source.adapter.restore_transfer(controller.options.moved_session)
    if restored then controller.options.moved_session = nil end
  end
end

function Manager:request_window(configuration_path, request)
  if self.options.record then return nil, "new windows are unavailable while --record is active" end
  local intent, intent_reason = window_request(self, request)
  if intent == nil then return nil, intent_reason end
  local options = copy_options(self.options)
  options.application = self
  options.command = nil
  options.multi_window_smoke_requester = false
  options.session_move_smoke_requester = false
  options.workspace_smoke = false
  options.host_tab = intent.kind == "host-tab"
  options.host_tab_source_id = intent.source_controller_id
  clear_one_shot_smokes(options)
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
  self:_restore_failed_transfer(self.controllers[index])
  table.remove(self.controllers, index)
end

function Manager:_resume(index)
  local controller = self.controllers[index]
  if controller == nil then return true end
  local ok, signal = coroutine.resume(controller.thread)
  if not ok then
    self:_restore_failed_transfer(controller)
    return nil, signal
  end
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
  local restored = self:_read_layout()
  if restored then
    for _, item in ipairs(restored.windows) do
      local options = copy_options(self.options)
      options.application = self
      options.command = nil
      options.geometry = item.geometry
      options.restored_workspace = item.workspace
      options.layout_restored = true
      options.host_tab = false
      options.workspace_smoke = false
      options.multi_window_smoke_requester = false
      options.session_move_smoke_requester = false
      local started, reason = self:_start(options)
      if started == nil then error(reason) end
    end
  else
    local initial = copy_options(self.options)
    initial.application = self
    initial.multi_window_smoke_requester = initial.multi_window_smoke == true
    initial.session_move_smoke_requester = initial.session_move_smoke == true
    local started, reason = self:_start(initial)
    if started == nil then error(reason) end
  end
  while #self.controllers > 0 do
    local pending, pending_reason = self:_start_pending()
    if not pending then error(pending_reason) end
    local waited, wait_reason = self:_wait_for_controllers()
    if not waited then error(wait_reason) end
    local ran, run_reason = self:_run_controllers()
    if not ran then error(run_reason) end
    local written, write_reason = self:_write_layout()
    if not written then io.stderr:write("Kiwi layout persistence failed: ", write_reason or "unavailable", "\n") end
  end
  local written, write_reason = self:_write_layout()
  if not written then io.stderr:write("Kiwi layout persistence failed: ", write_reason or "unavailable", "\n") end
end

return Manager
