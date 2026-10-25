-- Synchronous configuration staging. Preserve the live State object's identity
-- because the parser and host hold references to it. Strings/image byte buffers
-- and cluster arrays are immutable here. Screen cells and image residency are
-- private copies; history rows are copied on access through Scrollback:get.
-- Neither the original nor rows returned by Scrollback:peek may be mutated
-- during staging. Activation transfers exclusive ownership of unread history.
local Transaction = {}
Transaction.__index = Transaction

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  if seen[value] then return seen[value] end
  if rawget(value, "glyph") ~= nil and rawget(value, "fg") ~= nil and rawget(value, "flags") ~= nil then
    if value.glyph == " " and value.flags == 0 and value.width == 1 and value.codepoints == nil
      and value.underline_color == nil and value.underline_style == nil and value.underline_slot == nil
      and value.hyperlink_id == nil and value.display_text == nil and not value.continuation then
      local blank = { glyph = " ", fg = value.fg, bg = value.bg, flags = 0, width = 1,
        fg_slot = value.fg_slot, bg_slot = value.bg_slot }
      seen[value] = blank
      return blank
    end
    -- Fixed terminal cell record, matching Screen.copy_cell. Preallocate its
    -- fields instead of growing a hash table and recursively copying scalars.
    local cell = {
      glyph = value.glyph, fg = value.fg, bg = value.bg,
      fg_slot = value.fg_slot, bg_slot = value.bg_slot, flags = value.flags,
      codepoints = value.codepoints, width = value.width, continuation = value.continuation,
      anchor_column = value.anchor_column, display_text = value.display_text,
      hyperlink_id = value.hyperlink_id, underline_style = value.underline_style,
      underline_color = value.underline_color, underline_slot = value.underline_slot,
    }
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
