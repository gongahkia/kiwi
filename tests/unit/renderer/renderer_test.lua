local assertions = require("support.assertions")
local Clean = require("renderer.clean")
local GlyphCache = require("renderer.glyph_cache")
local Grid = require("renderer.grid")
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
  local value = {
    calls = {},
    dpi_scale = 1,
    pixel_height = 27,
    pixel_width = 28,
    window_height = 27,
    window_width = 28,
  }
  local function record(name, ...)
    value.calls[#value.calls + 1] = { name = name, ... }
  end
  function value.newFont(path_or_size, size)
    record("newFont", path_or_size, size)
    return font()
  end
  function value.setColor(red, green, blue, alpha)
    record("setColor", red, green, blue, alpha)
  end
  function value.setFont(selected)
    record("setFont", selected)
  end
  function value.rectangle(mode, x, y, width, height)
    record("rectangle", mode, x, y, width, height)
  end
  function value.print(text, x, y)
    record("print", text, x, y)
  end
  function value.line(x1, y1, x2, y2)
    record("line", x1, y1, x2, y2)
  end
  function value.getDimensions()
    return value.window_width, value.window_height
  end
  function value.getPixelDimensions()
    return value.pixel_width, value.pixel_height
  end
  function value.getDPIScale()
    return value.dpi_scale
  end
  return value
end

local function operation_count(api, name)
  local count = 0
  for _, operation in ipairs(api.calls) do
    if operation.name == name then
      count = count + 1
    end
  end
  return count
end

local function operation(api, name, index)
  local count = 0
  for _, value in ipairs(api.calls) do
    if value.name == name then
      count = count + 1
      if count == index then
        return value
      end
    end
  end
end

local function snapshot()
  return {
    columns = 2,
    rows = 1,
    screen = {
      rows = {
        {
          cells = {
            {
              attributes = 1 + 2 + 8 + 32,
              background = { blue = 6, green = 5, kind = "rgb", red = 4 },
              continuation = false,
              foreground = { blue = 3, green = 2, kind = "rgb", red = 1 },
              text = "A",
              width = 1,
            },
            {
              attributes = 64 + 128,
              background = "default",
              continuation = false,
              foreground = "default",
              text = "B",
              width = 1,
            },
          },
        },
      },
    },
  }
end

local function wide_snapshot()
  local value = snapshot()
  value.columns = 3
  value.screen.rows[1].cells = {
    {
      attributes = 8,
      background = "default",
      continuation = false,
      foreground = "default",
      text = "界",
      width = 2,
    },
    {
      attributes = 0,
      background = "default",
      continuation = true,
      foreground = "default",
      text = "",
      width = 0,
    },
    {
      attributes = 0,
      background = "default",
      continuation = false,
      foreground = "default",
      text = "C",
      width = 1,
    },
  }
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
    name = "renderer defaults to the explicit no-post-processing clean preset",
    run = function()
      local renderer = assert(Renderer.new({}))
      local preset = renderer:preset()
      assertions.equal(Clean.id, preset.id)
      assertions.equal(false, preset.post_processing)
      assertions.equal(0, #preset.effects)
      local unsupported, error_value = Renderer.new({ preset = "stanczyk.crt" })
      assertions.falsy(unsupported)
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
  {
    name = "renderer clean pass draws terminal cell presentation attributes",
    run = function()
      local api = graphics()
      local renderer = assert(Renderer.new({}))
      assert(renderer:load_font(api))
      assertions.truthy(renderer:draw(snapshot()))
      assertions.equal(1, operation_count(api, "setFont"))
      assertions.equal(2, operation_count(api, "rectangle"))
      assertions.equal(3, operation_count(api, "print"))
      assertions.equal(2, operation_count(api, "line"))

      local calls_before = #api.calls
      local value, error_value = renderer:draw({ columns = 1, rows = 1, screen = { rows = {} } })
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      assertions.equal(calls_before, #api.calls)
    end,
  },
  {
    name = "renderer places wide cells once across two terminal columns",
    run = function()
      local api = graphics()
      local renderer = assert(Renderer.new({}))
      assert(renderer:load_font(api))
      local value = wide_snapshot()
      assert(renderer:draw(value))
      assertions.equal(2, operation_count(api, "rectangle"))
      assertions.equal(2, operation_count(api, "print"))
      assertions.equal(1, operation_count(api, "line"))
      local rectangle = operation(api, "rectangle", 1)
      assertions.equal(18, rectangle[4])
      local rectangles_before = operation_count(api, "rectangle")
      assert(renderer:draw(value, { { first_column = 2, last_column = 2, row = 1 } }))
      assertions.equal(rectangles_before + 1, operation_count(api, "rectangle"))
      value.screen.rows[1].cells[2].continuation = false
      local calls_before = #api.calls
      local rendered, render_error = renderer:draw(value)
      assertions.falsy(rendered)
      assertions.equal("config_error", render_error.kind)
      assertions.equal(calls_before, #api.calls)
    end,
  },
  {
    name = "renderer passes combining graphemes to the font unchanged",
    run = function()
      local api = graphics()
      local renderer = assert(Renderer.new({}))
      assert(renderer:load_font(api))
      local value = snapshot()
      value.screen.rows[1].cells[1].text = "é"
      assert(renderer:draw(value))
      assertions.equal("é", operation(api, "print", 1)[1])
    end,
  },
  {
    name = "renderer draws block beam and underline cursors",
    run = function()
      for _, style in ipairs({ "block", "beam", "underline" }) do
        local api = graphics()
        local renderer = assert(Renderer.new({ cursor_style = style }))
        assert(renderer:load_font(api))
        local value = snapshot()
        value.cursor = { column = 2, row = 1 }
        value.cursor_visible = true
        assert(renderer:draw(value))
        assertions.equal(3, operation_count(api, "rectangle"), style)
      end
    end,
  },
  {
    name = "renderer derives a centered grid from integer font metrics",
    run = function()
      local layout =
        assert(Grid.layout({ cell_height = 17, cell_width = 9 }, 28, 27, { padding = 5 }))
      assertions.equal(2, layout.columns)
      assertions.equal(1, layout.rows)
      assertions.equal(18, layout.grid_width)
      assertions.equal(17, layout.grid_height)
      assertions.equal(5, layout.x)
      assertions.equal(5, layout.y)
      local value, error_value = Grid.layout({ cell_height = 17, cell_width = 9 }, -1, 27)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
    end,
  },
  {
    name = "renderer turns window resizes into grid resize events",
    run = function()
      local api = graphics()
      local renderer = assert(Renderer.new({ padding = 5 }))
      assertions.falsy(renderer:resize(28, 27))
      assert(renderer:load_font(api))
      local layout, event = assert(renderer:resize(28, 27))
      assertions.equal(2, layout.columns)
      assertions.equal(1, layout.rows)
      assertions.equal(2, event.columns)
      assertions.equal(1, event.rows)
      assertions.equal(28, event.pixel_width)
      assertions.equal(27, event.pixel_height)
      local rectangles_before = operation_count(api, "rectangle")
      assert(renderer:draw(snapshot(), {}))
      assertions.equal(rectangles_before + 2, operation_count(api, "rectangle"))
      layout, event = assert(renderer:resize(28, 27))
      assertions.equal(nil, event)
      layout, event = assert(renderer:resize(19, 27))
      assertions.equal(1, event.columns)
      local calls_before = #api.calls
      local value, error_value = renderer:draw(snapshot(), {})
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      assertions.equal(calls_before, #api.calls)
    end,
  },
  {
    name = "renderer owns the bootstrap empty canvas draw",
    run = function()
      local api = graphics()
      local renderer = assert(Renderer.new({}))
      assertions.falsy(renderer:draw_empty())
      assert(renderer:load_font(api))
      assert(renderer:resize(28, 27))
      local rectangles_before = operation_count(api, "rectangle")
      assert(renderer:draw_empty())
      assertions.equal(rectangles_before + 1, operation_count(api, "rectangle"))
    end,
  },
  {
    name = "renderer keeps grid units separate from high-DPI event pixels",
    run = function()
      local api = graphics()
      api.dpi_scale = 2
      api.pixel_height = 54
      api.pixel_width = 56
      local renderer = assert(Renderer.new({ padding = 5 }))
      assert(renderer:load_font(api))
      local layout, event = assert(renderer:resize_window())
      assertions.equal(2, layout.columns)
      assertions.equal(1, layout.rows)
      assertions.equal(2, layout.dpi_scale)
      assertions.equal(56, event.pixel_width)
      assertions.equal(54, event.pixel_height)
      api.pixel_width = 84
      layout, event = assert(renderer:resize_window())
      assertions.equal(84, event.pixel_width)
      api.dpi_scale = 0
      local value, error_value = renderer:resize_window()
      assertions.falsy(value)
      assertions.equal("renderer_resource_error", error_value.kind)
    end,
  },
  {
    name = "renderer redraws only validated dirty cell ranges",
    run = function()
      local invalid_renderer, invalid_renderer_error = Renderer.new({ cursor_style = "pipe" })
      assertions.falsy(invalid_renderer)
      assertions.equal("config_error", invalid_renderer_error.kind)
      local api = graphics()
      local renderer = assert(Renderer.new({}))
      assert(renderer:load_font(api))
      assert(renderer:draw(snapshot()))
      local rectangles_before = operation_count(api, "rectangle")
      local prints_before = operation_count(api, "print")
      local lines_before = operation_count(api, "line")
      assert(renderer:draw(snapshot(), { { first_column = 2, last_column = 2, row = 1 } }))
      assertions.equal(rectangles_before + 1, operation_count(api, "rectangle"))
      assertions.equal(prints_before + 1, operation_count(api, "print"))
      assertions.equal(lines_before + 1, operation_count(api, "line"))
      local calls_after = #api.calls
      local value, error_value =
        renderer:draw(snapshot(), { { first_column = 1, last_column = 2, row = 2 } })
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      assertions.equal(calls_after, #api.calls)
      value, error_value =
        renderer:draw(snapshot(), { [2] = { first_column = 1, last_column = 1, row = 1 } })
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      assertions.equal(calls_after, #api.calls)
    end,
  },
  {
    name = "renderer redraws old and new cursor cells from empty damage",
    run = function()
      local api = graphics()
      local renderer = assert(Renderer.new({ cursor_style = "block" }))
      assert(renderer:load_font(api))
      local value = snapshot()
      value.cursor = { column = 1, row = 1 }
      assert(renderer:draw(value))
      local rectangles_before = operation_count(api, "rectangle")
      value.cursor = { column = 2, row = 1 }
      assert(renderer:draw(value, {}))
      assertions.equal(rectangles_before + 3, operation_count(api, "rectangle"))
    end,
  },
}
