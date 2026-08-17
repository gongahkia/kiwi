local Workspace = require("kiwi.session.workspace")

local WindowManager = {}
WindowManager.__index = WindowManager

local function positive_integer(value, name)
  assert(type(value) == "number" and value >= 1 and value % 1 == 0, name .. " must be a positive integer")
end

function WindowManager.new(options)
  options = options or {}
  assert(type(options.new_session) == "function", "window manager needs a new-session factory")
  local self = setmetatable({
    maximum_windows = options.maximum_windows or 16,
    new_session = options.new_session,
    next_window_id = 0,
    windows = {},
  }, WindowManager)
  positive_integer(self.maximum_windows, "window manager maximum windows")
  return self
end

function WindowManager:window(id)
  return self.windows[id]
end

function WindowManager:window_count()
  local count = 0
  for _ in pairs(self.windows) do count = count + 1 end
  return count
end

function WindowManager:new_window(options)
  if self:window_count() >= self.maximum_windows then return nil, "window-limit" end
  options = options or {}
  self.next_window_id = self.next_window_id + 1
  local session = options.session or self.new_session()
  local workspace = Workspace.new(options.workspace_options)
  local pane, reason = workspace:new_tab(session)
  if pane == nil then return nil, reason end
  local window = { id = self.next_window_id, workspace = workspace, geometry = options.geometry }
  self.windows[window.id] = window
  return window, pane
end

function WindowManager:close_window(id, close_session)
  local window = self.windows[id]
  if window == nil then return nil, "unknown-window" end
  for _, pane in pairs(window.workspace.panes) do close_session(pane.session) end
  self.windows[id] = nil
  return true
end

function WindowManager:move_pane(source_window_id, pane_id, destination_window_id, destination_tab_id, direction)
  local source = self:window(source_window_id)
  local destination = self:window(destination_window_id)
  if source == nil or destination == nil then return nil, "unknown-window" end
  local pane = source.workspace.panes[pane_id]
  if pane == nil then return nil, "unknown-pane" end
  local attached, reason
  if destination_tab_id == nil then
    attached, reason = destination.workspace:adopt_tab(pane.session)
  else
    attached, reason = destination.workspace:adopt_split(destination_tab_id, direction or "vertical", pane.session)
  end
  if attached == nil then return nil, reason end
  local detached, detach_reason = source.workspace:detach_pane(pane_id)
  if detached == nil then
    destination.workspace:close_pane(attached.id)
    return nil, detach_reason
  end
  return attached
end

function WindowManager:duplicate_pane(source_window_id, destination_window_id, destination_tab_id, direction)
  local source = self:window(source_window_id)
  local destination = self:window(destination_window_id)
  if source == nil or destination == nil then return nil, "unknown-window" end
  local session = self.new_session()
  local pane, reason
  if destination_tab_id == nil then
    pane, reason = destination.workspace:adopt_tab(session)
  else
    pane, reason = destination.workspace:adopt_split(destination_tab_id, direction or "vertical", session)
  end
  if pane == nil then return nil, reason end
  return pane
end

function WindowManager:snapshot()
  local windows = {}
  for _, window in pairs(self.windows) do
    windows[#windows + 1] = { geometry = window.geometry, id = window.id, workspace = window.workspace:snapshot() }
  end
  table.sort(windows, function(left, right) return left.id < right.id end)
  return { schema_version = 1, windows = windows }
end

return WindowManager
