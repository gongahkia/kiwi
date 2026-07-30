local Colour = require("renderer.colour")
local Errors = require("runtime.errors")
local GlyphCache = require("renderer.glyph_cache")
local LoveFont = require("renderer.love_font")

local Renderer = {}
local renderer_mt = {}
renderer_mt.__index = renderer_mt

Renderer.contract = {
  constructor = "new(config) -> renderer | nil, error",
  cell_metrics = "cell_metrics() -> cell_metrics | nil, error",
  draw = "draw(snapshot, damage?) -> nil, error?",
  glyph = "glyph(text, style?) -> glyph | nil, error",
  load_font = "load_font(graphics) -> cell_metrics | nil, error",
  resize = "resize(pixel_width, pixel_height) -> nil, error?",
  destroy = "destroy()",
}

local attributes = {
  bold = 1,
  conceal = 64,
  faint = 2,
  inverse = 32,
  strike = 128,
  underline = 8,
}

local cursor_styles = { beam = true, block = true, underline = true }

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function positive_integer(value, name)
  if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 1 then
    return config_error(name .. " must be a positive integer", { provided = value })
  end
  return value
end

local function has_attribute(value, attribute)
  return math.floor(value / attribute) % 2 == 1
end

local function valid_colour(value)
  if value == "default" then
    return true
  end
  if type(value) ~= "table" then
    return nil
  end
  if value.kind == "indexed" then
    return type(value.index) == "number"
      and value.index % 1 == 0
      and value.index >= 0
      and value.index <= 255
  end
  return value.kind == "rgb"
    and type(value.red) == "number"
    and value.red % 1 == 0
    and value.red >= 0
    and value.red <= 255
    and type(value.green) == "number"
    and value.green % 1 == 0
    and value.green >= 0
    and value.green <= 255
    and type(value.blue) == "number"
    and value.blue % 1 == 0
    and value.blue >= 0
    and value.blue <= 255
end

local function valid_cell(cell)
  if type(cell) ~= "table" or type(cell.text) ~= "string" then
    return nil
  end
  if
    (cell.width ~= 0 and cell.width ~= 1 and cell.width ~= 2)
    or type(cell.continuation) ~= "boolean"
  then
    return nil
  end
  if cell.continuation ~= (cell.width == 0) or (cell.continuation and cell.text ~= "") then
    return nil
  end
  if
    type(cell.attributes) ~= "number"
    or cell.attributes % 1 ~= 0
    or cell.attributes < 0
    or cell.attributes > 0xFFFFFFFF
  then
    return nil
  end
  return valid_colour(cell.foreground) and valid_colour(cell.background)
end

local function validate_snapshot(snapshot)
  if type(snapshot) ~= "table" then
    return config_error("renderer snapshot must be a table")
  end
  local columns, columns_error = positive_integer(snapshot.columns, "renderer snapshot columns")
  if not columns then
    return nil, columns_error
  end
  local rows, rows_error = positive_integer(snapshot.rows, "renderer snapshot rows")
  if not rows then
    return nil, rows_error
  end
  if type(snapshot.screen) ~= "table" or type(snapshot.screen.rows) ~= "table" then
    return config_error("renderer snapshot screen must contain rows")
  end
  for row = 1, rows do
    local source = snapshot.screen.rows[row]
    if type(source) ~= "table" or type(source.cells) ~= "table" then
      return config_error("renderer snapshot row is invalid", { row = row })
    end
    for column = 1, columns do
      if not valid_cell(source.cells[column]) then
        return config_error("renderer snapshot cell is invalid", { column = column, row = row })
      end
    end
  end
  if snapshot.cursor ~= nil then
    if type(snapshot.cursor) ~= "table" then
      return config_error("renderer snapshot cursor is invalid")
    end
    local cursor_column, cursor_column_error =
      positive_integer(snapshot.cursor.column, "renderer snapshot cursor column")
    if not cursor_column then
      return nil, cursor_column_error
    end
    local cursor_row, cursor_row_error =
      positive_integer(snapshot.cursor.row, "renderer snapshot cursor row")
    if not cursor_row then
      return nil, cursor_row_error
    end
    if cursor_column > columns or cursor_row > rows then
      return config_error("renderer snapshot cursor is outside the screen")
    end
  end
  if snapshot.cursor_visible ~= nil and type(snapshot.cursor_visible) ~= "boolean" then
    return config_error("renderer snapshot cursor visibility is invalid")
  end
  return columns, rows
end

local function graphics_method(graphics, name)
  if type(graphics) ~= "table" or type(graphics[name]) ~= "function" then
    return config_error("renderer graphics must implement " .. name)
  end
  return graphics[name]
end

local function draw_background(graphics, colour, x, y, width, height)
  graphics.setColor(colour.red, colour.green, colour.blue, 1)
  graphics.rectangle("fill", x, y, width, height)
end

local function draw_glyph(graphics, renderer, cell, foreground, x, y)
  if cell.continuation or cell.text == "" then
    return true
  end
  local style = has_attribute(cell.attributes, attributes.bold) and "bold" or "regular"
  local glyph, glyph_error = renderer:glyph(cell.text, style)
  if not glyph then
    return nil, glyph_error
  end
  local alpha = has_attribute(cell.attributes, attributes.faint) and 0.5 or 1
  graphics.setColor(foreground.red, foreground.green, foreground.blue, alpha)
  graphics.print(glyph.text, x, y)
  if style == "bold" then
    graphics.print(glyph.text, x + 1, y)
  end
  return true
end

