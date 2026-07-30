local assertions = require("support.assertions")
local Cell = require("terminal.cell")

return {
  {
    name = "cell creates a blank single-width default-rendition cell",
    run = function()
      local cell = assert(Cell.new())
      assertions.equal(0, cell.attributes)
      assertions.equal("default", cell.background)
      assertions.falsy(cell.continuation)
      assertions.equal("default", cell.foreground)
      assertions.falsy(cell.hyperlink_id)
      assertions.equal("", cell.text)
      assertions.equal(1, cell.width)
    end,
  },
  {
    name = "cell preserves wide glyph semantics and colour rendition",
    run = function()
      local foreground = { index = 196, kind = "indexed" }
      local cell = assert(Cell.new({
        attributes = 3,
        background = { blue = 12, green = 34, kind = "rgb", red = 56 },
        foreground = foreground,
        text = "界",
        width = 2,
      }))
      foreground.index = 1
      assertions.equal(3, cell.attributes)
      assertions.equal(12, cell.background.blue)
      assertions.equal(34, cell.background.green)
      assertions.equal("rgb", cell.background.kind)
      assertions.equal(56, cell.background.red)
      assertions.equal(196, cell.foreground.index)
      assertions.equal("indexed", cell.foreground.kind)
      assertions.falsy(cell.continuation)
      assertions.equal("界", cell.text)
      assertions.equal(2, cell.width)
    end,
  },
  {
    name = "cell creates an empty continuation for a wide glyph",
    run = function()
      local cell = assert(Cell.new({ continuation = true, width = 0 }))
      assertions.truthy(cell.continuation)
      assertions.equal("", cell.text)
      assertions.equal(0, cell.width)
    end,
  },
  {
    name = "cell rejects invalid semantic fields",
    run = function()
      local invalid_options = {
        { attributes = -1 },
        { background = { kind = "indexed", index = 256 } },
        { continuation = true, text = "x", width = 0 },
        { continuation = false, width = 0 },
        { continuation = true, width = 1 },
        { foreground = { kind = "rgb", red = 0, green = 0 } },
        { foreground = { index = 1, kind = "indexed", unexpected = true } },
        { hyperlink_id = "future" },
        { text = false },
        { width = 3 },
      }
      for _, options in ipairs(invalid_options) do
        local cell, error_value = Cell.new(options)
        assertions.falsy(cell)
        assertions.equal("config_error", error_value.kind)
      end
    end,
  },
}
