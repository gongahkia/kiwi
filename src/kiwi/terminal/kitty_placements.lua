local KittyPlacements = {}
KittyPlacements.__index = KittyPlacements

KittyPlacements.default_limit = 256
KittyPlacements.default_max_rows = 256

local function positive_integer(value, maximum)
  if value == nil or not value:match("^%d+$") then return nil end
  local number = tonumber(value)
  if number == nil or number == 0 or number > maximum then return nil end
  return number
end

local function signed_integer(value)
  if value == nil or not value:match("^-?%d+$") then return nil end
  local number = tonumber(value)
  if number == nil or number < -2147483648 or number > 2147483647 then return nil end
  return number
end

local function key(image_id, placement_id)
  return tostring(image_id) .. ":" .. tostring(placement_id)
end

local function copy_stats(stats)
  return {
    clipped = stats.clipped,
    created = stats.created,
    rejected = stats.rejected,
    released = stats.released,
    replaced = stats.replaced,
  }
end

local function copy_record(record)
  local rows = {}
  for index, row in ipairs(record.rows) do
    rows[index] = { line_id = row.line_id, source_row = row.source_row }
  end
  return {
    column = record.column,
    columns = record.columns,
    id = record.id,
    image_id = record.image_id,
    placement_id = record.placement_id,
    rows = rows,
    scope = record.scope,
    z = record.z,
  }
end

function KittyPlacements.new(options)
  options = options or {}
  local limit = options.limit or KittyPlacements.default_limit
  local max_rows = options.max_rows or KittyPlacements.default_max_rows
  assert(type(limit) == "number" and limit >= 1 and limit % 1 == 0, "kitty placement limit must be a positive integer")
  assert(type(max_rows) == "number" and max_rows >= 1 and max_rows % 1 == 0, "kitty placement row limit must be a positive integer")
  return setmetatable({
    by_key = {},
    limit = limit,
    max_rows = max_rows,
    next_id = 0,
    placements = {},
    stats = { clipped = 0, created = 0, rejected = 0, released = 0, replaced = 0 },
  }, KittyPlacements)
end

function KittyPlacements:reject(reason)
  self.stats.rejected = self.stats.rejected + 1
  return nil, reason
end

function KittyPlacements:remove(record, reason)
  self.by_key[key(record.image_id, record.placement_id)] = nil
  for index, candidate in ipairs(self.placements) do
    if candidate == record then
      table.remove(self.placements, index)
      break
    end
  end
  self.stats.released = self.stats.released + 1
  return record, reason
end

function KittyPlacements:parse(controls)
  if controls.a == "p" then
    for field in pairs(controls) do
      if field ~= "a" and field ~= "C" and field ~= "c" and field ~= "i" and field ~= "p" and field ~= "r" and field ~= "z" then
        return self:reject("unsupported-placement-controls")
      end
    end
    local image_id = positive_integer(controls.i, 0xffffffff)
    local placement_id = positive_integer(controls.p, 0xffffffff)
    local columns = positive_integer(controls.c, 0xffffffff)
    local rows = positive_integer(controls.r, self.max_rows)
    local z = controls.z == nil and 0 or signed_integer(controls.z)
    if image_id == nil or placement_id == nil or columns == nil or rows == nil then return self:reject("invalid-placement") end
    if controls.C ~= "1" then return self:reject("unsupported-cursor-policy") end
    if z == nil then return self:reject("invalid-z-index") end
    return { columns = columns, image_id = image_id, kind = "place", placement_id = placement_id, rows = rows, z = z }
  end

  if controls.a == "d" then
    for field in pairs(controls) do
      if field ~= "a" and field ~= "d" and field ~= "i" and field ~= "p" then
        return self:reject("unsupported-delete-controls")
      end
    end
    local mode = controls.d or "a"
    if mode ~= "a" and mode ~= "i" and mode ~= "I" then return self:reject("unsupported-delete") end
    local image_id = controls.i and positive_integer(controls.i, 0xffffffff) or nil
    local placement_id = controls.p and positive_integer(controls.p, 0xffffffff) or nil
    if controls.i and image_id == nil or controls.p and placement_id == nil then return self:reject("invalid-delete") end
    if (mode == "i" or mode == "I") and image_id == nil then return self:reject("missing-image-id") end
    if mode == "a" and (image_id ~= nil or placement_id ~= nil) then return self:reject("invalid-delete") end
    return { image_id = image_id, kind = "delete", mode = mode, placement_id = placement_id }
  end

  return self:reject("unsupported-action")
end

