local assertions = require("support.assertions")
local Rendition = require("terminal.rendition")

return {
  {
    name = "rendition defaults to default colours and no attributes",
    run = function()
      local rendition = assert(Rendition.new())
      assertions.equal(0, rendition.attributes)
      assertions.equal("default", rendition.background)
      assertions.equal("default", rendition.foreground)
    end,
  },
  {
    name = "rendition normalises independent colour values",
    run = function()
      local source = { index = 22, kind = "indexed" }
      local rendition = assert(Rendition.new({
        attributes = 1,
        background = { blue = 30, green = 20, kind = "rgb", red = 10 },
        foreground = source,
      }))
      source.index = 0
      assertions.equal(1, rendition.attributes)
      assertions.equal(30, rendition.background.blue)
      assertions.equal(22, rendition.foreground.index)
    end,
  },
  {
    name = "rendition copy is independent",
    run = function()
      local rendition = assert(Rendition.new({ foreground = { index = 1, kind = "indexed" } }))
      local copy = assert(Rendition.copy(rendition))
      rendition.foreground.index = 2
      assertions.equal(1, copy.foreground.index)
    end,
  },
  {
    name = "rendition rejects invalid fields",
    run = function()
      local invalid_options = {
        { attributes = 4294967296 },
        { background = { kind = "unknown" } },
        { foreground = { index = 2, kind = "indexed", unexpected = true } },
        { unexpected = true },
      }
      for _, options in ipairs(invalid_options) do
        local rendition, error_value = Rendition.new(options)
        assertions.falsy(rendition)
        assertions.equal("config_error", error_value.kind)
      end
    end,
  },
}
