local assertions = require("support.assertions")
local Standalone = require("app.standalone")

local function graphics()
  local font = require("fixtures.renderer.font").new()
  local printed = {}
  return {
    line = function() end,
    newFont = function()
      return font
    end,
    print = function(text)
      printed[#printed + 1] = text
    end,
    rectangle = function() end,
    setColor = function() end,
    setFont = function() end,
  },
    printed
end

return {
  {
    name = "standalone replays the bundled recording fixture through the renderer",
    run = function()
      local value, printed = graphics()
      local app = assert(Standalone.new(value, {
        padding = 16,
        window_height = 480,
        window_width = 800,
      }))
      assertions.equal(3, #assert(app:update(0)))
      assertions.equal("S", app:terminal_instance().primary_screen.rows[1].cells[1].text)
      assertions.truthy(app:draw())
      assertions.equal("S", printed[1])
      local layout = assert(app:resize(640, 360))
      assertions.equal(layout.columns, app:terminal_instance().config.columns)
      assertions.equal(layout.rows, app:terminal_instance().config.rows)
      assertions.truthy(app:draw())
      assertions.truthy(app:stop())
    end,
  },
}
