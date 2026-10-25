local Scrollback = {}
Scrollback.__index = Scrollback

function Scrollback.new(limit)
  assert(limit >= 0, "scrollback limit must not be negative")
  return setmetatable({ limit = limit, rows = {}, head = 1, count = 0 }, Scrollback)
end

function Scrollback:size()
  return self.count
end

function Scrollback:clear()
  self.rows = {}
  if self.borrowed then self.borrowed = {} end
  self.head = 1
  self.count = 0
end

function Scrollback:push(row)
  if self.limit == 0 then
    return row
  end
  if self.count < self.limit then
    local index = ((self.head + self.count - 1) % self.limit) + 1
    self.rows[index] = row
    if self.borrowed then self.borrowed[index] = nil end
    self.count = self.count + 1
    return nil
  end
  local evicted = self.rows[self.head]
  self.rows[self.head] = row
  if self.borrowed then self.borrowed[self.head] = nil end
  self.head = (self.head % self.limit) + 1
  return evicted
end

-- Metadata readers may inspect a row without materializing a staged copy or
-- resolving its cached colours. They must not mutate the returned row.
function Scrollback:peek(index)
  assert(index >= 1 and index <= self.count, "scrollback index out of bounds")
  local physical = ((self.head + index - 2) % self.limit) + 1
  return self.rows[physical], physical
end

function Scrollback:get(index)
  local row, physical = self:peek(index)
  if self.borrowed and self.borrowed[physical] then
    row = self.copy_row(row)
    self.rows[physical], self.borrowed[physical] = row, nil
  end
  if self.resolve_row then self.resolve_row(row) end
  return row
end

-- Synchronous transactions keep the original immutable until activation.
-- A full copy is necessary only for rows actually accessed during staging.
function Scrollback:fork(copy_row)
  local fork = Scrollback.new(self.limit)
  fork.head, fork.count = self.head, self.count
  fork.copy_row, fork.borrowed = copy_row, {}
  for physical, row in pairs(self.rows) do
    fork.rows[physical], fork.borrowed[physical] = row, true
  end
  return fork
end

function Scrollback:adopt()
  self.borrowed, self.copy_row = nil, nil
end

return Scrollback
