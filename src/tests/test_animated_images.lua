local Assert = require("tests.assert")
local Base64 = require("kiwi.terminal.base64")
local KittyGraphics = require("kiwi.terminal.kitty_graphics")

local gif = "R0lGODlhAgACAPAAAP8AAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQAAAAAACwAAAAAAgACAAACAoRRACH5BAAFAAAALAAAAAACAAIAgAAA/wAAAAIChFEAOw=="
local apng = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAAAAAAAAAQCEeRdzAAAACGFjVEwAAAACAAAAAPONk3AAAAAaZmNUTAAAAAAAAAACAAAAAgAAAAAAAAAAAAEAGQAA9jTBKQAAABJJREFUeJxj+MfA+I+BkQFCAQAf5gP97YntFAAAABpmY1RMAAAAAQAAAAIAAAACAAAAAAAAAAAAAQAZAABtRyv9AAAAFmZkQVQAAAACeJxjYGT4x8jwjwFCAQAX/gP9RayewQAAAABJRU5ErkJggg=="
local disposal_gif = "R0lGODlhAwADAPEAAP8AAACAAAAA/wAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQEAAAAACwAAAAAAwADAAACA4R/BQAh+QQEBQAAACwBAAEAAQABAAACAlQBACH5BAQFAAAALAAAAAABAAEAAAICTAEAOw=="

local function transfer(id, width, height, data)
  return string.format("a=t,i=%d,s=%d,v=%d,f=100,t=d,m=0;%s", id, width, height, data)
end

local function apply(cache, id, width, height, data)
  local result = cache:apply(transfer(id, width, height, data))
  Assert.truthy(result.ok, result.reason)
end

return {
  kitty_graphics_decodes_and_schedules_animated_gif_frames = function()
    local cache = KittyGraphics.new()
    apply(cache, 4, 2, 2, gif)
    local image = cache:view().images[1]
    Assert.equal(image.format, "gif")
    Assert.equal(image.frames, 2)
    Assert.equal(image.animated, true)
    Assert.equal(image.bytes, 32)
    Assert.equal(cache:upload_descriptor(4).frame_bytes, 16)

    cache:set_active_images({ [4] = true })
    local delay = cache:animation_delay(10)
    Assert.near(delay, 0.1, 0.0001)
    Assert.truthy(cache:advance(10 + delay))
    local frame = cache:upload_descriptor(4)
    Assert.equal(frame.frame_revision, 2)
    Assert.equal(tonumber(frame.pixels[0]), 0)
    Assert.equal(tonumber(frame.pixels[2]), 255)
    Assert.equal(cache:view().stats.frames_advanced, 1)
  end,
  kitty_graphics_decodes_and_schedules_apng_frames = function()
    local cache = KittyGraphics.new()
    apply(cache, 5, 2, 2, apng)
    local image = cache:view().images[1]
    Assert.equal(image.format, "apng")
    Assert.equal(image.frames, 2)
    Assert.equal(image.plays, 0)

    cache:set_active_images({ [5] = true })
    local delay = cache:animation_delay(20)
    Assert.near(delay, 0.04, 0.0001)
    Assert.truthy(cache:advance(20 + delay))
    local frame = cache:upload_descriptor(5)
    Assert.equal(frame.frame_revision, 2)
    Assert.equal(tonumber(frame.pixels[0]), 1)
    Assert.equal(tonumber(frame.pixels[2]), 254)
  end,
  gif_disposal_background_clears_the_prior_subframe = function()
    local bytes = Base64.decode(disposal_gif)
    local control = assert(bytes:find("\33\249\4\4\5\0\0\0", 1, true))
    bytes = bytes:sub(1, control + 2) .. string.char(8) .. bytes:sub(control + 4)
    local cache = KittyGraphics.new()
    apply(cache, 6, 3, 3, Base64.encode(bytes))
    local image = cache.images[6]
    local third = image.frames[3].pixels
    local middle = (1 * 3 + 1) * 4
    Assert.equal(tonumber(third[middle]), 0)
    Assert.equal(tonumber(third[middle + 1]), 0)
    Assert.equal(tonumber(third[middle + 2]), 0)
    Assert.equal(tonumber(third[middle + 3]), 0)
  end,
  kitty_graphics_rejects_animated_images_at_frame_and_memory_limits = function()
    local frame_limited = KittyGraphics.new({ max_animation_frames = 1 })
    local result = frame_limited:apply(transfer(7, 2, 2, gif))
    Assert.equal(result.ok, false)
    Assert.equal(result.reason, "animation-frame-limit")
    Assert.equal(frame_limited:view().image_count, 0)

    local memory_limited = KittyGraphics.new({ max_animation_bytes = 16 })
    result = memory_limited:apply(transfer(8, 2, 2, apng))
    Assert.equal(result.ok, false)
    Assert.equal(result.reason, "animation-byte-limit")
    Assert.equal(memory_limited:view().image_count, 0)
  end,
}
