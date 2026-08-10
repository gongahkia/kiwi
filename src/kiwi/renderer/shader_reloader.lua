local Reloader = {}
Reloader.__index = Reloader

local default_diagnostic_limit = 16
local max_diagnostic_bytes = 4096

local function compact(message)
  message = tostring(message)
  if #message <= max_diagnostic_bytes then return message end
  return message:sub(1, max_diagnostic_bytes) .. "..."
end

local function configured_paths(paths)
  local result = {}
  for _, path in ipairs(paths or {}) do
    assert(type(path) == "string" and #path > 0, "shader development path must be a non-empty string")
    result[path] = true
  end
  return result
end

local function active_definition(pass)
  assert(type(pass) == "table" and type(pass.name) == "string", "shader reload pass must have a name")
  local shader = assert(pass.shader, "shader reload pass " .. pass.name .. " has no active shader")
  assert(type(shader.id) == "string" and type(shader.pass) == "string" and type(shader.path) == "string", "shader reload pass " .. pass.name .. " has an invalid active shader")
  assert(type(shader.source_fingerprint) == "string", "shader reload pass " .. pass.name .. " has no shader fingerprint")
  assert(pass.pipeline ~= nil, "shader reload pass " .. pass.name .. " has no active pipeline")
  assert(type(pass.pipeline_label) == "string" and type(pass.vertex_entry) == "string" and type(pass.fragment_entry) == "string", "shader reload pass " .. pass.name .. " has no pipeline definition")
  return { id = shader.id, pass = shader.pass, path = shader.path }
end

local function configured_passes(self, passes)
  local result = {}
  for _, pass in ipairs(passes) do
    if pass.shader and self.paths[pass.shader.path] then
      local definition = active_definition(pass)
      result[#result + 1] = { pass = pass, definition = definition }
    end
  end
  return result
end

local function retained_passes(items)
  local names = {}
  for _, item in ipairs(items) do names[#names + 1] = item.pass.name end
  return table.concat(names, ", ")
end

function Reloader.new(options)
  options = options or {}
  local enabled = options.enabled == true
  local paths = configured_paths(options.paths)
  if enabled then
    assert(next(paths) ~= nil, "enabled shader reload needs an explicit development path")
  end
  local diagnostic_limit = options.diagnostic_limit or default_diagnostic_limit
  assert(type(diagnostic_limit) == "number" and diagnostic_limit >= 1 and diagnostic_limit % 1 == 0, "shader reload diagnostic limit must be a positive integer")
  local poll_interval = options.poll_interval or 0.25
  assert(type(poll_interval) == "number" and poll_interval >= 0, "shader reload poll interval must be non-negative")
  return setmetatable({
    enabled = enabled,
    paths = paths,
    loader = assert(options.loader, "shader reloader needs a shader loader"),
    diagnostic_limit = diagnostic_limit,
    diagnostics = {},
    observed = {},
    attempted = {},
    poll_interval = poll_interval,
    next_poll = 0,
  }, Reloader)
end

function Reloader:is_enabled()
  return self.enabled
end

function Reloader:record(level, message)
  message = compact(message)
  local previous = self.diagnostics[#self.diagnostics]
  if previous and previous.level == level and previous.message == message then return end
  self.diagnostics[#self.diagnostics + 1] = { level = level, message = message }
  while #self.diagnostics > self.diagnostic_limit do table.remove(self.diagnostics, 1) end
end

function Reloader:history()
  local copy = {}
  for index, diagnostic in ipairs(self.diagnostics) do
    copy[index] = { level = diagnostic.level, message = diagnostic.message }
  end
  return copy
end

function Reloader:track(passes)
  if not self.enabled then return end
  for _, item in ipairs(configured_passes(self, passes)) do
    self.observed[item.definition.path] = item.pass.shader.source_fingerprint
    self.attempted[item.definition.path] = item.pass.shader.source_fingerprint
  end
end

function Reloader:reject(items, path, detail)
  local message = string.format(
    "shader hot reload rejected source %s; retained last-known-good module/pipeline for passes %s: %s",
    path,
    retained_passes(items),
    compact(detail)
  )
  self:record("error", message)
  return false, message
end

local function release_candidates(owner, candidates)
  for index = #candidates, 1, -1 do
    local candidate = candidates[index]
    pcall(owner.release_native, owner, candidate.pipeline)
    pcall(candidate.shader.release)
  end
end

function Reloader:reload(owner, passes, force)
  if not self.enabled then
    return false, "shader hot reload is disabled outside explicit development mode"
  end
  local items = configured_passes(self, passes)
  if #items == 0 then
    return nil, "no active shader uses an explicitly configured development path"
  end

  local sources = {}
  for _, item in ipairs(items) do
    local path = item.definition.path
    if sources[path] == nil then
      local ok, source = pcall(self.loader.read, self.loader, item.definition)
      if not ok then return self:reject(items, path, source) end
      sources[path] = { source = source, fingerprint = self.loader:fingerprint(source) }
    end
  end

  local changed = {}
  local retry = force
  for path, source in pairs(sources) do
    if force or source.fingerprint ~= self.observed[path] then changed[path] = true end
    if source.fingerprint ~= self.attempted[path] then retry = true end
  end
  if next(changed) == nil then return nil, "shader source unchanged" end
  if not retry then return nil, "shader source remains rejected" end

  local candidates = {}
  for _, item in ipairs(items) do
    if changed[item.definition.path] then
      local source = sources[item.definition.path]
      local ok, shader = pcall(self.loader.load_source, self.loader, item.definition, source.source)
      if not ok then
        release_candidates(owner, candidates)
        for path, observed_source in pairs(sources) do self.attempted[path] = observed_source.fingerprint end
        return self:reject(items, item.definition.path, shader)
      end
      local pipeline_ok, pipeline = pcall(owner.create_pipeline, owner, item.pass.pipeline_label, item.pass.vertex_entry, item.pass.fragment_entry, shader)
      if not pipeline_ok then
        pcall(shader.release)
        release_candidates(owner, candidates)
        for path, observed_source in pairs(sources) do self.attempted[path] = observed_source.fingerprint end
        return self:reject(items, item.definition.path, pipeline)
      end
      candidates[#candidates + 1] = { pass = item.pass, shader = shader, pipeline = pipeline }
    end
  end

  for _, candidate in ipairs(candidates) do
    candidate.previous_shader = candidate.pass.shader
    candidate.previous_pipeline = candidate.pass.pipeline
    candidate.pass.shader = candidate.shader
    candidate.pass.pipeline = candidate.pipeline
  end
  for _, candidate in ipairs(candidates) do
    owner:release_native(candidate.previous_pipeline)
    candidate.previous_shader.release()
  end
  local paths = {}
  for path, source in pairs(sources) do
    if changed[path] then
      self.observed[path] = source.fingerprint
      self.attempted[path] = source.fingerprint
      paths[#paths + 1] = path
    end
  end
  table.sort(paths)
  local message = "shader hot reload applied source " .. table.concat(paths, ", ")
  self:record("info", message)
  return true, message
end

function Reloader:poll(owner, passes, time)
  if not self.enabled then return nil, "shader hot reload is disabled" end
  assert(type(time) == "number", "shader reload poll time must be a number")
  if time < self.next_poll then return nil, "shader reload poll is not due" end
  self.next_poll = time + self.poll_interval
  return self:reload(owner, passes, false)
end

return Reloader
