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
    self.count = self.count + 1
    return nil
  end
  local evicted = self.rows[self.head]
  self.rows[self.head] = row
  self.head = (self.head % self.limit) + 1
  return evicted
end

function Scrollback:get(index)
  assert(index >= 1 and index <= self.count, "scrollback index out of bounds")
  local physical = ((self.head + index - 2) % self.limit) + 1
  return self.rows[physical]
end

return Scrollback
