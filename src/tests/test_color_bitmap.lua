local ffi = require("ffi")
local Assert = require("tests.assert")
local Bitmap = require("kiwi.font.bitmap")
local Cache = require("kiwi.font.glyph_cache")

local function source()
  return {
    width = 2, height = 2, pitch = 12, pixel_mode = 7, left = 2, top = 4, advance = 6,
    buffer = ffi.new("uint8_t[24]", {
      10, 20, 30, 40, 20, 40, 60, 80, 255, 255, 255, 255,
      30, 60, 90, 120, 40, 80, 120, 160, 255, 255, 255, 255,
    }),
  }
end

return {
  color_bitmap_swizzles_bgra_without_unpremultiplying_or_copying_pitch_padding = function()
    local input = source()
    local bitmap = assert(Bitmap.describe(input, 512))
    local pixels = ffi.new("uint8_t[64]")
    Bitmap.write(input, bitmap, pixels, 4, 1, 1)
    Assert.equal(ffi.string(pixels + 20, 8), string.char(30, 20, 10, 40, 60, 40, 20, 80))
    Assert.equal(ffi.string(pixels + 36, 8), string.char(90, 60, 30, 120, 120, 80, 40, 160))
    Assert.equal(pixels[28], 0)
    Assert.equal(pixels[16], 0)
    Assert.equal(bitmap.color, true)
  end,
  color_bitmap_scales_strikes_and_interpolates_premultiplied_channels = function()
    local input = source()
    input.scale = 0.5
    local bitmap = assert(Bitmap.describe(input, 512))
    Assert.equal(bitmap.width, 1)
    Assert.equal(bitmap.height, 1)
    Assert.equal(bitmap.left, 1)
    Assert.equal(bitmap.top, 2)
    Assert.equal(bitmap.advance, 3)
    local pixels = ffi.new("uint8_t[4]")
    Bitmap.write(input, bitmap, pixels, 1, 0, 0)
    Assert.equal(ffi.string(pixels, 4), string.char(75, 50, 25, 100))
  end,
  grayscale_coverage_survives_the_shared_rgba_atlas = function()
    local input = { width = 2, height = 1, pitch = 3, pixel_mode = 2, buffer = ffi.new("uint8_t[3]", { 64, 192, 255 }) }
    local bitmap = assert(Bitmap.describe(input, 512))
    local pixels = ffi.new("uint8_t[8]")
    Bitmap.write(input, bitmap, pixels, 2, 0, 0)
    Assert.equal(ffi.string(pixels, 8), string.char(64, 0, 0, 64, 192, 0, 0, 192))
    Assert.equal(bitmap.color, false)
  end,
  bitmap_limits_reject_bad_stride_null_data_and_excessive_sizes_before_reading = function()
    for _, change in ipairs({ { pitch = 7 }, { pitch = -12 }, { width = 2049 }, { scale = 300 }, { scale = 0 }, { scale = 0/0 } }) do
      local input = source()
      for key, value in pairs(change) do input[key] = value end
      local bitmap, reason = Bitmap.describe(input, 512)
      Assert.equal(bitmap, nil)
      Assert.equal(reason, "bitmap-limit")
    end
    local input = source()
    input.buffer = nil
    Assert.equal(Bitmap.describe(input, 512), nil)
    input = source(); input.pixel_mode = 5
    local bitmap, reason = Bitmap.describe(input, 512)
    Assert.equal(bitmap, nil)
    Assert.equal(reason, "unsupported-pixel-mode")
  end,
  mixed_color_and_gray_cache_eviction_clears_all_channels_and_retains_live_pixels = function()
    local cache = Cache.new({ width = 8, height = 4, max_entries = 2 })
    local face = { id = 1, pixel_height = 2, rasterize = function(_, id)
      local input = source()
      if id > 2 then input.pixel_mode = 2 end
      return input
    end }
    local owner = {}
    local pinned = assert(cache:get_or_insert(face, 1, owner))
    local pinned_offset = (pinned.y * 8 + pinned.x) * 4
    local before = ffi.string(cache.pixels + pinned_offset, 8)
    local old = assert(cache:get_or_insert(face, 2))
    for id = 3, 100 do
      local glyph = assert(cache:get_or_insert(face, id))
      Assert.equal(glyph.x, old.x)
      Assert.equal(glyph.bitmap.color, false)
      Assert.equal(cache.pixels[(glyph.y * 8 + glyph.x) * 4 + 1], 0)
      Assert.equal(ffi.string(cache.pixels + pinned_offset, 8), before)
    end
    Assert.equal(cache.pixel_bytes, 128)
    Assert.equal(cache.stats.evictions, 98)
  end,
}
