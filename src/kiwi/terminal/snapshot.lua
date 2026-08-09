local Json = require("kiwi.bench.json")

local Snapshot = {}

function Snapshot.value(state)
  local rows = {}
  for row = 0, state.rows - 1 do
    local cells = {}
    local text = {}
    for column = 0, state.columns - 1 do
      local cell = state:cell_at_index(state:index(column, row))
      text[#text + 1] = cell.glyph
      cells[#cells + 1] = { bg = cell.bg, fg = cell.fg, flags = cell.flags, glyph = cell.glyph }
    end
    rows[#rows + 1] = { cells = cells, text = table.concat(text) }
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
      cursor_visible = state.modes.cursor_visible,
      insert = state.modes.insert,
      origin = state.modes.origin,
    },
    rows = rows,
    scrollback_lines = state.scrollback:size(),
    title = state.title,
  }
end

function Snapshot.encode(state)
  return Json.encode(Snapshot.value(state))
end

return Snapshot
