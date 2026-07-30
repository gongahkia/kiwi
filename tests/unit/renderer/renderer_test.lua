local assertions = require("support.assertions")
local GlyphCache = require("renderer.glyph_cache")
local LoveFont = require("renderer.love_font")
local Metrics = require("renderer.metrics")
local Renderer = require("renderer.renderer")

local function font()
  return {
    getAscent = function()
      return 12.8
    end,
    getHeight = function()
      return 16.2
    end,
    getWidth = function(_, text)
      if text == "M" then
        return 8.2
      end
      if text == "A" then
        return 7
      end
      if text == "é" then
        return 9
      end
      return #text
    end,
  }
end

local function graphics()
  local value = { calls = {} }
  function value.newFont(path_or_size, size)
    value.calls[#value.calls + 1] = { path_or_size, size }
    return font()
  end
  return value
end

return {
  {
    name = "renderer bootstrap rejects absent snapshot",
    run = function()
      local renderer = assert(Renderer.new({}))
      local value, error_value = renderer:draw(nil)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
    end,
  },
  {
    name = "renderer metrics derive explicit integer cell geometry",
    run = function()
      local value = assert(Metrics.new(font()))
      assertions.equal(12, value.baseline)
      assertions.equal(17, value.cell_height)
      assertions.equal(9, value.cell_width)
      value = assert(Metrics.new(font(), { baseline = 10, cell_height = 20, cell_width = 11 }))
      assertions.equal(10, value.baseline)
      assertions.equal(20, value.cell_height)
      assertions.equal(11, value.cell_width)
      local metrics, error_value = Metrics.new(font(), { cell_height = 8 })
      assertions.falsy(metrics)
      assertions.equal("config_error", error_value.kind)
    end,
  },
  {
    name = "renderer loads fonts through an injected graphics boundary",
    run = function()
      local api = graphics()
      local resource = assert(LoveFont.load(api, {
        cell_height = 19,
        cell_width = 10,
        font_path = "fixtures/mono.ttf",
        font_size = 15,
      }))
      assertions.equal("fixtures/mono.ttf", api.calls[1][1])
      assertions.equal(15, api.calls[1][2])
      assertions.equal(19, resource.metrics.cell_height)
      assertions.equal(10, resource.metrics.cell_width)

      local renderer = assert(Renderer.new({ font_size = 13 }))
      local metrics = assert(renderer:load_font(api))
      assertions.equal(17, metrics.cell_height)
      assertions.equal(9, metrics.cell_width)
      assertions.equal(metrics.cell_width, assert(renderer:cell_metrics()).cell_width)
    end,
  },
  {
    name = "renderer glyph cache expands lazily across ASCII and Unicode",
    run = function()
      local cache = assert(GlyphCache.new(font(), {
        baseline = 12,
        cell_height = 17,
        cell_width = 9,
      }, { max_entries = 2 }))
      local ascii = assert(cache:get("A"))
      assertions.equal(7, ascii.advance)
      local unicode = assert(cache:get("é", "bold"))
      assertions.equal(9, unicode.advance)
      assertions.equal("bold", unicode.style)
      assertions.equal(2, cache:stats().entries)
      assert(cache:get("A"))
      assert(cache:get("B"))
      assertions.equal(2, cache:stats().entries)
      assertions.equal(1, cache:stats().hits)
      assertions.equal(3, cache:stats().misses)

      local renderer = assert(Renderer.new({ max_glyph_entries = 2 }))
      assertions.falsy(renderer:glyph("A"))
      assert(renderer:load_font(graphics()))
      assertions.equal(7, assert(renderer:glyph("A")).advance)
    end,
  },
}
