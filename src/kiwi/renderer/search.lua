local Color = require("kiwi.renderer.color")

local Search = {}

Search.default_color = Color.pack(0xeb, 0xcb, 0x8b, 0x70)

local function color_descriptor(color)
  local channels = Color.unpack(color)
  return {
    alpha = channels.alpha / 255,
    blue = channels.blue / 255,
    green = channels.green / 255,
    red = channels.red / 255,
  }
end

function Search.parse_color(value)
  if value == nil then return Search.default_color end
  assert(type(value) == "string", "search color must be #RRGGBB or #RRGGBBAA")
  local red, green, blue, alpha = value:match("^#(%x%x)(%x%x)(%x%x)(%x%x)$")
  if red == nil then
    red, green, blue = value:match("^#(%x%x)(%x%x)(%x%x)$")
    alpha = "70"
  end
  assert(red ~= nil, "search color must be #RRGGBB or #RRGGBBAA")
  return Color.pack(tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16), tonumber(alpha, 16))
end

local function inactive(color)
  return {
    active = false,
    color = color_descriptor(color),
    current_index = 0,
    finish_column = 0,
    finish_row = 0,
    match_count = 0,
    start_column = 0,
    start_row = 0,
    status = "inactive",
    visible_matches = { count = 0 },
  }
end

local function row_positions(model, scope)
  local positions = {}
  for index, entry in ipairs(model:selection_rows(scope)) do
    positions[entry.line_id] = index - 1
  end
  return positions
end

local function viewport_range(match, positions, top_index)
  local row = positions[match.line_id]
  if row == nil then return nil end
  return {
    finish_column = match.finish_column,
    finish_row = row - top_index,
    start_column = match.start_column,
    start_row = row - top_index,
  }
end

function Search.descriptor(model, color)
  color = color or Search.default_color
  local descriptor = inactive(color)
  if type(model.search_view) ~= "function" or type(model.selection_rows) ~= "function" or type(model.visible_row) ~= "function" then return descriptor end
  local view = model:search_view()
  descriptor.status = view.status
  descriptor.match_count = view.match_count
  descriptor.current_index = view.current_index
  if not view.active or not view.visible then return descriptor end
  local positions = row_positions(model, view.scope)
  local top = model:visible_row(0)
  local top_index = top and positions[top.line_id]
  if top_index == nil then return descriptor end
  local visible = { count = 0 }
  for _, match in ipairs(view.matches) do
    local range = viewport_range(match, positions, top_index)
    if range and range.start_row >= 0 and range.start_row < model.rows then
      visible.count = visible.count + 1
      visible["match_" .. visible.count] = range
    end
  end
  descriptor.visible_matches = visible
  if view.current == nil then return descriptor end
  local current = viewport_range(view.current, positions, top_index)
  if current == nil then return descriptor end
  descriptor.start_column = current.start_column
  descriptor.start_row = current.start_row
  descriptor.finish_column = current.finish_column
  descriptor.finish_row = current.finish_row
  descriptor.active = descriptor.color.alpha > 0 and current.start_row >= 0 and current.start_row < model.rows
  return descriptor
end

return Search
