local viewport = {
  columns = 80,
  rows = 24,
  padding = 32,
}

local function grid_metrics()
  local width, height = love.graphics.getDimensions()
  local usable_width = math.max(1, width - viewport.padding * 2)
  local usable_height = math.max(1, height - viewport.padding * 2)
  local cell_width = math.floor(usable_width / viewport.columns)
  local cell_height = math.floor(usable_height / viewport.rows)
  local size = math.max(1, math.min(cell_width, cell_height))
  local grid_width = size * viewport.columns
  local grid_height = size * viewport.rows
  return size, (width - grid_width) / 2, (height - grid_height) / 2, grid_width, grid_height
end

function love.load()
  love.graphics.setBackgroundColor(0.035, 0.045, 0.07, 1)
end

function love.draw()
  local cell_size, x, y, grid_width, grid_height = grid_metrics()
  love.graphics.setColor(0.08, 0.1, 0.15, 1)
  love.graphics.rectangle("fill", x, y, grid_width, grid_height)
  love.graphics.setColor(0.22, 0.28, 0.4, 1)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, grid_width, grid_height)
  for column = 1, viewport.columns - 1 do
    local line_x = x + column * cell_size
    love.graphics.line(line_x, y, line_x, y + grid_height)
  end
  for row = 1, viewport.rows - 1 do
    local line_y = y + row * cell_size
    love.graphics.line(x, line_y, x + grid_width, line_y)
  end
end
