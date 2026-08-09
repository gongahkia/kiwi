local Damage = {}
Damage.__index = Damage

local function assert_index(self, index)
  assert(index >= 0 and index < self.count, "cell index out of bounds")
end

function Damage.new(count)
  assert(count >= 0, "damage count must not be negative")
  return setmetatable({ count = count, ranges_list = {}, dirty_count = 0, full = false }, Damage)
end

function Damage:mark(index)
  assert_index(self, index)
  return self:mark_range(index, 1) > 0
end

function Damage:mark_range(first, length)
  assert(length >= 0, "damage range length must not be negative")
  assert(first >= 0 and first + length <= self.count, "damage range out of bounds")
  if length == 0 or self.full then
    return 0
  end

  local last = first + length - 1
  local ranges = self.ranges_list
  if #ranges == 0 then
    ranges[1] = { first = first, count = length }
    self.dirty_count = length
    return length
  end

  -- The terminal's normal write path extends one contiguous dirty range.
  -- Keep that case allocation-free so it remains trace-friendly under output.
  do
    local range = ranges[#ranges]
    local range_last = range.first + range.count - 1
    if first >= range.first and last + 1 >= range.first and first <= range_last + 1 then
      local previous_count = range.count
      if last > range_last then
        range.count = last - range.first + 1
      end
      self.dirty_count = self.dirty_count + range.count - previous_count
      return range.count - previous_count
    end
  end

  local merged = {}
  local inserted = false
  local previous_count = self.dirty_count

  for _, range in ipairs(ranges) do
    local range_last = range.first + range.count - 1
    if range_last + 1 < first then
      merged[#merged + 1] = range
    elseif last + 1 < range.first then
      if not inserted then
        merged[#merged + 1] = { first = first, count = last - first + 1 }
        inserted = true
      end
      merged[#merged + 1] = range
    else
      first = math.min(first, range.first)
      last = math.max(last, range_last)
      self.dirty_count = self.dirty_count - range.count
    end
  end

  if not inserted then
    merged[#merged + 1] = { first = first, count = last - first + 1 }
  end
  self.dirty_count = self.dirty_count + last - first + 1
  self.ranges_list = merged
  return self.dirty_count - previous_count
end

function Damage:mark_all()
  self.full = true
  self.ranges_list = {}
  self.dirty_count = self.count
end

function Damage:clear()
  self.full = false
  self.ranges_list = {}
  self.dirty_count = 0
end

function Damage:ranges()
  if self.dirty_count == 0 then
    return {}
  end
  if self.full then
    return { { first = 0, count = self.count } }
  end
  return self.ranges_list
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
