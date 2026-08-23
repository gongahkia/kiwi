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
  assert(type(context.application) == "table", "product action dispatcher needs an application")
  assert(type(context.configuration) == "function", "product action dispatcher needs configuration access")
  assert(type(context.configuration_path) == "function", "product action dispatcher needs configuration path access")
  assert(type(context.set_configuration_path) == "function", "product action dispatcher needs configuration path mutation")
  assert(type(context.active_session) == "function", "product action dispatcher needs active-session access")
  assert(type(context.create_split) == "function" and type(context.create_tab) == "function", "product action dispatcher needs workspace creation")
  assert(type(context.close_active_pane) == "function" and type(context.focus_next_tab) == "function", "product action dispatcher needs workspace navigation")
  assert(type(context.request_configuration_reload) == "function", "product action dispatcher needs configuration reload access")
  assert(type(context.host) == "table" and context.window ~= nil, "product action dispatcher needs a host window")
  return setmetatable({ context = context }, Dispatcher)
end

function Dispatcher:handle(action)
  local context = self.context
  if action == "command-palette" then
    if type(context.host.show_command_palette) ~= "function" then
      report(context, "Kiwi command palette unavailable: this host has no native palette bridge")
      return true, false
    end
    local configuration = context.configuration()
    local opened, reason = context.host.show_command_palette(context.window, Actions.palette_entries(configuration.command_palette_entries), function(selected)
      local handled, layout_changed = self:handle(selected)
      if handled and layout_changed then context.application:mark_layout_dirty() end
    end)
    if not opened then report(context, "Kiwi command palette unavailable: " .. (reason or "unknown error")) end
    return true, false
  end
  if action == "next-tab" then
    return true, context.focus_next_tab() == true
  end
  if action == "new-tab" then
    local created, reason = context.create_tab()
    if not created then rejected(context, "tab creation", reason) end
    return true, created == true
  end
  if action == "new-window" then
    local opened, reason = context.application:request_window(context.configuration_path())
    if not opened then rejected(context, "new-window request", reason) end
    return true, false
  end
  if action == "open-configuration" then
    if type(context.host.open_text_file) ~= "function" then
      report(context, "Kiwi configuration opener unavailable: this host has no text-file opener")
      return true, false
    end
    local path = Config.edit_path(context.explicit_configuration_path, context.configuration_path(), nil, context.host.platform)
    if path == nil then
      report(context, "Kiwi configuration opener unavailable: no default configuration path")
      return true, false
    end
    if context.configuration_path() == nil then
      local initialized, reason = (context.ensure_configuration_file or Filesystem.ensure_new_file)(path, Config.edit_template)
      if not initialized then
        rejected(context, "configuration initialization", reason)
        return true, false
      end
      context.set_configuration_path(path)
    end
    local opened, reason = context.host.open_text_file(context.window, path)
    if not opened then rejected(context, "configuration opener", reason) end
    return true, false
  end
  if action == "move-session-new-window" or action == "move-session-next-window" then
    local session = context.active_session()
    if context.session_move_smoke_requester then session.session_move_smoke_source_id = context.controller_id end
    local moved, reason
    if action == "move-session-next-window" then
      moved, reason = context.application:move_active_to_next_window(context.controller_id)
    else
      moved, reason = context.application:move_active_to_new_window(context.controller_id)
    end
    if not moved then rejected(context, "session move", reason) end
    return true, moved == true
  end
  if action == "duplicate-session-new-window" or action == "duplicate-session-next-window" then
    local duplicated, reason
    if action == "duplicate-session-next-window" then
      duplicated, reason = context.application:duplicate_active_to_next_window(context.controller_id)
    else
      duplicated, reason = context.application:request_window(context.configuration_path())
    end
    if not duplicated then rejected(context, "session duplication", reason) end
    return true, false
  end
  if action == "close-pane" then
    local closed, reason = context.close_active_pane()
    if not closed then rejected(context, "pane closure", reason) end
    return true, closed == true
  end
  if action == "split-right" or action == "split-down" then
    local direction = action == "split-right" and "vertical" or "horizontal"
    local created, reason = context.create_split(direction)
    if not created then rejected(context, direction .. " split", reason) end
    return true, created == true
  end
  if action == "reload-config" then
    context.request_configuration_reload()
    return true, false
  end
  return false, false
end

return Dispatcher
