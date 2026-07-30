local assertions = require("support.assertions")
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
      return 0
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
}
