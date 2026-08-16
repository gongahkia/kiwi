local Assert = require("tests.assert")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")

local function capture(command)
  local pipe = assert(io.popen(command .. " 2>&1", "r"))
  local output = pipe:read("*a")
  local ok = pipe:close()
  return output, ok == true
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
  end,

  kitty_image_script_rejects_non_https_urls_before_fetching = function()
    local output, ok = capture("TERM=kiwi ./script/kiwi-image http://example.invalid/kiwi.png")
    Assert.truthy(not ok)
    Assert.truthy(output:find("existing PNG file or an HTTPS URL", 1, true) ~= nil)
  end,
}
