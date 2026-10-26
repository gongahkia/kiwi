local ffi = require("ffi")
local Font = require("kiwi.font.system")
local Terminal = require("kiwi.session.terminal")
local PreparedFrame = require("kiwi.renderer.prepared_frame")
local Host = require(os.getenv("KIWI_HOST") == "gtk" and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
local gl = Host.presentation_backend == "gtk-gl"
local window, context, font, renderer, prepared
local ok, message = xpcall(function()
  window = Host.new({ width = 480, height = 240 }, "Kiwi colour glyph readback")
  for _ = 1, 100 do
    local width, height = window:drawable_size()
    if width > 0 and height > 0 then break end
    window:wait_events(0.01)
  end
  if gl then
    assert(window:enable_gl_area_probe())
  else
    context = require("kiwi.gpu.context").new(Host, window, { framebuffer_capture = true })
  end
  font = Font.new({ pixel_height = 23, atlas = { width = 128, height = 128 } })
  local terminal = Terminal.new({ columns = 12, rows = 3 })
  local state = Terminal.state(terminal)
  local rasterize = font.primary.rasterize
  local a, b = font.primary:glyph_index(65), font.primary:glyph_index(66)
  font.primary.rasterize = function(self, id)
    if id ~= a and id ~= b then return rasterize(self, id) end
    local color = id == a
    local pixels = ffi.new("uint8_t[?]", 8 * 8 * (color and 4 or 1))
    for index = 0, 63 do
      if color then pixels[index * 4 + 2], pixels[index * 4 + 3] = 128, 128 else pixels[index] = 128 end
    end
    return { width = 8, height = 8, pitch = color and 32 or 8,
      buffer = pixels, pixel_mode = color and 7 or 2, top = 8, left = 0 }
  end
  terminal:write("\27[?25l\27[48;2;0;0;0m\27[38;2;0;255;0m\27[2JA")
  local compositor
  if gl then prepared = PreparedFrame.new(font, state, { scrollbar_policy = "never" })
  else
    renderer = require("kiwi.renderer.renderer").new(context, font, state, { scrollbar_policy = "never" })
    compositor = require("kiwi.renderer.compositor").new(context)
  end
  local revision = 10
  local function capture(red, green, blue)
    local after = compositor and compositor.frame or 0
    if context then
      context.framebuffer_samples = {}
      assert(context.native.surface.kiwi_framebuffer_capture_set_expected_rgb(context.framebuffer_capture, red, green, blue, 4) ~= 0)
    end
    revision = revision + 1
    local deadline = window:time() + 5
    repeat
      window:poll_events()
      if gl then
        local plan = prepared:prepare_model(state)
        local frame = prepared:prepare_frame(state, window:time(), false, false)
        local snapshot = prepared:complete_snapshot(plan, frame)
        snapshot.revision = revision
        assert(window:submit_gl_area_snapshot(snapshot))
        prepared:commit_model(plan)
      else
        renderer:update_model(state)
        compositor:render({ { renderer = renderer, model = state,
          viewport = { x = 0, y = 0, width = context.width, height = context.height } } }, window:time())
      end
      window:wait_events(0.01)
      if gl then
        local status = assert(window:gl_area_state())
        if status.rendered_revision == revision then return assert(window:gl_area_count_rgb(red, green, blue, 4)) end
      else
        context:poll_framebuffer_capture()
        local sample = context.framebuffer_samples[#context.framebuffer_samples]
        if sample and sample.frame > after then return sample.expected_rgb_pixels end
      end
    until window:time() >= deadline
    error("colour glyph framebuffer readback timed out")
  end
  local half = context and context.surface_is_srgb and 188 or 128
  local red_pixels = capture(half, 0, 0)
  assert(red_pixels > 100, "BGRA swizzle, colour/foreground separation or alpha blending failed: " .. red_pixels)
  terminal:write("\27[2J\27[H\27[8mA")
  assert(capture(half, 0, 0) == 0, "concealed colour glyph remained visible")
  terminal:write("\27[2J\27[H\27[28mB")
  local gray_pixels = capture(0, half, 0)
  assert(gray_pixels > 100, "grayscale coverage changed in the RGBA atlas: " .. gray_pixels)

  terminal:write("\27[2J\27[H\27[38;2;255;0;255m😀😀")
  local face = assert(font:face_for_cluster({ 0x1f600 }))
  local glyph = assert(font.glyph_cache:get_or_insert(face, face:glyph_index(0x1f600)))
  assert(glyph.bitmap.color)
  local counts, best, maximum = {}, nil, 0
  for row = 0, glyph.bitmap.height - 1 do
    for column = 0, glyph.bitmap.width - 1 do
      local pixel = font.glyph_cache.pixels + ((glyph.y + row) * 128 + glyph.x + column) * 4
      if pixel[3] == 255 and math.max(pixel[0], pixel[1], pixel[2]) - math.min(pixel[0], pixel[1], pixel[2]) > 40 then
        local key = pixel[0] * 65536 + pixel[1] * 256 + pixel[2]
        counts[key] = (counts[key] or 0) + 1
        if counts[key] > maximum then best, maximum = { tonumber(pixel[0]), tonumber(pixel[1]), tonumber(pixel[2]) }, counts[key] end
      end
    end
  end
  assert(best, "native emoji font produced no opaque coloured ink")
  local emoji_pixels = capture(unpack(best))
  assert(emoji_pixels >= 8, "native emoji colour did not reach the framebuffer: " .. emoji_pixels)
  print(string.format("Colour glyph GPU smoke passed (%s): red alpha=%d, gray alpha=%d, native emoji=%d pixels; concealment passed; font=%s",
    gl and "GTK GL" or "WGPU", red_pixels, gray_pixels, emoji_pixels, face.family))
end, debug.traceback)
if prepared then prepared:destroy() end
if renderer then renderer:destroy() end
if font then font:destroy() end
if context then context:destroy() end
if window then window:destroy() end
assert(ok, message)
