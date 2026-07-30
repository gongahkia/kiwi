local assertions = require("support.assertions")
local Cursor = require("terminal.cursor")

return {
  {
    name = "cursor defaults to the first cell without pending wrap",
    run = function()
      local cursor = assert(Cursor.new())
      assertions.equal(1, cursor.column)
      assertions.falsy(cursor.pending_wrap)
      assertions.equal(1, cursor.row)
    end,
  },
  {
    name = "cursor copies position independently",
    run = function()
      local cursor = assert(Cursor.new({ column = 3, pending_wrap = true, row = 2 }))
      local copy = assert(Cursor.copy(cursor))
      cursor.column = 1
      assertions.equal(3, copy.column)
      assertions.truthy(copy.pending_wrap)
      assertions.equal(2, copy.row)
    end,
  },
  {
    name = "cursor rejects invalid fields",
    run = function()
      local invalid_options = {
        { column = 0 },
        { pending_wrap = "yes" },
        { row = 1.5 },
        { unexpected = true },
      }
      for _, options in ipairs(invalid_options) do
        local cursor, error_value = Cursor.new(options)
        assertions.falsy(cursor)
        assertions.equal("config_error", error_value.kind)
      end
    end,
  },
}
