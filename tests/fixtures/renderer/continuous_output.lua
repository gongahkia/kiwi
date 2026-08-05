local Fixture = {}
local fixture_mt = {}
fixture_mt.__index = fixture_mt

local function positive_integer(value, name)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 then
    error(name .. " must be a positive integer")
  end
  return value
end

local function cell()
  return {
    attributes = 0,
    background = "default",
    continuation = false,
    foreground = "default",
    text = " ",
    width = 1,
  }
end

function Fixture.new(options)
  options = options or {}
  local columns = positive_integer(options.columns or 120, "columns")
  local rows = positive_integer(options.rows or 40, "rows")
  local visible_rows = {}
  for row = 1, rows do
    local cells = {}
    for column = 1, columns do
      cells[column] = cell()
    end
    visible_rows[row] = { cells = cells }
  end
  return setmetatable({
    damage = { { first_column = 1, last_column = columns, row = 1 } },
    frame = 0,
    snapshot = {
      columns = columns,
      rows = rows,
      screen = { rows = visible_rows },
    },
  }, fixture_mt)
end

function fixture_mt:advance()
  self.frame = self.frame + 1
  local row = (self.frame - 1) % self.snapshot.rows + 1
  local cells = self.snapshot.screen.rows[row].cells
  for column = 1, self.snapshot.columns do
    local value = (self.frame + column - 2) % 36
    cells[column].text = value < 10 and string.char(string.byte("0") + value)
      or string.char(string.byte("a") + value - 10)
  end
  self.damage[1].row = row
  return self.snapshot, self.damage
end

return Fixture
