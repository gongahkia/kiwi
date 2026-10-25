local Color = require("kiwi.renderer.color")

local Selection = {}

Selection.default_color = Color.pack(0x5e, 0x81, 0xac, 0x70)

local function color_descriptor(color)
  local channels = Color.unpack(color)
  return {
    alpha = channels.alpha / 255,
    blue = channels.blue / 255,
    green = channels.green / 255,
    red = channels.red / 255,
  }
end

function Selection.parse_color(value)
  if value == nil then return Selection.default_color end
  assert(type(value) == "string", "selection color must be #RRGGBB or #RRGGBBAA")
  local red, green, blue, alpha = value:match("^#(%x%x)(%x%x)(%x%x)(%x%x)$")
  if red == nil then
    red, green, blue = value:match("^#(%x%x)(%x%x)(%x%x)$")
    alpha = "70"
  end
  assert(red ~= nil, "selection color must be #RRGGBB or #RRGGBBAA")
  return Color.pack(tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16), tonumber(alpha, 16))
end

local function inactive(color)
  return {
    active = false,
    color = color_descriptor(color),
    finish_column = 0,
    finish_row = 0,
    start_column = 0,
    start_row = 0,
  }
end

local function row_positions(model, scope)
  local positions = {}
  for index, entry in ipairs(model:selection_rows(scope, true)) do
    positions[entry.line_id] = index - 1
  end
  return positions
end

function Selection.descriptor(model, color)
  color = color or Selection.default_color
  local descriptor = inactive(color)
  if type(model.selection_view) ~= "function" or type(model.selection_rows) ~= "function" or type(model.visible_row) ~= "function" then return descriptor end
  local view = model:selection_view()
  if not view.active or not view.visible or view.empty then return descriptor end
  local start, finish, top_index
  if model.document and view.start.row_index and view.finish.row_index then
    start, finish = view.start.row_index - 1, view.finish.row_index - 1
    top_index = model:document(view.scope):top() - 1
  else
    local positions = row_positions(model, view.scope)
    local top = model:visible_row(0)
    start, finish, top_index = positions[view.start.line_id], positions[view.finish.line_id], top and positions[top.line_id]
  end
  if start == nil or finish == nil or top_index == nil then return descriptor end
  descriptor.start_column = view.start.column
  descriptor.start_row = start - top_index
  descriptor.finish_column = view.finish.column
  descriptor.finish_row = finish - top_index
  descriptor.block = view.mode == "block"
  local first = descriptor.start_row * model.columns + descriptor.start_column
  local last = descriptor.finish_row * model.columns + descriptor.finish_column
  descriptor.active = descriptor.color.alpha > 0 and first < model.columns * model.rows and last > 0
  if descriptor.block then
    descriptor.active = descriptor.color.alpha > 0 and descriptor.start_column < descriptor.finish_column
      and descriptor.finish_row >= 0 and descriptor.start_row < model.rows
  end
  return descriptor
end

return Selection
