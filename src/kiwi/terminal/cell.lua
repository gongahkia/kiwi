local Cell = {}

-- History cells store values in array slots rather than one hash node per
-- property. The frequently mutated screen keeps ordinary tables. Named access
-- remains available to history consumers, including palette resolution. Use
-- Cell.clone for copies: pairs/rawget expose storage, not the named schema.
local slots = {
  glyph = 1, fg = 2, bg = 3, fg_slot = 4, bg_slot = 5, flags = 6,
  codepoints = 7, width = 8, underline_style = 9, underline_color = 10,
  underline_slot = 11, continuation = 12, anchor_column = 13,
  display_text = 14, hyperlink_id = 15,
}
local cell_metatable = {
  __index = function(cell, key) return rawget(cell, slots[key] or key) end,
  __newindex = function(cell, key, value) rawset(cell, slots[key] or key, value) end,
}

function Cell.is_compact(value)
  return getmetatable(value) == cell_metatable
end

-- Optional slots are allocated only when used; do not grow plain cells just
-- to write nil. Codepoint arrays are immutable and shared by copies.
local function copy_optional(destination, source)
  if destination.underline_style ~= nil or source.underline_style ~= nil then destination.underline_style = source.underline_style end
  if destination.underline_color ~= nil or source.underline_color ~= nil then destination.underline_color = source.underline_color end
  if destination.underline_slot ~= nil or source.underline_slot ~= nil then destination.underline_slot = source.underline_slot end
  if destination.continuation ~= nil or source.continuation ~= nil then destination.continuation = source.continuation end
  if destination.anchor_column ~= nil or source.anchor_column ~= nil then destination.anchor_column = source.anchor_column end
  if destination.display_text ~= nil or source.display_text ~= nil then destination.display_text = source.display_text end
  if destination.hyperlink_id ~= nil or source.hyperlink_id ~= nil then destination.hyperlink_id = source.hyperlink_id end
end

function Cell.copy_into(destination, source)
  destination.glyph = source.glyph
  destination.fg = source.fg
  destination.bg = source.bg
  destination.fg_slot = source.fg_slot
  destination.bg_slot = source.bg_slot
  destination.flags = source.flags
  destination.codepoints = source.codepoints
  destination.width = source.width
  copy_optional(destination, source)
end

function Cell.pack(source)
  if source.underline_style ~= nil or source.underline_color ~= nil or source.underline_slot ~= nil
      or source.continuation ~= nil or source.anchor_column ~= nil
      or source.display_text ~= nil or source.hyperlink_id ~= nil then
    -- Allocate the complete optional array together. Inserting sparse high
    -- indices individually would reserve hash nodes instead of array storage.
    return setmetatable({ source.glyph, source.fg, source.bg, source.fg_slot,
      source.bg_slot, source.flags, source.codepoints, source.width,
      source.underline_style, source.underline_color, source.underline_slot,
      source.continuation, source.anchor_column, source.display_text, source.hyperlink_id }, cell_metatable)
  end
  return setmetatable({ source.glyph, source.fg, source.bg, source.fg_slot,
    source.bg_slot, source.flags, source.codepoints, source.width }, cell_metatable)
end

function Cell.expand(source)
  local cell = {
    glyph = source.glyph, fg = source.fg, bg = source.bg,
    fg_slot = source.fg_slot, bg_slot = source.bg_slot, flags = source.flags,
    codepoints = source.codepoints, width = source.width,
  }
  copy_optional(cell, source)
  return cell
end

function Cell.clone(source)
  if Cell.is_compact(source) then return Cell.pack(source) end
  return Cell.expand(source)
end

-- When scrolling, detach the live cell array so the screen can reset and reuse
-- it after history owns independent packed copies. Reflow only needs packing.
function Cell.pack_row(row, detach)
  local previous = row.cells
  if detach then row.cells = {} end
  for column, cell in pairs(previous) do
    if detach or not Cell.is_compact(cell) then row.cells[column] = Cell.pack(cell) end
  end
  if detach then return previous end
end

return Cell
