local Color = require("kiwi.renderer.color")

local Hyperlink = {}

Hyperlink.default_color = Color.pack(0x88, 0xc0, 0xd0, 0xff)

local function color_descriptor(color)
  local channels = Color.unpack(color)
  return {
    alpha = channels.alpha / 255,
    blue = channels.blue / 255,
    green = channels.green / 255,
    red = channels.red / 255,
  }
end

function Hyperlink.parse_color(value)
  if value == nil then return Hyperlink.default_color end
  assert(type(value) == "string", "hyperlink color must be #RRGGBB or #RRGGBBAA")
  local red, green, blue, alpha = value:match("^#(%x%x)(%x%x)(%x%x)(%x%x)$")
  if red == nil then
    red, green, blue = value:match("^#(%x%x)(%x%x)(%x%x)$")
    alpha = "ff"
  end
  assert(red ~= nil, "hyperlink color must be #RRGGBB or #RRGGBBAA")
  return Color.pack(tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16), tonumber(alpha, 16))
end

function Hyperlink.descriptor(model, color)
  color = color or Hyperlink.default_color
  local descriptor = { active = false, color = color_descriptor(color), visible_cells = 0 }
  if type(model.cells) ~= "table" or type(model.columns) ~= "number" or type(model.rows) ~= "number" then return descriptor end
  for index = 0, model.columns * model.rows - 1 do
    local cell = model.cells[index]
    if cell and cell.hyperlink_id ~= nil then descriptor.visible_cells = descriptor.visible_cells + 1 end
  end
  descriptor.active = descriptor.visible_cells > 0 and descriptor.color.alpha > 0
  if not descriptor.active then descriptor.color.alpha = 0 end
  return descriptor
end

return Hyperlink
