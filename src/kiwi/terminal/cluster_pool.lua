-- Terminal codepoint arrays are immutable: extending a grapheme replaces its
-- array. Share repeated Unicode clusters just as state.lua shares ASCII arrays.
-- The FIFO bounds both entries and each retained key/array; eviction only drops
-- the pool's reference and never changes a cell's retained cluster.
local Pool = { maximum_entries = 4096, maximum_bytes = 256, maximum_codepoints = 64 }
Pool.__index = Pool

function Pool.new()
  return setmetatable({ entries = {}, order = {}, next_slot = 1, count = 0 }, Pool)
end

-- text is the exact semantic UTF-8 cluster (not its dotted-circle display
-- substitute). prefix is immutable or nil for a new single-codepoint cluster.
function Pool:intern(text, prefix, codepoint)
  local count = prefix and #prefix or 0
  local cacheable = #text <= Pool.maximum_bytes and count < Pool.maximum_codepoints
  if cacheable then
    local existing = self.entries[text]
    if existing then return existing end
  end
  local codepoints = {}
  for index = 1, count do codepoints[index] = prefix[index] end
  codepoints[count + 1] = codepoint
  if cacheable then
    local evicted = self.order[self.next_slot]
    if evicted then self.entries[evicted] = nil else self.count = self.count + 1 end
    self.entries[text], self.order[self.next_slot] = codepoints, text
    self.next_slot = self.next_slot % Pool.maximum_entries + 1
  end
  return codepoints
end

return Pool
