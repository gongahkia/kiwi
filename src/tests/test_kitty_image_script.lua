local Assert = require("tests.assert")
local Base64 = require("kiwi.terminal.base64")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")

local gif = "R0lGODlhAgACAPAAAP8AAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQAAAAAACwAAAAAAgACAAACAoRRACH5BAAFAAAALAAAAAACAAIAgAAA/wAAAAIChFEAOw=="
local apng = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAAAAAAAAAQCEeRdzAAAACGFjVEwAAAACAAAAAPONk3AAAAAaZmNUTAAAAAAAAAACAAAAAgAAAAAAAAAAAAEAGQAA9jTBKQAAABJJREFUeJxj+MfA+I+BkQFCAQAf5gP97YntFAAAABpmY1RMAAAAAQAAAAIAAAACAAAAAAAAAAAAAQAZAABtRyv9AAAAFmZkQVQAAAACeJxjYGT4x8jwjwFCAQAX/gP9RayewQAAAABJRU5ErkJggg=="

local function capture(command)
  local pipe = assert(io.popen(command .. " 2>&1", "r"))
  local output = pipe:read("*a")
  local ok = pipe:close()
  return output, ok == true
end

local function temporary_image(encoded, extension)
  local path = os.tmpname() .. extension
  local handle = assert(io.open(path, "wb"))
  handle:write(Base64.decode(encoded))
  handle:close()
  return path
end

return {
  kitty_image_script_transfers_the_checked_in_png_in_bounded_apc_chunks = function()
    local output, ok = capture("TERM=kiwi ./script/kiwi-image --file assets/kiwi-bird.png --id 7 --placement-id 3 --columns 4 --rows 2 --z -1")
    Assert.truthy(ok)
    local state = State.new(10, 5)
    local parser = Parser.new(state)
    parser:feed(output)
    parser:finish()
    local image = state.kitty_graphics:view().images[1]
    Assert.equal(image.id, 7)
    Assert.equal(image.width, 320)
    Assert.equal(image.height, 320)
    local placement = state:kitty_placements_view().placements[1]
    Assert.equal(placement.placement_id, 3)
    Assert.equal(placement.columns, 4)
    Assert.equal(placement.row_count, 2)
    Assert.equal(placement.z, -1)
    Assert.equal(state.cursor.column, 0)
    Assert.equal(state.cursor.row, 2)
  end,

  kitty_image_script_can_keep_a_composition_fixture_stationary = function()
    local output, ok = capture("TERM=kiwi ./script/kiwi-image --file assets/kiwi-bird.png --columns 4 --rows 2 --no-cursor-advance")
    Assert.truthy(ok)
    local state = State.new(10, 5)
    local parser = Parser.new(state)
    parser:feed(output)
    parser:finish()
    Assert.equal(state.cursor.column, 0)
    Assert.equal(state.cursor.row, 0)
  end,

  kitty_image_script_advances_after_gif_and_apng_files = function()
    for _, fixture in ipairs({ { bytes = gif, extension = ".gif" }, { bytes = apng, extension = ".apng" } }) do
      local path = temporary_image(fixture.bytes, fixture.extension)
      local output, ok = capture(string.format("TERM=kiwi ./script/kiwi-image --file %q --columns 4 --rows 2", path))
      os.remove(path)
      Assert.truthy(ok)
      local state = State.new(10, 5)
      local parser = Parser.new(state)
      parser:feed(output)
      parser:finish()
      Assert.equal(state.kitty_graphics:view().images[1].width, 2)
      Assert.equal(state.kitty_graphics:view().images[1].height, 2)
      Assert.equal(state.cursor.column, 0)
      Assert.equal(state.cursor.row, 2)
    end
  end,

  kitty_image_script_rejects_non_https_urls_before_fetching = function()
    local output, ok = capture("TERM=kiwi ./script/kiwi-image http://example.invalid/kiwi.png")
    Assert.truthy(not ok)
    Assert.truthy(output:find("existing PNG, APNG, or GIF file or an HTTPS URL", 1, true) ~= nil)
  end,
}
