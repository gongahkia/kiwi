local CommandRegions = {}
CommandRegions.__index = CommandRegions

CommandRegions.default_limit = 256
CommandRegions.default_row_reference_limit = 8

local function copy_position(position)
  return { column = position.column, line_id = position.line_id, scope = position.scope }
end

local function copy_region(region)
  local recovery
  if region.recovery then
    recovery = {}
    for index, reason in ipairs(region.recovery) do recovery[index] = reason end
  end
  return {
    command_start = region.command_start and copy_position(region.command_start) or nil,
    coverage = region.reference_overflow and "truncated"
      or region.row_count == 0 and "none"
      or region.retained_rows == 0 and "evicted"
      or region.retained_rows == region.row_count and "retained"
      or "partial",
    cwd_id = region.cwd_id,
    exit_status = region.exit_status,
    finish = region.finish and copy_position(region.finish) or nil,
    id = region.id,
    interruption = region.interruption,
    output_start = region.output_start and copy_position(region.output_start) or nil,
    prompt_start = region.prompt_start and copy_position(region.prompt_start) or nil,
    recovery = recovery,
    reference_overflow = region.reference_overflow,
    retained_rows = region.retained_rows,
    row_count = region.row_count,
    scope = region.scope,
    start = copy_position(region.start),
    state = region.state,
  }
end

local function recover(self, region, reason)
  region.recovery = region.recovery or {}
  region.recovery[#region.recovery + 1] = reason
  self.stats.recovered = self.stats.recovered + 1
end

local function copy_stats(stats)
  return {
    dropped = stats.dropped,
    interrupted = stats.interrupted,
    orphaned = stats.orphaned,
    recovered = stats.recovered,
    repeated = stats.repeated,
  }
end

function CommandRegions.new(options)
  options = options or {}
  local limit = options.limit or CommandRegions.default_limit
  local row_reference_limit = options.row_reference_limit or CommandRegions.default_row_reference_limit
  assert(type(limit) == "number" and limit >= 1 and limit % 1 == 0, "command-region limit must be a positive integer")
  assert(type(row_reference_limit) == "number" and row_reference_limit >= 1 and row_reference_limit % 1 == 0, "command-region row-reference limit must be a positive integer")
  return setmetatable({
    by_id = {},
    limit = limit,
    next_id = 0,
    open = nil,
    regions = {},
    row_reference_limit = row_reference_limit,
    stats = { dropped = 0, interrupted = 0, orphaned = 0, recovered = 0, repeated = 0 },
  }, CommandRegions)
end

function CommandRegions:clear()
  self.by_id = {}
  self.next_id = 0
  self.open = nil
  self.regions = {}
end

function CommandRegions:append(event, state, recovery)
  self.next_id = self.next_id + 1
  local position = copy_position(event)
  local region = {
    cwd_id = event.cwd_id,
    id = self.next_id,
    last_position = position,
    retained_rows = 0,
    row_count = 0,
    scope = event.scope,
    start = position,
    state = state,
  }
  if state == "prompt" then region.prompt_start = copy_position(event) end
  if state == "command" then region.command_start = copy_position(event) end
  if state == "output" then region.output_start = copy_position(event) end
  self.regions[#self.regions + 1] = region
  self.by_id[region.id] = region
  if #self.regions > self.limit then
    local dropped = table.remove(self.regions, 1)
    self.by_id[dropped.id] = nil
    self.stats.dropped = self.stats.dropped + 1
  end
  self.open = region
  if recovery then recover(self, region, recovery) end
  return region
end

function CommandRegions:active_id()
  return self.open and self.open.id or nil
end

function CommandRegions:attach_row(id)
  local region = self.by_id[id]
  if region == nil then return false end
  region.row_count = region.row_count + 1
  region.retained_rows = region.retained_rows + 1
  return true
end

function CommandRegions:release_row(ids)
  for _, id in ipairs(ids or {}) do
    local region = self.by_id[id]
    if region and region.retained_rows > 0 then region.retained_rows = region.retained_rows - 1 end
  end
end

function CommandRegions:mark_row_reference_overflow(id)
  local region = self.by_id[id]
  if region then region.reference_overflow = true end
end

function CommandRegions:reconcile_rows(rows)
  local retained = {}
  for _, row in ipairs(rows) do
    for _, id in ipairs(row.command_region_ids or {}) do
      if self.by_id[id] then retained[id] = (retained[id] or 0) + 1 end
    end
  end
  for _, region in ipairs(self.regions) do region.retained_rows = retained[region.id] or 0 end
end

function CommandRegions:finish(region, position, state, exit_status, interruption)
  region.finish = copy_position(position)
  region.last_position = copy_position(position)
  region.exit_status = exit_status
  region.state = state
  if interruption then region.interruption = interruption end
  if state == "interrupted" then self.stats.interrupted = self.stats.interrupted + 1 end
  self.open = nil
  return region
end

function CommandRegions:transition_to_command(region, event)
  region.command_start = copy_position(event)
  region.last_position = copy_position(event)
  region.state = "command"
  return region
end

function CommandRegions:transition_to_output(region, event, recovery)
  region.output_start = copy_position(event)
  region.last_position = copy_position(event)
  region.state = "output"
  if recovery then
    recover(self, region, recovery)
  end
  return region
end

function CommandRegions:apply(event)
  if event.kind == "cwd" then return nil, "ignored" end
  local region = self.open
  if region and region.scope ~= event.scope then
    self:finish(region, region.last_position, "interrupted", nil, "scope-change")
    region = nil
  end

  if event.kind == "prompt" then
    if region then self:finish(region, event, "interrupted", nil, "next-prompt") end
    return self:append(event, "prompt"), "accepted"
  end

  if event.kind == "command_start" then
    if region == nil then return self:append(event, "command", "missing-prompt"), "recovered" end
    if region.state == "prompt" then return self:transition_to_command(region, event), "accepted" end
    if region.state == "command" then
      self.stats.repeated = self.stats.repeated + 1
      return region, "repeated"
    end
    self:finish(region, event, "interrupted", nil, "next-command")
    return self:append(event, "command", "missing-prompt"), "recovered"
  end

  if event.kind == "command_executed" then
    if region == nil then return self:append(event, "output", "missing-prompt-command"), "recovered" end
    if region.state == "prompt" then return self:transition_to_output(region, event, "missing-command-start"), "recovered" end
    if region.state == "command" then return self:transition_to_output(region, event), "accepted" end
    self.stats.repeated = self.stats.repeated + 1
    return region, "repeated"
  end

  if event.kind == "command_finished" then
    if region == nil then
      self.stats.orphaned = self.stats.orphaned + 1
      return nil, "orphaned"
    end
    if region.state == "prompt" then
      recover(self, region, "missing-command-start-output")
    elseif region.state == "command" then
      recover(self, region, "missing-command-executed")
    end
    return self:finish(region, event, "completed", event.exit_status), "accepted"
  end

  error("unknown shell marker kind: " .. tostring(event.kind))
end

function CommandRegions:view()
  local regions = {}
  for index, region in ipairs(self.regions) do regions[index] = copy_region(region) end
  return {
    active_id = self.open and self.open.id or nil,
    regions = regions,
    stats = copy_stats(self.stats),
  }
end

function CommandRegions:snapshot()
  return self:view()
end

return CommandRegions
