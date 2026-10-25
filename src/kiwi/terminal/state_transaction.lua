-- Synchronous configuration staging. Preserve the live State object's identity
-- because the parser and host hold references to it. Strings/image byte buffers
-- are immutable here; tables (including image residency) are private copies.
local Transaction = {}
Transaction.__index = Transaction

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  if seen[value] then return seen[value] end
  local result = setmetatable({}, getmetatable(value))
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  return result
end

local function bind(snapshot, owner)
  snapshot.cells = setmetatable({}, { __index = function(_, index) return owner:cell_at_index(index) end })
  for _, screen in ipairs({ snapshot.primary, snapshot.alternate }) do
    screen.blank_cell = function() return owner:blank_cell() end
    screen.line_id_factory = function()
      owner.next_line_id = owner.next_line_id + 1
      return owner.next_line_id
    end
  end
  snapshot.kitty_graphics.on_image_release = function(id)
    owner:detach_kitty_placement_records(owner.kitty_placements:remove_image(id))
  end
end

function Transaction.new(state)
  local self = setmetatable({ original = state, state = copy(state, {}), effects = {} }, Transaction)
  bind(self.state, self.state)
  self.state.effect_sink = function(kind, value)
    self.effects[#self.effects + 1] = { kind = kind, value = value }
  end
  return self
end

function Transaction:seal()
  assert(not self.sealed and not self.committed, "state transaction already sealed")
  bind(self.state, self.original)
  self.state.effect_sink = self.original.effect_sink
  self.sealed = true
end

function Transaction:commit()
  assert(self.sealed and not self.committed, "state transaction must be sealed exactly once")
  for key in pairs(self.original) do self.original[key] = nil end
  for key, value in pairs(self.state) do self.original[key] = value end
  self.committed = true
end

function Transaction:publish_effects()
  assert(self.committed and not self.published, "state transaction effects must follow commit exactly once")
  self.published = true
  for _, effect in ipairs(self.effects) do self.original:emit_effect(effect.kind, effect.value) end
end

return Transaction
