local bit = require("bit")
local ffi = require("ffi")
local Gif = require("kiwi.ffi.gif")
local Png = require("kiwi.ffi.png")

local ImageDecoder = {}

ImageDecoder.default_max_frames = 256
ImageDecoder.default_max_animation_bytes = 32 * 1024 * 1024
ImageDecoder.minimum_delay = 1 / 60
ImageDecoder.zero_delay = 0.1

local png_signature = "\137PNG\r\n\26\n"

local function positive_integer(value, name)
  assert(type(value) == "number" and value >= 1 and value % 1 == 0, name .. " must be a positive integer")
  return value
end

local function be16(bytes, offset)
  return bytes:byte(offset) * 0x100 + bytes:byte(offset + 1)
end

local function le16(bytes, offset)
  return bytes:byte(offset) + bytes:byte(offset + 1) * 0x100
end

local function be32(bytes, offset)
  return ((bytes:byte(offset) * 0x100 + bytes:byte(offset + 1)) * 0x100 + bytes:byte(offset + 2)) * 0x100 + bytes:byte(offset + 3)
end

local function pack32(value)
  return string.char(
    math.floor(value / 0x1000000) % 0x100,
    math.floor(value / 0x10000) % 0x100,
    math.floor(value / 0x100) % 0x100,
    value % 0x100
  )
end

local function unsigned(value)
  return value < 0 and value + 0x100000000 or value
end

local function crc32(bytes)
  local value = -1
  for index = 1, #bytes do
    value = bit.bxor(value, bytes:byte(index))
    for _ = 1, 8 do
      if bit.band(value, 1) ~= 0 then
        value = bit.bxor(bit.rshift(value, 1), 0xedb88320)
      else
        value = bit.rshift(value, 1)
      end
    end
  end
  return unsigned(bit.bnot(value))
end

