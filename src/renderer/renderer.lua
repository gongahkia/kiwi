local Colour = require("renderer.colour")
local Clean = require("renderer.clean")
local Dpi = require("renderer.dpi")
local Errors = require("runtime.errors")
local GlyphCache = require("renderer.glyph_cache")
local GlyphResolver = require("renderer.glyph_resolver")
local Grid = require("renderer.grid")
local LoveFont = require("renderer.love_font")
local Event = require("runtime.event")
local Snapshot = require("renderer.snapshot")

local Renderer = {}
local renderer_mt = {}
renderer_mt.__index = renderer_mt

Renderer.contract = {
  constructor = "new(config) -> renderer | nil, error",
  cell_metrics = "cell_metrics() -> cell_metrics | nil, error",
  draw = "draw(snapshot, damage?) -> nil, error?",
  draw_empty = "draw_empty() -> true | nil, error",
  draw_terminal = "draw_terminal(terminal, damage?) -> true | nil, error",
  glyph = "glyph(text, style?) -> glyph | nil, error",
  load_font = "load_font(graphics) -> cell_metrics | nil, error",
  preset = "preset() -> preset",
  resize = "resize(window_width, window_height, pixel_width?, pixel_height?) -> layout, resize_event? | nil, error",
  resize_window = "resize_window() -> layout, resize_event? | nil, error",
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
      local cell = source.cells[column]
      if cell.width == 2 then
        local continuation = source.cells[column + 1]
        if continuation == nil or not continuation.continuation then
          return config_error(
            "renderer snapshot wide cell is malformed",
            { column = column, row = row }
          )
        end
      elseif cell.continuation then
        local leading = source.cells[column - 1]
        if leading == nil or leading.width ~= 2 then
          return config_error("renderer snapshot continuation cell is malformed", {
            column = column,
            row = row,
          })
        end
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

local function validate_damage(damage, columns, rows)
  if damage == nil then
    return nil
  end
  if type(damage) ~= "table" then
    return config_error("renderer damage must be a table")
  end
  local ranges = {}
  local ordered_rows = {}
  local first_missing_index = 1
  for index, range in ipairs(damage) do
    first_missing_index = index + 1
    if type(range) ~= "table" then
      return config_error("renderer damage range is invalid", { index = index })
    end
    local row, row_error = positive_integer(range.row, "renderer damage row")
    if not row then
      return nil, row_error
    end
    local first, first_error = positive_integer(range.first_column, "renderer damage first column")
    if not first then
      return nil, first_error
    end
    local last, last_error = positive_integer(range.last_column, "renderer damage last column")
    if not last then
      return nil, last_error
    end
    if row > rows or first > columns or last > columns or first > last then
      return config_error("renderer damage range is outside the screen", { index = index })
    end
    local existing = ranges[row]
    if existing then
      existing.first_column = math.min(existing.first_column, first)
      existing.last_column = math.max(existing.last_column, last)
    else
      ranges[row] = { first_column = first, last_column = last, row = row }
      ordered_rows[#ordered_rows + 1] = row
    end
  end
  for key in pairs(damage) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key >= first_missing_index then
      return config_error("renderer damage must be a dense range array")
    end
  end
  table.sort(ordered_rows)
  return ranges, ordered_rows
end

local function add_damage_range(ranges, ordered_rows, row, first, last)
  local existing = ranges[row]
  if existing then
    existing.first_column = math.min(existing.first_column, first)
    existing.last_column = math.max(existing.last_column, last)
    return
  end
  ranges[row] = { first_column = first, last_column = last, row = row }
  ordered_rows[#ordered_rows + 1] = row
end

local function cursor_from_snapshot(snapshot)
  if snapshot.cursor == nil or snapshot.cursor_visible == false then
    return nil
  end
  return { column = snapshot.cursor.column, row = snapshot.cursor.row }
end

local function same_cursor(left, right)
  return left == right or (left and right and left.column == right.column and left.row == right.row)
end

local function cursor_in_damage(cursor, ranges)
  local range = cursor and ranges[cursor.row]
  return range and cursor.column >= range.first_column and cursor.column <= range.last_column
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

local function draw_cursor(graphics, metrics, snapshot, config, origin_x, origin_y)
  if snapshot.cursor == nil or snapshot.cursor_visible == false then
    return true
  end
  local style, style_error = cursor_style(config)
  if not style then
    return nil, style_error
  end
  local x = origin_x + (snapshot.cursor.column - 1) * metrics.cell_width
  local y = origin_y + (snapshot.cursor.row - 1) * metrics.cell_height
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
  local style, style_error = cursor_style(config)
  if not style then
    return nil, style_error
  end
  local preset_name = config.preset or Clean.id
  if preset_name ~= Clean.id then
    return config_error("renderer preset is unsupported", { provided = preset_name })
  end
  local preset, preset_error = Clean.new()
  if not preset then
    return nil, preset_error
  end
  return setmetatable({
    config = config,
    font = nil,
    glyph_cache = nil,
    glyph_resolver = nil,
    grid = nil,
    last_cursor = nil,
    metrics = nil,
    needs_full_redraw = false,
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
  local resolver, resolver_error =
    GlyphResolver.new(resource.font, { max_entries = self.config.max_glyph_entries })
  if not resolver then
    return nil, resolver_error
  end
  self.font = resource.font
  self.graphics = graphics
  self.glyph_cache = cache
  self.glyph_resolver = resolver
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

function renderer_mt:preset()
  return Clean.new()
end

function renderer_mt:glyph(text, style)
  if not self.glyph_cache or not self.glyph_resolver then
    return nil, Errors.new("renderer_resource_error", "renderer font is not loaded")
  end
  local display_text, display_text_error = self.glyph_resolver:resolve(text)
  if not display_text then
    return nil, display_text_error
  end
  return self.glyph_cache:get(display_text, style)
end

function renderer_mt:draw(snapshot, damage)
  local columns, rows = validate_snapshot(snapshot)
  if not columns then
    return nil, rows
  end
  if self.grid and (columns ~= self.grid.columns or rows ~= self.grid.rows) then
    return config_error("renderer snapshot dimensions do not match the window grid", {
      grid_columns = self.grid.columns,
      grid_rows = self.grid.rows,
      snapshot_columns = columns,
      snapshot_rows = rows,
    })
  end
  local full_redraw = damage == nil or self.needs_full_redraw
  local ranges, ordered_rows_or_error =
    validate_damage(full_redraw and nil or damage, columns, rows)
  if not full_redraw and not ranges then
    return nil, ordered_rows_or_error
  end
  local ordered_rows = ordered_rows_or_error
  local current_cursor = cursor_from_snapshot(snapshot)
  local cursor_changed = not same_cursor(self.last_cursor, current_cursor)
  local cursor_needs_draw = full_redraw
  if not full_redraw and cursor_changed then
    if self.last_cursor and self.last_cursor.row <= rows and self.last_cursor.column <= columns then
      add_damage_range(
        ranges,
        ordered_rows,
        self.last_cursor.row,
        self.last_cursor.column,
        self.last_cursor.column
      )
    end
    if current_cursor then
      add_damage_range(
        ranges,
        ordered_rows,
        current_cursor.row,
        current_cursor.column,
        current_cursor.column
      )
      cursor_needs_draw = true
    end
  elseif not full_redraw and cursor_in_damage(current_cursor, ranges) then
    cursor_needs_draw = true
  end
  if ordered_rows then
    table.sort(ordered_rows)
  end
  local style, style_error = cursor_style(self.config)
  if not style then
    return nil, style_error
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
  if not full_redraw and #ordered_rows == 0 then
    self.last_cursor = current_cursor
    return true
  end
  self.graphics.setFont(self.font)
  local metrics = self.metrics
  local origin_x = self.grid and self.grid.x or 0
  local origin_y = self.grid and self.grid.y or 0
  local first_row = full_redraw and 1 or nil
  local last_row = full_redraw and rows or nil
  local function draw_range(row, first, last)
    local y = (row - 1) * metrics.cell_height
    local source = snapshot.screen.rows[row]
    if source.cells[first].continuation then
      first = first - 1
    end
    if source.cells[last].width == 2 then
      last = last + 1
    end
    for column = first, last do
      local cell = source.cells[column]
      if not cell.continuation then
        local x = origin_x + (column - 1) * metrics.cell_width
        local width = cell.width * metrics.cell_width
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
    return true
  end
  if first_row then
    for row = first_row, last_row do
      local drawn, draw_error = draw_range(row, 1, columns)
      if not drawn then
        return nil, draw_error
      end
    end
  else
    for _, row in ipairs(ordered_rows) do
      local range = ranges[row]
      local drawn, draw_error = draw_range(row, range.first_column, range.last_column)
      if not drawn then
        return nil, draw_error
      end
    end
  end
  if cursor_needs_draw then
    local drawn_cursor, cursor_error =
      draw_cursor(self.graphics, metrics, snapshot, self.config, origin_x, origin_y)
    if not drawn_cursor then
      return nil, cursor_error
    end
  end
  self.last_cursor = current_cursor
  self.needs_full_redraw = false
  return true
end

function renderer_mt:draw_empty()
  if self.state == "destroyed" then
    return nil, Errors.new("renderer_resource_error", "renderer is destroyed")
  end
  if not self.graphics or not self.grid then
    return nil, Errors.new("renderer_resource_error", "renderer window is not initialised")
  end
  for _, name in ipairs({ "rectangle", "setColor" }) do
    local method, method_error = graphics_method(self.graphics, name)
    if not method then
      return nil, method_error
    end
  end
  self.graphics.setColor(0.035, 0.045, 0.07, 1)
  self.graphics.rectangle("fill", 0, 0, self.grid.window_width, self.grid.window_height)
  return true
end

function renderer_mt:draw_terminal(terminal, damage)
  local snapshot, snapshot_error = Snapshot.from_terminal(terminal)
  if not snapshot then
    return nil, snapshot_error
  end
  return self:draw(snapshot, damage)
end

function renderer_mt:resize(window_width, window_height, pixel_width, pixel_height)
  if self.state == "destroyed" then
    return nil, Errors.new("renderer_resource_error", "renderer is destroyed")
  end
  if not self.metrics then
    return nil, Errors.new("renderer_resource_error", "renderer font is not loaded")
  end
  local layout, layout_error = Grid.layout(self.metrics, window_width, window_height, {
    padding = self.config.padding,
  })
  if not layout then
    return nil, layout_error
  end
  local event, event_error = Event.resize(
    layout.columns,
    layout.rows,
    pixel_width or layout.window_width,
    pixel_height or layout.window_height
  )
  if not event then
    return nil, event_error
  end
  local previous = self.grid
  if
    previous
    and previous.window_width == layout.window_width
    and previous.window_height == layout.window_height
    and previous.padding == layout.padding
    and previous.pixel_width == event.pixel_width
    and previous.pixel_height == event.pixel_height
  then
    return layout
  end
  layout.pixel_height = event.pixel_height
  layout.pixel_width = event.pixel_width
  self.grid = layout
  self.needs_full_redraw = true
  return layout, event
end

function renderer_mt:resize_window()
  if self.state == "destroyed" then
    return nil, Errors.new("renderer_resource_error", "renderer is destroyed")
  end
  if not self.graphics then
    return nil, Errors.new("renderer_resource_error", "renderer font is not loaded")
  end
  local dimensions, dimensions_error = Dpi.dimensions(self.graphics)
  if not dimensions then
    return nil, dimensions_error
  end
  local layout, event_or_error = self:resize(
    dimensions.window_width,
    dimensions.window_height,
    dimensions.pixel_width,
    dimensions.pixel_height
  )
  if not layout then
    return nil, event_or_error
  end
  layout.dpi_scale = dimensions.dpi_scale
  return layout, event_or_error
end

function renderer_mt:destroy()
  self.state = "destroyed"
end

return Renderer
