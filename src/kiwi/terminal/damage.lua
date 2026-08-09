local Damage = {}
Damage.__index = Damage

local function assert_index(self, index)
  assert(index >= 0 and index < self.count, "cell index out of bounds")
end

function Damage.new(count)
  assert(count >= 0, "damage count must not be negative")
  return setmetatable({ count = count, dirty = {}, dirty_count = 0, full = false }, Damage)
end

function Damage:mark(index)
  assert_index(self, index)
  if self.full or self.dirty[index] then
    return false
  end
  self.dirty[index] = true
  self.dirty_count = self.dirty_count + 1
  return true
end

function Damage:mark_range(first, length)
  assert(length >= 0, "damage range length must not be negative")
  assert(first >= 0 and first + length <= self.count, "damage range out of bounds")
  if length == 0 or self.full then
    return 0
  end

  local marked = 0
  for index = first, first + length - 1 do
    if self:mark(index) then
      marked = marked + 1
    end
  end
  return marked
end

function Damage:mark_all()
  self.full = true
  self.dirty = {}
  self.dirty_count = self.count
end

function Damage:clear()
  self.full = false
  self.dirty = {}
  self.dirty_count = 0
end

function Damage:ranges()
  if self.dirty_count == 0 then
    return {}
  end
  if self.full then
    return { { first = 0, count = self.count } }
  end

  local ranges = {}
  local index = 0
  while index < self.count do
    if self.dirty[index] then
      local first = index
      repeat
        index = index + 1
      until index == self.count or not self.dirty[index]
      ranges[#ranges + 1] = { first = first, count = index - first }
    else
      index = index + 1
    end
  end
  return ranges
end

function Damage:summary()
  local ranges = self:ranges()
  return {
    cells = self.dirty_count,
    ranges = #ranges,
    full = self.full,
  }
end

return Damage
