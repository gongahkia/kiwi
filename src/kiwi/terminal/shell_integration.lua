local Utf8 = require("kiwi.terminal.utf8")

local ShellIntegration = {}
ShellIntegration.__index = ShellIntegration

ShellIntegration.maximum_cwd_bytes = 2048
ShellIntegration.default_event_limit = 512
ShellIntegration.default_directory_limit = 128

local marker_kinds = {
  A = "prompt",
  B = "command_start",
  C = "command_executed",
}

local function valid_utf8(value)
  local valid = true
  local decoder = Utf8.Decoder.new(function(_, _, replaced)
    if replaced then valid = false end
  end)
  for index = 1, #value do decoder:feed_byte(value:byte(index)) end
  decoder:finish()
  return valid
end

local function valid_ascii_uri(value, maximum)
  if type(value) ~= "string" or #value == 0 or #value > maximum or value:find("\0", 1, true) or not valid_utf8(value) then return false end
  for index = 1, #value do
    local byte = value:byte(index)
    if byte <= 0x20 or byte >= 0x7f then return false end
  end
  return true
end

function ShellIntegration.parse_cwd(value, maximum_bytes)
  maximum_bytes = maximum_bytes or ShellIntegration.maximum_cwd_bytes
  if not valid_ascii_uri(value, maximum_bytes) then return nil, "invalid-cwd" end
  local host, path = value:match("^file://([^/]*)(/.*)$")
  if host == nil or path == nil or host:match("^[A-Za-z0-9%._%-%[%]:]*$") == nil or path:find("[?#]", 1) then return nil, "invalid-cwd" end
  return { host = host, path = path, uri = value }
end

function ShellIntegration.parse_marker(value)
  if type(value) ~= "string" then return nil, "invalid-marker" end
  local kind = marker_kinds[value]
  if kind then return { kind = kind } end
  if value == "D" then return { kind = "command_finished" } end
  local status = value:match("^D;(%d+)$")
  if status == nil then
    if value:match("^[A-D]") then return nil, "invalid-marker" end
    if value:match("^[A-Za-z]") then return nil, "unknown-marker" end
    return nil, "invalid-marker"
  end
  status = tonumber(status)
  if status > 255 then return nil, "invalid-marker" end
  return { exit_status = status, kind = "command_finished" }
end

local function copy_event(event)
  return {
    column = event.column,
    cwd_id = event.cwd_id,
    exit_status = event.exit_status,
    kind = event.kind,
    line_id = event.line_id,
    scope = event.scope,
    timestamp = event.timestamp,
  }
end

function ShellIntegration.new(options)
  options = options or {}
  local event_limit = options.event_limit or ShellIntegration.default_event_limit
  local directory_limit = options.directory_limit or ShellIntegration.default_directory_limit
  local maximum_cwd_bytes = options.maximum_cwd_bytes or ShellIntegration.maximum_cwd_bytes
  assert(type(event_limit) == "number" and event_limit >= 1 and event_limit % 1 == 0, "shell event limit must be a positive integer")
  assert(type(directory_limit) == "number" and directory_limit >= 1 and directory_limit % 1 == 0, "shell directory limit must be a positive integer")
  assert(type(maximum_cwd_bytes) == "number" and maximum_cwd_bytes >= 1 and maximum_cwd_bytes % 1 == 0, "shell current-directory limit must be a positive integer")
  return setmetatable({
    current_directory = nil,
    directories = {},
    directory_limit = directory_limit,
    directory_order = {},
    event_limit = event_limit,
    events = {},
    maximum_cwd_bytes = maximum_cwd_bytes,
    next_directory_id = 0,
    next_timestamp = 0,
    stats = { directories_dropped = 0, events_dropped = 0, markers_unknown = 0, rejected = 0 },
  }, ShellIntegration)
end

function ShellIntegration:clear()
  self.current_directory = nil
  self.directories = {}
  self.directory_order = {}
  self.events = {}
  self.next_directory_id = 0
  self.next_timestamp = 0
end

function ShellIntegration:record(kind, position, exit_status)
  self.next_timestamp = self.next_timestamp + 1
  local current = self.current_directory
  local event = {
    column = position.column,
    cwd_id = current and current.id or nil,
    exit_status = exit_status,
    kind = kind,
    line_id = position.line_id,
    scope = position.scope,
    timestamp = self.next_timestamp,
  }
  self.events[#self.events + 1] = event
  if #self.events > self.event_limit then
    table.remove(self.events, 1)
    self.stats.events_dropped = self.stats.events_dropped + 1
  end
  return event
end

function ShellIntegration:remember_directory(directory)
  self.next_directory_id = self.next_directory_id + 1
  directory.id = self.next_directory_id
  self.directories[directory.id] = directory
  self.directory_order[#self.directory_order + 1] = directory.id
  while #self.directory_order > self.directory_limit do
    local id = table.remove(self.directory_order, 1)
    self.directories[id] = nil
    self.stats.directories_dropped = self.stats.directories_dropped + 1
  end
  self.current_directory = directory
  return directory
end

function ShellIntegration:apply_cwd(value, position)
  local directory, status = ShellIntegration.parse_cwd(value, self.maximum_cwd_bytes)
  if directory == nil then
    self.stats.rejected = self.stats.rejected + 1
    return nil, status
  end
  self:remember_directory(directory)
  return self:record("cwd", position), "accepted"
end

function ShellIntegration:apply_marker(value, position)
  local marker, status = ShellIntegration.parse_marker(value)
  if marker == nil then
    if status == "unknown-marker" then self.stats.markers_unknown = self.stats.markers_unknown + 1 else self.stats.rejected = self.stats.rejected + 1 end
    return nil, status
  end
  return self:record(marker.kind, position, marker.exit_status), "accepted"
end

function ShellIntegration:remap_positions(scope, mapper)
  assert(type(mapper) == "function", "shell integration remap requires a mapper")
  for _, event in ipairs(self.events) do
    if event.scope == scope then
      local remapped = mapper(event)
      if remapped then
        event.column = remapped.column
        event.line_id = remapped.line_id
      end
    end
  end
end

function ShellIntegration:view()
  local events = {}
  for index, event in ipairs(self.events) do events[index] = copy_event(event) end
  local current = self.current_directory
  return {
    current_directory = current and { host = current.host, id = current.id, path = current.path, uri = current.uri } or nil,
    events = events,
    stats = {
      directories_dropped = self.stats.directories_dropped,
      events_dropped = self.stats.events_dropped,
      markers_unknown = self.stats.markers_unknown,
      rejected = self.stats.rejected,
    },
  }
end

function ShellIntegration:snapshot()
  local events = {}
  for index, event in ipairs(self.events) do events[index] = copy_event(event) end
  return {
    current_directory_id = self.current_directory and self.current_directory.id or nil,
    events = events,
    stats = {
      directories_dropped = self.stats.directories_dropped,
      events_dropped = self.stats.events_dropped,
      markers_unknown = self.stats.markers_unknown,
      rejected = self.stats.rejected,
    },
  }
end

return ShellIntegration
