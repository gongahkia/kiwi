local Json = require("kiwi.bench.json")

local Snapshot = {}
Snapshot.version = 1

function Snapshot.value(state)
  local rows = {}
  for row = 0, state.rows - 1 do
    local source = state:visible_row(row)
    local cells = {}
    local text = {}
    for column = 0, state.columns - 1 do
      local cell = state:cell_at_index(state:index(column, row))
      text[#text + 1] = cell.glyph
      local snapshot_cell = { bg = cell.bg, fg = cell.fg, flags = cell.flags, glyph = cell.glyph }
      if cell.hyperlink_id then snapshot_cell.hyperlink = { id = cell.hyperlink_id } end
      if cell.continuation then
        snapshot_cell.cluster = { anchor_column = cell.anchor_column, kind = "continuation" }
      elseif cell.codepoints and (#cell.codepoints > 1 or cell.width == 2 or cell.display_text ~= cell.glyph) then
        local codepoints = {}
        for index, codepoint in ipairs(cell.codepoints) do codepoints[index] = codepoint end
        snapshot_cell.cluster = { codepoints = codepoints, width = cell.width }
      end
      cells[#cells + 1] = snapshot_cell
    end
    local snapshot_row = { cells = cells, text = table.concat(text) }
    if source and source.command_region_ids then
      local ids = {}
      for index, id in ipairs(source.command_region_ids) do ids[index] = id end
      snapshot_row.command_region_ids = ids
    end
    if source and source.command_regions_truncated then snapshot_row.command_regions_truncated = true end
    rows[#rows + 1] = snapshot_row
  end
  return {
    active_screen = state.active_screen == state.primary and "primary" or "alternate",
    columns = state.columns,
    cursor = { column = state.cursor.column, row = state.cursor.row, visible = state.cursor.visible },
    history_offset = state.history_offset,
    margins = { bottom = state.active_screen.bottom_margin, top = state.active_screen.top_margin },
    modes = {
      application_cursor = state.modes.application_cursor,
      autowrap = state.modes.autowrap,
      bracketed_paste = state.modes.bracketed_paste,
      cursor_style = state.modes.cursor_style,
      cursor_visible = state.modes.cursor_visible,
      focus_reporting = state.modes.focus_reporting,
      insert = state.modes.insert,
      keyboard_flags = state.modes.keyboard_flags,
      mouse_protocol = state.modes.mouse_protocol,
      mouse_sgr = state.modes.mouse_sgr,
      mouse_tracking = state.modes.mouse_tracking,
      origin = state.modes.origin,
      synchronized_output = state.modes.synchronized_output,
    },
    rows = rows,
    command_regions = state.command_regions and state.command_regions:snapshot() or nil,
    kitty_graphics = state.kitty_graphics and state.kitty_graphics:snapshot() or nil,
    kitty_placements = state.kitty_placements and state.kitty_placements:snapshot() or nil,
    shell = state.shell and state.shell:snapshot() or nil,
    scrollback_lines = state.scrollback:size(),
    title = state.title,
    v = Snapshot.version,
  }
end

function Snapshot.encode(state)
  return Json.encode(Snapshot.value(state))
end

return Snapshot
