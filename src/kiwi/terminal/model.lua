local Damage = require("kiwi.terminal.damage")

local Terminal = {}
Terminal.__index = Terminal

Terminal.flags = {
  bold = 0x01,
  semantic = 0x02,
  recent = 0x04,
}

local function copy_cell(cell)
  return {
    glyph = cell.glyph,
    fg = cell.fg,
    bg = cell.bg,
    flags = cell.flags,
  }
end

local function same_cell(left, right)
  return left.glyph == right.glyph
    and left.fg == right.fg
    and left.bg == right.bg
    and left.flags == right.flags
end

function Terminal.new(columns, rows, default_cell)
  assert(columns > 0 and rows > 0, "terminal dimensions must be positive")
  default_cell = default_cell or { glyph = " ", fg = 0xffd8dee9, bg = 0xff20242b, flags = 0 }

  local self = setmetatable({
    columns = columns,
    rows = rows,
    cells = {},
    default_cell = copy_cell(default_cell),
    cursor = { column = 0, row = 0 },
    damage = Damage.new(columns * rows),
  }, Terminal)

  for index = 0, columns * rows - 1 do
    self.cells[index] = copy_cell(self.default_cell)
  end
  self.damage:mark_all()
  return self
end

function Terminal:index(column, row)
  assert(column >= 0 and column < self.columns, "column out of bounds")
  assert(row >= 0 and row < self.rows, "row out of bounds")
  return row * self.columns + column
end

function Terminal:position(index)
  assert(index >= 0 and index < self.columns * self.rows, "cell index out of bounds")
  return index % self.columns, math.floor(index / self.columns)
end

function Terminal:get(column, row)
  return self.cells[self:index(column, row)]
end

function Terminal:set(column, row, cell)
  assert(type(cell.glyph) == "string" and #cell.glyph > 0, "cell glyph must be a non-empty string")
  local index = self:index(column, row)
  local old = self.cells[index]
  if same_cell(old, cell) then
    return false
  end
  self.cells[index] = copy_cell(cell)
  self.damage:mark(index)
  return true
end

function Terminal:write(column, row, text, style)
  style = style or self.default_cell
  local written = 0
  for offset = 1, #text do
    local target = column + offset - 1
    if target >= self.columns then
      break
    end
    if self:set(target, row, {
      glyph = text:sub(offset, offset),
      fg = style.fg,
      bg = style.bg,
      flags = style.flags or 0,
    }) then
      written = written + 1
    end
  end
  return written
end

function Terminal:set_cursor(column, row)
  local old_index = self:index(self.cursor.column, self.cursor.row)
  local new_index = self:index(column, row)
  self.cursor.column = column
  self.cursor.row = row
  self.damage:mark(old_index)
  self.damage:mark(new_index)
end

function Terminal:mark_all_dirty()
  self.damage:mark_all()
end

function Terminal:clear_damage()
  self.damage:clear()
end

function Terminal:resize(columns, rows)
  assert(columns > 0 and rows > 0, "terminal dimensions must be positive")
  self.columns = columns
  self.rows = rows
  self.cells = {}
  for index = 0, columns * rows - 1 do
    self.cells[index] = copy_cell(self.default_cell)
  end
  self.cursor = { column = 0, row = 0 }
  self.damage = Damage.new(columns * rows)
  self.damage:mark_all()
end

return Terminal
