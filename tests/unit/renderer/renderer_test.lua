local assertions = require("support.assertions")
local Renderer = require("renderer.renderer")

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
}
