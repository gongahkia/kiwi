local ffi = require("ffi")

-- Decorations share the bounded alpha atlas with text. A cell-sized mask
-- preserves phase across spaces, wide cells and adjacent font fallback runs.
local Decoration = { hyperlink_flag = 0x800, strike = 6 }
Decoration.__index = Decoration

function Decoration.new(metrics)
  local width, height = metrics.cell_width, metrics.cell_height
  local thickness = math.max(1, math.floor((metrics.underline_thickness or height / 18) + 0.5))
  thickness = math.min(thickness, math.max(1, math.floor(height / 5)))
  return setmetatable({
    id = 0, -- Native font face IDs start at one; each font system owns a cache.
    pixel_height = height,
    width = width, height = height,
    thickness = thickness,
    center = math.max(0.5, math.min(height - thickness / 2,
      math.floor((metrics.baseline or height * 0.75) + (metrics.underline_offset or 1)) + 0.5)),
    strike_center = math.floor((metrics.baseline or height * 0.75) * 0.6) + 0.5,
    native = { pixel_mode_gray = 2 },
  }, Decoration)
end

local function line(y, center, thickness)
  return math.max(0, math.min(1, thickness / 2 + 0.5 - math.abs(y - center)))
end

function Decoration:rasterize(style)
  assert(style >= 1 and style <= 6, "unknown decoration style")
  local width, height, thickness = self.width, self.height, self.thickness
  local pixels = ffi.new("uint8_t[?]", width * height)
  local period = width / math.max(1, math.floor(width / (4 * thickness)))
  local amplitude = thickness
  local curly_center = math.max(amplitude + thickness / 2, math.min(self.center, height - amplitude - thickness / 2))
  for row = 0, height - 1 do
    for column = 0, width - 1 do
      local x, y = column + 0.5, row + 0.5
      local coverage
      if style == 2 then
        coverage = math.max(line(y, self.center, thickness), line(y, self.center - 2 * thickness, thickness))
      elseif style == 3 then
        coverage = line(y, curly_center + amplitude * math.sin(x / width * math.pi * 2), thickness)
      elseif style == 4 then
        local dx, dy = x % period - period / 2, y - self.center
        coverage = math.max(0, math.min(1, thickness / 2 + 0.5 - math.sqrt(dx * dx + dy * dy)))
      elseif style == 5 then
        coverage = x % width < width * 0.67 and line(y, self.center, thickness) or 0
      else
        coverage = line(y, style == 6 and self.strike_center or self.center, thickness)
      end
      pixels[row * width + column] = math.floor(coverage * 255 + 0.5)
    end
  end
  -- Keep the FFI allocation alive through the cache's copy operation.
  self.buffer = pixels
  return { width = width, height = height, pitch = width, buffer = pixels,
    pixel_mode = 2, left = 0, top = height, advance = width }
end

return Decoration