local function png_chunk(kind, data)
  return pack32(#data) .. kind .. data .. pack32(crc32(kind .. data))
end

local function clamped_delay(numerator, denominator)
  if numerator == 0 then return ImageDecoder.zero_delay end
  if denominator == 0 then denominator = 100 end
  return math.max(ImageDecoder.minimum_delay, numerator / denominator)
end

local function opaque_or_over(destination, destination_offset, source, source_offset)
  local source_alpha = tonumber(source[source_offset + 3])
  if source_alpha == 0 then return end
  if source_alpha == 255 then
    destination[destination_offset] = source[source_offset]
    destination[destination_offset + 1] = source[source_offset + 1]
    destination[destination_offset + 2] = source[source_offset + 2]
    destination[destination_offset + 3] = 255
    return
  end
  local destination_alpha = tonumber(destination[destination_offset + 3])
  local output_alpha = source_alpha + math.floor((destination_alpha * (255 - source_alpha) + 127) / 255)
  if output_alpha == 0 then
    destination[destination_offset] = 0
    destination[destination_offset + 1] = 0
    destination[destination_offset + 2] = 0
    destination[destination_offset + 3] = 0
    return
  end
  for channel = 0, 2 do
    local source_value = tonumber(source[source_offset + channel])
    local destination_value = tonumber(destination[destination_offset + channel])
    local numerator = source_value * source_alpha * 255 + destination_value * destination_alpha * (255 - source_alpha)
    destination[destination_offset + channel] = math.floor((numerator + output_alpha * 127) / (output_alpha * 255))
  end
  destination[destination_offset + 3] = output_alpha
end

local function clear_rectangle(canvas, canvas_width, left, top, width, height)
  for row = top, top + height - 1 do
    local offset = (row * canvas_width + left) * 4
    ffi.fill(canvas + offset, width * 4, 0)
  end
end

local function copy_frame(canvas, bytes)
  local frame = ffi.new("uint8_t[?]", bytes)
  ffi.copy(frame, canvas, bytes)
  return frame
end

local function check_animation_limits(options, frame_count, bytes)
  if frame_count > options.max_frames then return nil, "animation-frame-limit" end
  if bytes > options.max_animation_bytes then return nil, "animation-byte-limit" end
  return true
end

local function result(format, width, height, frames, plays)
  local frame_bytes = width * height * 4
  return {
    animated = #frames > 1,
    bytes = frame_bytes * #frames,
    format = format,
    frame_bytes = frame_bytes,
    frames = frames,
    height = height,
    plays = plays or 1,
    width = width,
  }
end

local function decode_static_png(bytes, expected_width, expected_height)
  local decoded, pixels, reason = pcall(Png.decode_rgba, bytes, expected_width, expected_height, expected_width * expected_height * 4)
  if not decoded then return nil, "png-decode" end
  if pixels == nil then return nil, reason or "png-decode" end
  return result("png", expected_width, expected_height, { { duration = 0, pixels = pixels } }, 1)
end

local function parse_png(bytes)
  if #bytes < 45 or bytes:sub(1, 8) ~= png_signature then return nil, "png-header" end
  local chunks = {}
  local offset = 9
  while offset <= #bytes do
    if offset + 11 > #bytes then return nil, "apng-chunk" end
    local length = be32(bytes, offset)
    local finish = offset + 11 + length
    if finish > #bytes then return nil, "apng-chunk" end
    local kind = bytes:sub(offset + 4, offset + 7)
    local data = bytes:sub(offset + 8, offset + 7 + length)
    if crc32(kind .. data) ~= be32(bytes, offset + 8 + length) then return nil, "apng-crc" end
    chunks[#chunks + 1] = { data = data, kind = kind }
    offset = finish + 1
  end
  if offset ~= #bytes + 1 or #chunks == 0 or chunks[1].kind ~= "IHDR" or #chunks[1].data ~= 13 then return nil, "apng-chunk" end
  return chunks
end

local function has_apng_chunk(bytes)
  if #bytes < 33 or bytes:sub(1, 8) ~= png_signature then return false end
  local offset = 9
  while offset + 11 <= #bytes do
    local length = be32(bytes, offset)
    local finish = offset + 11 + length
    if finish > #bytes then return false end
    if bytes:sub(offset + 4, offset + 7) == "acTL" then return true end
    offset = finish + 1
  end
  return false
end

local function parse_apng(bytes, expected_width, expected_height, options)
  local chunks, reason = parse_png(bytes)
  if chunks == nil then return nil, reason end
  local ihdr = chunks[1].data
  local width = be32(ihdr, 1)
  local height = be32(ihdr, 5)
  if width ~= expected_width or height ~= expected_height then return nil, "png-dimensions" end

  local ancillary = {}
  local frames = {}
  local expected_sequence = 0
  local declared_frames
  local plays
  local current
  local seen_actl = false
  local seen_idat = false
  local seen_iend = false

  local function next_sequence(data)
    local sequence = be32(data, 1)
    if sequence ~= expected_sequence then return nil end
    expected_sequence = expected_sequence + 1
    return true
  end

  local function finish_frame()
    if current == nil or #current.data == 0 then return nil, "apng-frame-data" end
    frames[#frames + 1] = current
    current = nil
    return true
  end

  for _, chunk in ipairs(chunks) do
    local data = chunk.data
    local kind = chunk.kind
    if seen_iend then return nil, "apng-chunk" end
    if kind == "IHDR" then
      if chunk ~= chunks[1] then return nil, "apng-chunk" end
    elseif kind == "acTL" then
      if seen_actl or seen_idat or #data ~= 8 then return nil, "apng-chunk" end
      declared_frames = be32(data, 1)
      plays = be32(data, 5)
      if declared_frames == 0 or declared_frames > options.max_frames then return nil, "animation-frame-limit" end
      seen_actl = true
    elseif kind == "fcTL" then
      if not seen_actl or #data ~= 26 or not next_sequence(data) then return nil, "apng-frame-control" end
      if current then
        local ok, finish_reason = finish_frame()
        if not ok then return nil, finish_reason end
      end
      local frame_width = be32(data, 5)
      local frame_height = be32(data, 9)
      local left = be32(data, 13)
      local top = be32(data, 17)
      local disposal = data:byte(25)
      local blend = data:byte(26)
      if frame_width == 0 or frame_height == 0 or left + frame_width > width or top + frame_height > height
        or disposal > 2 or blend > 1 then
        return nil, "apng-frame-control"
      end
      if #frames + 1 > options.max_frames then return nil, "animation-frame-limit" end
      current = {
        blend = blend,
        data = {},
        delay = clamped_delay(be16(data, 21), be16(data, 23)),
        disposal = disposal,
        height = frame_height,
        left = left,
        top = top,
        width = frame_width,
      }
    elseif kind == "IDAT" then
      if not seen_actl or current == nil or #frames ~= 0 or seen_iend then return nil, "apng-frame-data" end
      seen_idat = true
      current.data[#current.data + 1] = data
    elseif kind == "fdAT" then
      if not seen_actl or not seen_idat or current == nil or #frames == 0 or #data < 5 or not next_sequence(data) or seen_iend then
        return nil, "apng-frame-data"
      end
      current.data[#current.data + 1] = data:sub(5)
    elseif kind == "IEND" then
      if seen_iend or #data ~= 0 then return nil, "apng-chunk" end
      seen_iend = true
      if current then
        local ok, finish_reason = finish_frame()
        if not ok then return nil, finish_reason end
      end
    elseif kind == "PLTE" or kind == "tRNS" then
      if seen_idat then return nil, "apng-chunk" end
      ancillary[#ancillary + 1] = png_chunk(kind, data)
    elseif kind:byte(1) >= 65 and kind:byte(1) <= 90 then
      return nil, "apng-chunk"
    end
  end

  if not seen_actl or not seen_idat or not seen_iend or current ~= nil or #frames ~= declared_frames then return nil, "apng-chunk" end
  local frame_bytes = width * height * 4
  local ok, limit_reason = check_animation_limits(options, #frames, frame_bytes * #frames)
  if not ok then return nil, limit_reason end

  local canvas = ffi.new("uint8_t[?]", frame_bytes)
  local previous
  local output = {}
  for index, frame in ipairs(frames) do
    if previous then
      if previous.disposal == 1 then
        clear_rectangle(canvas, width, previous.left, previous.top, previous.width, previous.height)
      elseif previous.disposal == 2 and previous.canvas then
        ffi.copy(canvas, previous.canvas, frame_bytes)
      end
    end
    local frame_png = png_signature
      .. png_chunk("IHDR", pack32(frame.width) .. pack32(frame.height) .. ihdr:sub(9))
      .. table.concat(ancillary)
      .. png_chunk("IDAT", table.concat(frame.data))
      .. png_chunk("IEND", "")
    local decoded, pixels, decode_reason = pcall(Png.decode_rgba, frame_png, frame.width, frame.height, frame.width * frame.height * 4)
    if not decoded or pixels == nil then return nil, decode_reason or "apng-decode" end
    local restore = frame.disposal == 2 and copy_frame(canvas, frame_bytes) or nil
    if frame.blend == 0 then clear_rectangle(canvas, width, frame.left, frame.top, frame.width, frame.height) end
    for row = 0, frame.height - 1 do
      for column = 0, frame.width - 1 do
        local source_offset = (row * frame.width + column) * 4
        local destination_offset = ((frame.top + row) * width + frame.left + column) * 4
        if frame.blend == 0 then
          ffi.copy(canvas + destination_offset, pixels + source_offset, 4)
        else
          opaque_or_over(canvas, destination_offset, pixels, source_offset)
        end
      end
    end
    output[index] = { duration = frame.delay, pixels = copy_frame(canvas, frame_bytes) }
    previous = {
      canvas = restore,
      disposal = frame.disposal,
      height = frame.height,
      left = frame.left,
      top = frame.top,
      width = frame.width,
    }
  end
  return result("apng", width, height, output, plays)
end

local function gif_loop_count(bytes)
  if #bytes < 13 then return nil, "gif-header" end
  local offset = 14
  local packed = bytes:byte(11)
  if bit.band(packed, 0x80) ~= 0 then offset = offset + 3 * (2 ^ (bit.band(packed, 7) + 1)) end
  while offset <= #bytes do
    local marker = bytes:byte(offset)
    offset = offset + 1
    if marker == 0x3b then return nil end
    if marker == 0x21 then
      if offset > #bytes then return nil, "gif-extension" end
      local label = bytes:byte(offset)
      offset = offset + 1
      if offset > #bytes then return nil, "gif-extension" end
      local first_size = bytes:byte(offset)
      offset = offset + 1
      if offset + first_size - 1 > #bytes then return nil, "gif-extension" end
      local application = bytes:sub(offset, offset + first_size - 1)
      offset = offset + first_size
      local first_data
      while true do
        if offset > #bytes then return nil, "gif-extension" end
        local size = bytes:byte(offset)
        offset = offset + 1
        if size == 0 then break end
        if offset + size - 1 > #bytes then return nil, "gif-extension" end
        local data = bytes:sub(offset, offset + size - 1)
        offset = offset + size
        if first_data == nil then first_data = data end
      end
      if label == 0xff and (application == "NETSCAPE2.0" or application == "ANIMEXTS1.0")
        and first_data and #first_data >= 3 and first_data:byte(1) == 1 then
        local repeats = first_data:byte(2) + first_data:byte(3) * 0x100
        return repeats == 0 and 0 or repeats + 1
      end
    elseif marker == 0x2c then
      if offset + 8 > #bytes then return nil, "gif-image" end
      local image_packed = bytes:byte(offset + 8)
      offset = offset + 9
      if bit.band(image_packed, 0x80) ~= 0 then offset = offset + 3 * (2 ^ (bit.band(image_packed, 7) + 1)) end
      if offset > #bytes then return nil, "gif-image" end
      offset = offset + 1
      while true do
        if offset > #bytes then return nil, "gif-image" end
        local size = bytes:byte(offset)
        offset = offset + 1
        if size == 0 then break end
        if offset + size - 1 > #bytes then return nil, "gif-image" end
        offset = offset + size
      end
    else
      return nil, "gif-header"
    end
  end
  return nil, "gif-header"
end

local function gif_control(image)
  local disposal, delay, transparent = 0, ImageDecoder.zero_delay, nil
  for index = 0, tonumber(image.ExtensionBlockCount) - 1 do
    local block = image.ExtensionBlocks[index]
    if tonumber(block.Function) == 0xf9 and tonumber(block.ByteCount) >= 4 then
      local packed = tonumber(block.Bytes[0])
      disposal = bit.band(bit.rshift(packed, 2), 7)
      delay = clamped_delay(tonumber(block.Bytes[1]) + tonumber(block.Bytes[2]) * 0x100, 100)
      if bit.band(packed, 1) ~= 0 then transparent = tonumber(block.Bytes[3]) end
    end
  end
  return disposal, delay, transparent
end

local function gif_row_order(height)
  local rows = {}
  for _, pass in ipairs({ { 0, 8 }, { 4, 8 }, { 2, 4 }, { 1, 2 } }) do
    for row = pass[1], height - 1, pass[2] do rows[#rows + 1] = row end
  end
  return rows
end

local function gif_fail(reason)
  error({ reason = reason }, 0)
end

local function decode_gif(bytes, expected_width, expected_height, options)
  local plays, loop_reason = gif_loop_count(bytes)
  if loop_reason then return nil, loop_reason end
  return Gif.with_file(bytes, function(file)
    local width = tonumber(file.SWidth)
    local height = tonumber(file.SHeight)
    local frame_count = tonumber(file.ImageCount)
    if width ~= expected_width or height ~= expected_height then gif_fail("gif-dimensions") end
    if frame_count < 1 then gif_fail("gif-decode") end
    local frame_bytes = width * height * 4
    local ok, limit_reason = check_animation_limits(options, frame_count, frame_bytes * frame_count)
    if not ok then gif_fail(limit_reason) end
    local canvas = ffi.new("uint8_t[?]", frame_bytes)
    local output = {}
    local previous
    for index = 0, frame_count - 1 do
      local image = file.SavedImages[index]
      local descriptor = image.ImageDesc
      local left = tonumber(descriptor.Left)
      local top = tonumber(descriptor.Top)
      local frame_width = tonumber(descriptor.Width)
      local frame_height = tonumber(descriptor.Height)
      if frame_width < 1 or frame_height < 1 or left < 0 or top < 0 or left + frame_width > width or top + frame_height > height then gif_fail("gif-frame") end
      if previous then
        if previous.disposal == 2 then
          clear_rectangle(canvas, width, previous.left, previous.top, previous.width, previous.height)
        elseif previous.disposal == 3 and previous.canvas then
          ffi.copy(canvas, previous.canvas, frame_bytes)
        end
      end
      local color_map = descriptor.ColorMap ~= nil and descriptor.ColorMap or file.SColorMap
      if color_map == nil or tonumber(color_map.ColorCount) < 1 or tonumber(color_map.ColorCount) > 256 then gif_fail("gif-color-map") end
      local disposal, delay, transparent = gif_control(image)
      local restore = disposal == 3 and copy_frame(canvas, frame_bytes) or nil
      local rows = tonumber(descriptor.Interlace) ~= 0 and gif_row_order(frame_height) or nil
      for source_row = 0, frame_height - 1 do
        local destination_row = rows and rows[source_row + 1] or source_row
        for column = 0, frame_width - 1 do
          local palette_index = tonumber(image.RasterBits[source_row * frame_width + column])
          if palette_index >= tonumber(color_map.ColorCount) then gif_fail("gif-color-index") end
          if palette_index ~= transparent then
            local color = color_map.Colors[palette_index]
            local offset = ((top + destination_row) * width + left + column) * 4
            canvas[offset] = color.Red
            canvas[offset + 1] = color.Green
            canvas[offset + 2] = color.Blue
            canvas[offset + 3] = 255
          end
        end
      end
      output[index + 1] = { duration = delay, pixels = copy_frame(canvas, frame_bytes) }
      previous = { canvas = restore, disposal = disposal, height = frame_height, left = left, top = top, width = frame_width }
    end
    return result("gif", width, height, output, plays or 1)
  end)
end

function ImageDecoder.decode(bytes, expected_width, expected_height, options)
  options = options or {}
  positive_integer(expected_width, "image width")
  positive_integer(expected_height, "image height")
  options.max_animation_bytes = positive_integer(options.max_animation_bytes or ImageDecoder.default_max_animation_bytes, "animation byte limit")
  options.max_frames = positive_integer(options.max_frames or ImageDecoder.default_max_frames, "animation frame limit")
  if bytes:sub(1, 8) == png_signature then
    if has_apng_chunk(bytes) then return parse_apng(bytes, expected_width, expected_height, options) end
    return decode_static_png(bytes, expected_width, expected_height)
  end
  if bytes:sub(1, 6) == "GIF87a" or bytes:sub(1, 6) == "GIF89a" then
    return decode_gif(bytes, expected_width, expected_height, options)
  end
  return nil, "unsupported-media"
end

return ImageDecoder
