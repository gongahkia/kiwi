local Inspector = {}

local function codepoint_text(codepoints)
  local values = {}
  for index, codepoint in ipairs(codepoints or {}) do values[index] = string.format("U+%04X", codepoint) end
  return table.concat(values, " ")
end

function Inspector.describe(state, font_system, column, row)
  local cell = state:get(column, row)
  local anchor_column = cell.continuation and cell.anchor_column or column
  local anchor = state:get(anchor_column, row)
  local face, fallback
  if anchor.codepoints then face, fallback = font_system:face_for_cluster(anchor.codepoints) else fallback = "blank" end
  return {
    row = row,
    column = column,
    anchor_column = anchor_column,
    kind = cell.continuation and "continuation" or anchor.codepoints and "anchor" or "blank",
    codepoints = anchor.codepoints or {},
    width = anchor.width or 1,
    text = anchor.glyph,
    display_text = anchor.display_text or anchor.glyph,
    font_path = face and face.path or nil,
    face_id = face and face.id or nil,
    fallback = fallback,
  }
end

function Inspector.format(item)
  return string.format(
    "text-inspector row=%d column=%d kind=%s anchor=%d width=%d codepoints=[%s] font=%s face=%s fallback=%s text=%q",
    item.row,
    item.column,
    item.kind,
    item.anchor_column,
    item.width,
    codepoint_text(item.codepoints),
    item.font_path or "none",
    item.face_id and tostring(item.face_id) or "none",
    item.fallback,
    item.text
  )
end

return Inspector
