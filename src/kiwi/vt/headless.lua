local Headless = {}
Headless.api_version = 1

local function validate_view(view)
  assert(type(view) == "table" and type(view.row) == "function", "headless renderer needs a libkiwi-vt render view")
  assert(type(view.columns) == "number" and type(view.rows) == "number", "headless renderer needs view dimensions")
end

local function cell_text(cell)
  if cell.continuation then return "" end
  return cell.display_text or cell.glyph or " "
end

-- Projects a libkiwi-vt render view as logical terminal text. Wide-cell
-- continuations are omitted; each anchor cell contributes its display text.
-- This is intentionally a diagnostic consumer, not a replacement for shaping.
function Headless.render(view, options)
  validate_view(view)
  options = options or {}
  assert(options.trim_trailing == nil or type(options.trim_trailing) == "boolean", "headless trim_trailing must be a boolean")

  local lines = {}
  for row = 0, view.rows - 1 do
    local parts = {}
    for _, cell in ipairs(view:row(row)) do parts[#parts + 1] = cell_text(cell) end
    local line = table.concat(parts)
    if options.trim_trailing then line = line:gsub(" +$", "") end
    lines[#lines + 1] = line
  end
  return {
    active_screen = view.active_screen,
    columns = view.columns,
    cursor = {
      column = view.cursor.column,
      pending_wrap = view.cursor.pending_wrap == true,
      row = view.cursor.row,
      visible = view.cursor.visible == true,
    },
    damage = view.damage,
    generation = view.generation,
    lines = lines,
    rows = view.rows,
    selection = view.selection,
    text = table.concat(lines, "\n"),
  }
end

-- Opens and closes the public render-update transaction around a diagnostic
-- projection. Damage is only acknowledged when the caller asks for it.
function Headless.render_terminal(terminal, options)
  assert(type(terminal) == "table" and type(terminal.begin_render_update) == "function", "headless renderer needs a libkiwi-vt terminal")
  options = options or {}
  assert(options.consume_damage == nil or type(options.consume_damage) == "boolean", "headless consume_damage must be a boolean")

  local view = terminal:begin_render_update()
  local ok, result = xpcall(function()
    return Headless.render(view, options)
  end, debug.traceback)
  terminal:end_render_update(ok and options.consume_damage == true)
  if not ok then error(result, 0) end
  return result
end

return Headless