function KittyPlacements:place(command, context)
  if not context.has_image(command.image_id) then return self:reject("unknown-image") end
  if command.columns > context.columns - context.column or command.rows > context.rows - context.row then
    return self:reject("placement-outside-viewport")
  end

  local rows = {}
  for offset = 0, command.rows - 1 do
    local row = context.screen.rows[context.row + offset]
    rows[#rows + 1] = { line_id = row.line_id, source_row = offset }
  end

  local previous = self.by_key[key(command.image_id, command.placement_id)]
  if previous == nil and #self.placements >= self.limit then return self:reject("placement-limit") end
  if previous then
    self:remove(previous, "replaced")
    self.stats.replaced = self.stats.replaced + 1
  end
  self.next_id = self.next_id + 1
  local placement = {
    column = context.column,
    columns = command.columns,
    id = self.next_id,
    image_id = command.image_id,
    placement_id = command.placement_id,
    rows = rows,
    scope = context.scope,
    z = command.z,
  }
  self.placements[#self.placements + 1] = placement
  self.by_key[key(placement.image_id, placement.placement_id)] = placement
  self.stats.created = self.stats.created + 1
  return placement, previous
end

function KittyPlacements:matching(command, scope)
  local matches = {}
  for _, placement in ipairs(self.placements) do
    local matches_scope = command.mode == "a" and placement.scope == scope
    local matches_image = (command.mode == "i" or command.mode == "I")
      and placement.image_id == command.image_id
      and (command.placement_id == nil or placement.placement_id == command.placement_id)
    if matches_scope or matches_image then
      matches[#matches + 1] = placement
    end
  end
  return matches
end

function KittyPlacements:delete(command, scope)
  local removed = {}
  for _, placement in ipairs(self:matching(command, scope)) do
    removed[#removed + 1] = self:remove(placement, "deleted")
  end
  return removed
end

function KittyPlacements:remove_image(image_id)
  local removed = {}
  for index = #self.placements, 1, -1 do
    local placement = self.placements[index]
    if placement.image_id == image_id then removed[#removed + 1] = self:remove(placement, "image-released") end
  end
  return removed
end

function KittyPlacements:release_line(scope, line_id)
  for index = #self.placements, 1, -1 do
    local placement = self.placements[index]
    if placement.scope == scope then
      for row_index = #placement.rows, 1, -1 do
        if placement.rows[row_index].line_id == line_id then
          table.remove(placement.rows, row_index)
          self.stats.clipped = self.stats.clipped + 1
          if #placement.rows == 0 then self:remove(placement, "row-released") end
          break
        end
      end
    end
  end
end

function KittyPlacements:clear_scope(scope)
  local removed = {}
  for index = #self.placements, 1, -1 do
    local placement = self.placements[index]
    if placement.scope == scope then removed[#removed + 1] = self:remove(placement, "cleared") end
  end
  return removed
end

function KittyPlacements:clear()
  local removed = {}
  for index = #self.placements, 1, -1 do removed[#removed + 1] = self:remove(self.placements[index], "reset") end
  return removed
end

function KittyPlacements:resize_scope(scope, columns)
  local removed = {}
  for index = #self.placements, 1, -1 do
    local placement = self.placements[index]
    if placement.scope == scope then
      if placement.column >= columns then
        removed[#removed + 1] = self:remove(placement, "resize-clipped")
      elseif placement.column + placement.columns > columns then
        placement.columns = columns - placement.column
        self.stats.clipped = self.stats.clipped + 1
      end
    end
  end
  return removed
end

function KittyPlacements:has_image(image_id)
  for _, placement in ipairs(self.placements) do
    if placement.image_id == image_id then return true end
  end
  return false
end

function KittyPlacements:view(scope, visible_rows)
  local by_line_id = {}
  for row, line_id in ipairs(visible_rows or {}) do by_line_id[line_id] = row - 1 end
  local placements = {}
  for _, placement in ipairs(self.placements) do
    if scope == nil or placement.scope == scope then
      local rows = {}
      for _, reference in ipairs(placement.rows) do
        local row = by_line_id[reference.line_id]
        if row ~= nil then rows[#rows + 1] = { row = row, source_row = reference.source_row } end
      end
      placements[#placements + 1] = {
        column = placement.column,
        columns = placement.columns,
        id = placement.id,
        image_id = placement.image_id,
        placement_id = placement.placement_id,
        rows = rows,
        scope = placement.scope,
        visible = #rows > 0,
        z = placement.z,
      }
    end
  end
  table.sort(placements, function(left, right)
    if left.z ~= right.z then return left.z < right.z end
    if left.image_id ~= right.image_id then return left.image_id < right.image_id end
    return left.placement_id < right.placement_id
  end)
  return { placements = placements, stats = copy_stats(self.stats) }
end

function KittyPlacements:snapshot()
  local placements = {}
  for index, placement in ipairs(self.placements) do placements[index] = copy_record(placement) end
  table.sort(placements, function(left, right)
    if left.image_id ~= right.image_id then return left.image_id < right.image_id end
    return left.placement_id < right.placement_id
  end)
  return { placements = placements, stats = copy_stats(self.stats) }
end

return KittyPlacements
