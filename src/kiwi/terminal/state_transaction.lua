-- Synchronous configuration staging. Preserve the live State object's identity
-- because the parser and host hold references to it. Strings/image byte buffers
-- and cluster arrays are immutable here. Screen cells and image residency are
-- private copies; history rows are copied on access through Scrollback:get.
-- Neither the original nor rows returned by Scrollback:peek may be mutated
-- during staging. Activation transfers exclusive ownership of unread history.
local Cell = require("kiwi.terminal.cell")
local Transaction = {}
Transaction.__index = Transaction

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  if seen[value] then return seen[value] end
  if rawget(value, "glyph") ~= nil and rawget(value, "fg") ~= nil and rawget(value, "flags") ~= nil then
    -- Cluster arrays are immutable; optional fields stay absent on plain cells.
    local cell = Cell.clone(value)
    seen[value] = cell
    return cell
  end
  local result = setmetatable({}, getmetatable(value))
  seen[value] = result
  for key, item in pairs(value) do
    -- Cluster arrays are immutable: extending a grapheme creates a new array.
    -- Keep the shared ASCII pool and Unicode arrays shared across candidates.
    if key == "codepoints" then result[key] = item
    else result[copy(key, seen)] = copy(item, seen) end
  end
  return result
end

local function bind(snapshot, owner)
  snapshot:bind_scrollback(owner)
  snapshot:bind_cells(owner)
  for _, screen in ipairs({ snapshot.primary, snapshot.alternate }) do
    screen.owner = owner
    screen.blank_cell = owner.blank_cell
    screen.line_id_factory = owner.allocate_line_id
  end
  snapshot.kitty_graphics.on_image_release = function(id)
    owner:detach_kitty_placement_records(owner.kitty_placements:remove_image(id))
  end
end

function Transaction.new(state, dimensions)
  local seen = {}
  local resized = dimensions and (dimensions.columns ~= state.columns or dimensions.rows ~= state.rows)
  if not resized then
    seen[state.scrollback] = state.scrollback:fork(function(row) return copy(row, {}) end)
  end
  local direct_reflow = resized and dimensions.columns ~= state.columns and state.reflow_on_resize
    and not state:can_keep_primary_rows_on_resize(dimensions.columns, dimensions.rows)
  if direct_reflow then
    -- Reflow reads source cells and creates independent destination cells.
    -- Clone row metadata but avoid copying the entire document twice. Do not
    -- expose this snapshot until resize has detached every source cell array.
    for _, screen in ipairs({ state.primary, state.alternate }) do
      for _, row in pairs(screen.rows) do seen[row.cells] = row.cells end
    end
    for _, row in pairs(state.scrollback.rows) do
      -- Resolving a pending palette must not write borrowed source cells.
      if row.palette_generation == state.palette_generation then seen[row.cells] = row.cells end
    end
  end
  local self = setmetatable({ original = state, state = copy(state, seen), effects = {} }, Transaction)
  bind(self.state, self.state)
  self.state.effect_sink = function(kind, value)
    self.effects[#self.effects + 1] = { kind = kind, value = value }
  end
  if resized then
    self.state:resize(dimensions.columns, dimensions.rows)
    self.state.grapheme_context_storage = {}
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
  self.state.scrollback:adopt()
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
