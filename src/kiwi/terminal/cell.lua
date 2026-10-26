local Cell = {}

-- Plain cells fit in eight hash slots. Assigning an absent optional key even
-- to nil can grow a LuaJIT table, so clear only fields that actually exist.
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

function Cell.clone(source)
  local cell = {
    glyph = source.glyph, fg = source.fg, bg = source.bg,
    fg_slot = source.fg_slot, bg_slot = source.bg_slot, flags = source.flags,
    codepoints = source.codepoints, width = source.width,
  }
  copy_optional(cell, source)
  return cell
end

return Cell
