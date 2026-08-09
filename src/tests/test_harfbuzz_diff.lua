local Assert = require("tests.assert")
local System = require("kiwi.font.system")
local Utf8 = require("kiwi.terminal.utf8")

local function command_exists(command)
  local process = io.popen("command -v " .. command .. " 2>/dev/null")
  if not process then return false end
  local value = process:read("*l")
  process:close()
  return value ~= nil and #value > 0
end

local function oracle(font_path, text)
  local command = string.format("hb-shape --no-glyph-names --utf8-clusters --font-file=%q --font-size=1152 --direction=ltr --features=liga=0,calt=0 %q", font_path, text)
  local process = assert(io.popen(command, "r"), "unable to start hb-shape")
  local output = assert(process:read("*a"), "unable to read hb-shape output")
  assert(process:close(), "hb-shape failed")
  local glyphs = {}
  for item in output:gmatch("[^%[%]|]+") do
    local glyph_id, cluster, rest = item:match("(%d+)=(%d+)(.*)")
    if glyph_id then
      local x_offset, y_offset = rest:match("@([%-]?%d+),([%-]?%d+)")
      local x_advance, y_advance = rest:match("%+([%-]?%d+),([%-]?%d+)")
      x_advance = x_advance or rest:match("%+([%-]?%d+)")
    glyphs[#glyphs + 1] = {
      glyph_id = tonumber(glyph_id),
      cluster = tonumber(cluster),
      x_offset = tonumber(x_offset) or 0,
      y_offset = tonumber(y_offset) or 0,
      x_advance = tonumber(x_advance) or 0,
      y_advance = tonumber(y_advance) or 0,
    }
    end
  end
  return glyphs
end

return {
  harfbuzz_ffi_matches_hb_shape_when_available = function()
    if not command_exists("hb-shape") then return end
    local system = System.new({ pixel_height = 18 })
    local text = "e" .. Utf8.encode(0x0301) .. " -> "
    local actual = system.primary:shape(text, { ligatures = false, contextual_alternates = false })
    local expected = oracle(system.primary.path, text)
    Assert.equal(#actual, #expected)
    for index = 1, #actual do
      for _, field in ipairs({ "glyph_id", "cluster", "x_offset", "y_offset", "x_advance", "y_advance" }) do
        Assert.equal(actual[index][field], expected[index][field], "hb-shape glyph " .. index .. " " .. field)
      end
    end
    system:destroy()
  end,
}
