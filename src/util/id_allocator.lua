local id_allocator = { MAX_SAFE_INTEGER = 9007199254740991 }
local allocator = {}
allocator.__index = allocator

local function is_valid_id(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value == math.floor(value)
    and value >= 1
    and value <= id_allocator.MAX_SAFE_INTEGER
end

function id_allocator.new(start)
  start = start or 1
  if not is_valid_id(start) then
    return nil, { code = "invalid_start", message = "start must be a positive safe integer" }
  end
  return setmetatable({ next_id = start }, allocator)
end

function allocator:peek()
  return self.next_id
end

function allocator:next()
  if self.next_id > id_allocator.MAX_SAFE_INTEGER then
    return nil, { code = "id_exhausted", message = "stable ID space exhausted" }
  end
  local id = self.next_id
  self.next_id = self.next_id + 1
  return id
end

return id_allocator