local function draw_decorations(graphics, cell, foreground, x, y, width, height)
  if has_attribute(cell.attributes, attributes.underline) then
    graphics.setColor(foreground.red, foreground.green, foreground.blue, 1)
    graphics.line(x, y + height - 1, x + width, y + height - 1)
  end
  if has_attribute(cell.attributes, attributes.strike) then
    graphics.setColor(foreground.red, foreground.green, foreground.blue, 1)
    graphics.line(x, y + math.floor(height / 2), x + width, y + math.floor(height / 2))
  end
  return true
end

local function cursor_style(config)
  local style = config.cursor_style or "block"
  if not cursor_styles[style] then
    return config_error("renderer cursor style is unsupported", { provided = style })
  end
  return style
end

local function draw_cursor(graphics, metrics, snapshot, config)
  if snapshot.cursor == nil or snapshot.cursor_visible == false then
    return true
  end
  local style, style_error = cursor_style(config)
  if not style then
    return nil, style_error
  end
  local x = (snapshot.cursor.column - 1) * metrics.cell_width
  local y = (snapshot.cursor.row - 1) * metrics.cell_height
  graphics.setColor(0.9, 0.92, 0.98, 0.8)
  if style == "block" then
    graphics.rectangle("fill", x, y, metrics.cell_width, metrics.cell_height)
  elseif style == "beam" then
    graphics.rectangle(
      "fill",
      x,
      y,
      math.max(1, math.floor(metrics.cell_width / 6)),
      metrics.cell_height
    )
  else
    graphics.rectangle("fill", x, y + metrics.cell_height - 2, metrics.cell_width, 2)
  end
  return true
end

function Renderer.new(config)
  if type(config) ~= "table" then
    return nil, Errors.new("config_error", "renderer config must be a table")
  end
  return setmetatable({
    config = config,
    font = nil,
    glyph_cache = nil,
    metrics = nil,
    state = "bootstrap",
  }, renderer_mt)
end

function renderer_mt:load_font(graphics)
  if self.state == "destroyed" then
    return nil, Errors.new("renderer_resource_error", "renderer is destroyed")
  end
  local resource, resource_error = LoveFont.load(graphics, self.config)
  if not resource then
    return nil, resource_error
  end
  local cache, cache_error =
    GlyphCache.new(resource.font, resource.metrics, { max_entries = self.config.max_glyph_entries })
  if not cache then
    return nil, cache_error
  end
  self.font = resource.font
  self.graphics = graphics
  self.glyph_cache = cache
  self.metrics = resource.metrics
  return self:cell_metrics()
end

function renderer_mt:cell_metrics()
  if not self.metrics then
    return nil, Errors.new("renderer_resource_error", "renderer font is not loaded")
  end
  return {
    baseline = self.metrics.baseline,
    cell_height = self.metrics.cell_height,
    cell_width = self.metrics.cell_width,
  }
end

function renderer_mt:glyph(text, style)
  if not self.glyph_cache then
    return nil, Errors.new("renderer_resource_error", "renderer font is not loaded")
  end
  return self.glyph_cache:get(text, style)
end

function renderer_mt:draw(snapshot, damage)
  if damage ~= nil and type(damage) ~= "table" then
    return nil, Errors.new("config_error", "renderer damage must be a table")
  end
  local columns, rows = validate_snapshot(snapshot)
  if not columns then
    return nil, rows
  end
  if not self.font or not self.graphics then
    return nil, Errors.new("renderer_resource_error", "renderer font is not loaded")
  end
  for _, name in ipairs({ "line", "print", "rectangle", "setColor", "setFont" }) do
    local method, method_error = graphics_method(self.graphics, name)
    if not method then
      return nil, method_error
    end
  end
  self.graphics.setFont(self.font)
  local metrics = self.metrics
  for row = 1, rows do
    local y = (row - 1) * metrics.cell_height
    local source = snapshot.screen.rows[row]
    for column = 1, columns do
      local cell = source.cells[column]
      local x = (column - 1) * metrics.cell_width
      local width = metrics.cell_width
      local foreground, foreground_error =
        Colour.resolve(cell.foreground, Colour.default_foreground)
      if not foreground then
        return nil, foreground_error
      end
      local background, background_error =
        Colour.resolve(cell.background, Colour.default_background)
      if not background then
        return nil, background_error
      end
      if has_attribute(cell.attributes, attributes.inverse) then
        foreground, background = background, foreground
      end
      draw_background(self.graphics, background, x, y, width, metrics.cell_height)
      local glyph_foreground = has_attribute(cell.attributes, attributes.conceal) and background
        or foreground
      local drawn, draw_error = draw_glyph(self.graphics, self, cell, glyph_foreground, x, y)
      if not drawn then
        return nil, draw_error
      end
      local decorated, decoration_error =
        draw_decorations(self.graphics, cell, glyph_foreground, x, y, width, metrics.cell_height)
      if not decorated then
        return nil, decoration_error
      end
    end
  end
  local drawn_cursor, cursor_error = draw_cursor(self.graphics, metrics, snapshot, self.config)
  if not drawn_cursor then
    return nil, cursor_error
  end
  return true
end

function renderer_mt:resize(pixel_width, pixel_height)
  if type(pixel_width) ~= "number" or type(pixel_height) ~= "number" then
    return nil, Errors.new("config_error", "renderer dimensions must be numbers")
  end
  return nil, Errors.new("renderer_resource_error", "renderer is not implemented")
end

function renderer_mt:destroy()
  self.state = "destroyed"
end

return Renderer
