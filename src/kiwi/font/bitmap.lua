local Bitmap = { color_flag = 0x20000000, bytes_per_pixel = 4 }

-- The atlas stores grayscale coverage in R, and premultiplied sRGB RGBA for
-- colour glyphs. Keeping premultiplication through resampling avoids fringes.
function Bitmap.describe(source, maximum)
  if source.pixel_mode ~= 2 and source.pixel_mode ~= 7 then return nil, "unsupported-pixel-mode" end
  if source.width == 0 or source.height == 0 then return nil, "empty-bitmap" end
  local channels = source.pixel_mode == 7 and 4 or 1
  local scale = source.scale or 1
  if source.width < 0 or source.height < 0 or source.width > 2048 or source.height > 2048
    or source.pitch < source.width * channels or source.pitch > 16384
    or source.buffer == nil or scale ~= scale or scale <= 0 then return nil, "bitmap-limit" end
  local width = math.max(1, math.floor(source.width * scale + 0.5))
  local height = math.max(1, math.floor(source.height * scale + 0.5))
  if width > maximum or height > maximum then return nil, "bitmap-limit" end
  return {
    width = width, height = height,
    left = (source.left or 0) * scale, top = (source.top or 0) * scale,
    advance = (source.advance or 0) * scale,
    color = channels == 4,
  }
end

local function sample(source, x, y, channel)
  local offset = y * source.pitch
  if source.pixel_mode == 7 then
    return source.buffer[offset + x * 4 + (channel == 0 and 2 or channel == 2 and 0 or channel)]
  end
  return (channel == 0 or channel == 3) and source.buffer[offset + x] or 0
end

function Bitmap.write(source, bitmap, pixels, stride, x, y)
  local width, height = bitmap.width, bitmap.height
  if width == source.width and height == source.height then
    for row = 0, height - 1 do
      local destination = pixels + ((y + row) * stride + x) * 4
      local input = source.buffer + row * source.pitch
      for column = 0, width - 1 do
        local offset = column * 4
        if bitmap.color then
          destination[offset], destination[offset + 1] = input[offset + 2], input[offset + 1]
          destination[offset + 2], destination[offset + 3] = input[offset], input[offset + 3]
        else
          destination[offset], destination[offset + 3] = input[column], input[column]
          destination[offset + 1], destination[offset + 2] = 0, 0
        end
      end
    end
    return
  end
  for row = 0, height - 1 do
    local sy = math.max(0, math.min(source.height - 1, (row + 0.5) * source.height / height - 0.5))
    local y0 = math.floor(sy)
    local y1 = math.min(y0 + 1, source.height - 1)
    local fy = sy - y0
    for column = 0, width - 1 do
      local sx = math.max(0, math.min(source.width - 1, (column + 0.5) * source.width / width - 0.5))
      local x0 = math.floor(sx)
      local x1 = math.min(x0 + 1, source.width - 1)
      local fx = sx - x0
      local destination = ((y + row) * stride + x + column) * 4
      for channel = 0, 3 do
        local upper = sample(source, x0, y0, channel) * (1 - fx) + sample(source, x1, y0, channel) * fx
        local lower = sample(source, x0, y1, channel) * (1 - fx) + sample(source, x1, y1, channel) * fx
        pixels[destination + channel] = math.floor(upper * (1 - fy) + lower * fy + 0.5)
      end
    end
  end
end

return Bitmap
