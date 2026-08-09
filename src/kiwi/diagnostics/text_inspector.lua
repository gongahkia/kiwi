local Inspector = {}

local function codepoint_text(codepoints)
  local values = {}
  for index, codepoint in ipairs(codepoints or {}) do values[index] = string.format("U+%04X", codepoint) end
  return table.concat(values, " ")
end

function Inspector.describe(state, font_system, column, row, layout)
  local cell = state:get(column, row)
  local anchor_column = cell.continuation and cell.anchor_column or column
  local anchor = state:get(anchor_column, row)
  local face, fallback
  if anchor.codepoints then face, fallback = font_system:face_for_cluster(anchor.codepoints) else fallback = "blank" end
  local glyphs = {}
  local cached_row = layout and layout.rows[row]
  for _, glyph in ipairs(cached_row and cached_row.glyphs or {}) do
    if glyph.cluster_column == anchor_column then
      glyphs[#glyphs + 1] = {
        glyph_id = glyph.glyph_id,
        face_id = glyph.face_id,
        shape_cluster = glyph.shape_cluster,
        x_advance = glyph.x_advance,
        y_advance = glyph.y_advance,
        x_offset = glyph.x_offset,
        y_offset = glyph.y_offset,
        atlas_page = glyph.atlas_page,
        missing_reason = glyph.missing_reason,
      }
    end
  end
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
    glyphs = glyphs,
  }
end

local function glyph_text(glyphs)
  local values = {}
  for index, glyph in ipairs(glyphs) do
    values[index] = string.format(
      "id=%d face=%d hb=%d advance=%d,%d offset=%d,%d atlas=%d%s",
      glyph.glyph_id,
      glyph.face_id,
      glyph.shape_cluster,
      glyph.x_advance,
      glyph.y_advance,
      glyph.x_offset,
      glyph.y_offset,
      glyph.atlas_page,
      glyph.missing_reason and " reason=" .. glyph.missing_reason or ""
    )
  end
  return table.concat(values, " | ")
end

function Inspector.format(item)
  return string.format(
    "text-inspector row=%d column=%d kind=%s anchor=%d width=%d codepoints=[%s] font=%s face=%s fallback=%s text=%q glyphs=[%s]",
    item.row,
    item.column,
    item.kind,
    item.anchor_column,
    item.width,
    codepoint_text(item.codepoints),
    item.font_path or "none",
    item.face_id and tostring(item.face_id) or "none",
    item.fallback,
    item.text,
    glyph_text(item.glyphs)
  )
end

return Inspector
