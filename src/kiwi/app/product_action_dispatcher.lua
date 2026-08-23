-- Product actions are host-neutral application intents. Native menus, the
-- command palette, local keybindings, and future automation adapters all
-- enter through this dispatcher rather than growing controller-specific paths.
local Actions = require("kiwi.app.actions")
local Config = require("kiwi.config")
local Filesystem = require("kiwi.platform.filesystem")

local Dispatcher = {}
Dispatcher.__index = Dispatcher

local function report(context, message)
  if type(context.report) == "function" then context.report(message) end
end

local function rejected(context, subject, reason)
  report(context, "Kiwi " .. subject .. " rejected: " .. (reason or "unavailable"))
end

function Dispatcher.new(context)
  assert(type(context) == "table", "product action dispatcher needs a context")
  return setmetatable({ context = context }, Dispatcher)
end

local function function_capability(context, subject, name)
  local callback = context[name]
  if type(callback) == "function" then return callback end
  rejected(context, subject, "missing " .. name)
end

local function application_capability(context, subject, name)
  local application = context.application
  local callback = type(application) == "table" and application[name] or nil
  if type(callback) == "function" then return application, callback end
  rejected(context, subject, "missing application." .. name)
end

function Dispatcher:handle(action)
  local context = self.context
  if action == "command-palette" then
    local host = context.host
    local configuration = function_capability(context, "command palette", "configuration")
    local application, mark_layout_dirty = application_capability(context, "command palette", "mark_layout_dirty")
    if type(host) ~= "table" or type(host.show_command_palette) ~= "function" or context.window == nil or configuration == nil or application == nil then
      report(context, "Kiwi command palette unavailable: this host has no native palette bridge")
      return true, false
    end
    local opened, reason = host.show_command_palette(context.window, Actions.palette_entries(configuration().command_palette_entries), function(selected)
      local handled, layout_changed = self:handle(selected)
      if handled and layout_changed then mark_layout_dirty(application) end
    end)
    if not opened then report(context, "Kiwi command palette unavailable: " .. (reason or "unknown error")) end
    return true, false
  end
  if action == "next-tab" then
    local focus_next_tab = function_capability(context, "next-tab", "focus_next_tab")
    return true, focus_next_tab and focus_next_tab() == true or false
  end
  if action == "new-tab" then
    local create_tab = function_capability(context, "new-tab", "create_tab")
    if create_tab == nil then return true, false end
    local created, reason = create_tab()
    if not created then rejected(context, "tab creation", reason) end
    return true, created == true
  end
  if action == "new-window" then
    local application, request_window = application_capability(context, "new-window", "request_window")
    local configuration_path = function_capability(context, "new-window", "configuration_path")
    if application == nil or configuration_path == nil then return true, false end
    local opened, reason = request_window(application, configuration_path(), { kind = "standalone" })
    if not opened then rejected(context, "new-window request", reason) end
    return true, false
  end
  if action == "open-configuration" then
    local host = context.host
    local configuration_path = function_capability(context, "configuration opener", "configuration_path")
    local set_configuration_path = function_capability(context, "configuration opener", "set_configuration_path")
    if type(host) ~= "table" or type(host.open_text_file) ~= "function" or context.window == nil or configuration_path == nil or set_configuration_path == nil then
      report(context, "Kiwi configuration opener unavailable: this host has no text-file opener")
      return true, false
    end
    local path = Config.edit_path(context.explicit_configuration_path, configuration_path(), nil, host.platform)
    if path == nil then
      report(context, "Kiwi configuration opener unavailable: no default configuration path")
      return true, false
    end
    if configuration_path() == nil then
      local initialized, reason = (context.ensure_configuration_file or Filesystem.ensure_new_file)(path, Config.edit_template)
      if not initialized then
        rejected(context, "configuration initialization", reason)
        return true, false
      end
      set_configuration_path(path)
    end
    local opened, reason = host.open_text_file(context.window, path)
    if not opened then rejected(context, "configuration opener", reason) end
    return true, false
  end
  if action == "move-session-new-window" or action == "move-session-next-window" then
    local active_session = function_capability(context, "session move", "active_session")
    local application, move_session = application_capability(context, "session move", action == "move-session-next-window" and "move_active_to_next_window" or "move_active_to_new_window")
    if active_session == nil or application == nil then return true, false end
    local session = active_session()
    if type(session) ~= "table" then
      rejected(context, "session move", "no active terminal session")
      return true, false
    end
    if context.session_move_smoke_requester then session.session_move_smoke_source_id = context.controller_id end
    local moved, reason
    if action == "move-session-next-window" then
      moved, reason = move_session(application, context.controller_id)
    else
      moved, reason = move_session(application, context.controller_id)
    end
    if not moved then rejected(context, "session move", reason) end
    return true, moved == true
  end
  if action == "duplicate-session-new-window" or action == "duplicate-session-next-window" then
    local duplicated, reason
    if action == "duplicate-session-next-window" then
      local application, duplicate_active_to_next_window = application_capability(context, "session duplication", "duplicate_active_to_next_window")
      if application == nil then return true, false end
      duplicated, reason = duplicate_active_to_next_window(application, context.controller_id)
    else
      local application, request_window = application_capability(context, "session duplication", "request_window")
      local configuration_path = function_capability(context, "session duplication", "configuration_path")
      if application == nil or configuration_path == nil then return true, false end
      duplicated, reason = request_window(application, configuration_path(), { kind = "standalone" })
    end
    if not duplicated then rejected(context, "session duplication", reason) end
    return true, false
  end
  if action == "close-pane" then
    local close_active_pane = function_capability(context, "close-pane", "close_active_pane")
    if close_active_pane == nil then return true, false end
    local closed, reason = close_active_pane()
    if not closed then rejected(context, "pane closure", reason) end
    return true, closed == true
  end
  if action == "split-right" or action == "split-down" then
    local direction = action == "split-right" and "vertical" or "horizontal"
    local create_split = function_capability(context, direction .. " split", "create_split")
    if create_split == nil then return true, false end
    local created, reason = create_split(direction)
    if not created then rejected(context, direction .. " split", reason) end
    return true, created == true
  end
  if action == "reload-config" then
    local request_configuration_reload = function_capability(context, "reload-config", "request_configuration_reload")
    if request_configuration_reload == nil then return true, false end
    request_configuration_reload()
    return true, false
  end
  return false, false
end

return Dispatcher
