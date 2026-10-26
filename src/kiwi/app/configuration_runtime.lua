-- File watching, debounce and recoverable errors shared by GTK GL controllers.
local Config = require("kiwi.config")
local Status = require("kiwi.app.configuration_watch")

local Runtime = {}
Runtime.__index = Runtime

function Runtime:load()
  self.dependencies = {}
  return Config.load(self.options.config, nil, {
    appearance = self.appearance,
    command_line_overrides = self.options.configuration_overrides,
    on_dependency = function(path) self.dependencies[#self.dependencies + 1] = path end,
  })
end

function Runtime:sync_watch()
  self.watch = nil
  if not self.window.watch_files or #self.dependencies == 0 then return end
  local paths, known = {}, {}
  for _, path in ipairs(self.dependencies) do
    if not known[path] then paths[#paths + 1] = path; known[path] = true end
  end
  local ok, watch = pcall(self.window.watch_files, self.window, paths)
  if ok then self.watch = watch
  else
    self.status:set_error(watch)
    io.stderr:write("Kiwi automatic configuration reload unavailable: ", tostring(watch), "\n")
  end
end

function Runtime.new(window, host, options)
  local self = setmetatable({ window = window, host = host, options = options,
    status = Status.new(), dependencies = {} }, Runtime)
  self.appearance = host.system_appearance and host.system_appearance(window) or nil
  self.configuration, self.path = self:load()
  self:sync_watch()
  return self
end

function Runtime:request()
  self.requested = true
end

function Runtime:append_watch(ptys)
  if self.configuration.live_config_reload and self.watch then ptys[#ptys + 1] = self.watch end
end

function Runtime:timeout(now, timeout)
  if self.requested then return 0 end
  local deadline = self.configuration.live_config_reload and self.status.deadline
  return deadline and math.min(timeout, math.max(0, deadline - now)) or timeout
end

function Runtime:poll(now, apply)
  if self.configuration.live_config_reload and self.watch then
    local ok, changed = pcall(self.watch.take_changes, self.watch)
    if ok then
      self.status:observe(changed, now)
      if self.status:ready(now) then self.requested = true end
    else
      self.watch = nil
      self.status:set_error(changed)
      io.stderr:write("Kiwi automatic configuration reload unavailable: ", tostring(changed), "\n")
    end
  end
  local appearance = self.host.system_appearance and self.host.system_appearance(self.window) or nil
  if appearance ~= nil and appearance ~= self.appearance then
    self.appearance = appearance
    if self.configuration.theme_mode == "system" then self.requested = true end
  end
  if not self.requested then return false end
  self.requested = false
  self.status:acknowledge()
  local loaded, candidate, path = pcall(self.load, self)
  local ok, applied, reason = false, nil, candidate
  if loaded then ok, applied, reason = pcall(apply, candidate, path) end
  local accepted = loaded and ok and applied == true
  if accepted then
    self.configuration, self.path = candidate, path
    self.status:set_error(nil)
    io.stdout:write("Kiwi configuration reloaded", path and ": " .. path or " (defaults)", "\n")
  else
    local message = not loaded and candidate or not ok and applied or reason or "configuration replacement rejected"
    self.status:set_error(message)
    io.stderr:write("Kiwi configuration reload rejected: ", tostring(message), "\n")
  end
  -- Failed loads can introduce missing theme/shader dependencies. Keep those
  -- watched while the previously accepted policy remains active.
  self:sync_watch()
  return accepted
end

return Runtime
