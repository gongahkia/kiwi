local Color = require("kiwi.renderer.color")

local CommandRegions = {}

CommandRegions.default_color = Color.pack(0x88, 0xc0, 0xd0, 0x55)
CommandRegions.visible_boundary_limit = 32

local roles = {
  { field = "prompt_start", name = "prompt", value = 1 },
  { field = "command_start", name = "command", value = 2 },
  { field = "output_start", name = "output", value = 3 },
  { field = "finish", name = "finish", value = 4 },
}

local function color_descriptor(color)
  local channels = Color.unpack(color)
  return {
    alpha = channels.alpha / 255,
    blue = channels.blue / 255,
    green = channels.green / 255,
    red = channels.red / 255,
  }
end

local function inactive()
  return {
    active = false,
    boundaries = { count = 0 },
    boundary_count = 0,
    omitted_boundary_count = 0,
  }
end

function CommandRegions.parse_color(value)
  if value == nil then return CommandRegions.default_color end
  assert(type(value) == "string", "command region color must be #RRGGBB or #RRGGBBAA")
  local red, green, blue, alpha = value:match("^#(%x%x)(%x%x)(%x%x)(%x%x)$")
  if red == nil then
    red, green, blue = value:match("^#(%x%x)(%x%x)(%x%x)$")
    alpha = "55"
  end
  assert(red ~= nil, "command region color must be #RRGGBB or #RRGGBBAA")
  return Color.pack(tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16), tonumber(alpha, 16))
end

function CommandRegions.color_descriptor(color)
  return color_descriptor(color or CommandRegions.default_color)
end

function CommandRegions.role_value(role)
  for _, candidate in ipairs(roles) do
    if candidate.name == role then return candidate.value end
  end
  return 0
end

local function visible_positions(model)
  local positions = {}
  for row = 0, model.rows - 1 do
    local visible = model:visible_row(row)
    if visible then positions[visible.line_id] = row end
  end
  return positions
end

function CommandRegions.descriptor(model)
  local descriptor = inactive()
  if type(model) ~= "table" or type(model.visible_row) ~= "function" or type(model.selection_scope) ~= "function"
    or type(model.command_regions) ~= "table" or type(model.command_regions.view) ~= "function" then
    return descriptor
  end
  local scope = model:selection_scope()
  local positions = visible_positions(model)
  local candidates = {}
  for _, region in ipairs(model.command_regions:view().regions) do
    for _, role in ipairs(roles) do
      local position = region[role.field]
      local row = position and position.scope == scope and positions[position.line_id] or nil
      if row ~= nil and type(position.column) == "number" and position.column >= 0 and position.column < model.columns then
        candidates[#candidates + 1] = { column = position.column, role = role.name, role_value = role.value, row = row }
      end
    end
  end
  table.sort(candidates, function(left, right)
    if left.row ~= right.row then return left.row < right.row end
    if left.column ~= right.column then return left.column < right.column end
    return left.role_value < right.role_value
  end)
  local seen = {}
  for _, candidate in ipairs(candidates) do
    local key = candidate.row .. ":" .. candidate.column .. ":" .. candidate.role
    if not seen[key] then
      seen[key] = true
      if descriptor.boundary_count < CommandRegions.visible_boundary_limit then
        descriptor.boundary_count = descriptor.boundary_count + 1
        descriptor.boundaries["boundary_" .. descriptor.boundary_count] = {
          column = candidate.column,
          role = candidate.role,
          row = candidate.row,
        }
      else
        descriptor.omitted_boundary_count = descriptor.omitted_boundary_count + 1
      end
    end
  end
  descriptor.boundaries.count = descriptor.boundary_count
  descriptor.active = descriptor.boundary_count > 0
  return descriptor
end

function CommandRegions.same(left, right)
  if left == right then return true end
  if left == nil or right == nil or left.active ~= right.active or left.boundary_count ~= right.boundary_count
    or left.omitted_boundary_count ~= right.omitted_boundary_count then
    return false
  end
  for index = 1, left.boundary_count do
    local first = left.boundaries["boundary_" .. index]
    local second = right.boundaries["boundary_" .. index]
    if first == nil or second == nil or first.column ~= second.column or first.role ~= second.role or first.row ~= second.row then return false end
  end
  return true
end

return CommandRegions
