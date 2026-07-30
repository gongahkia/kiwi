local assertions = require("support.assertions")
local Screen = require("terminal.screen")

return {
  {
    name = "screen creates an independent fixed-size row grid",
    run = function()
      local screen = assert(Screen.new(3, 2))
      assertions.equal(3, screen.columns)
      assertions.equal(2, screen.height)
      assertions.equal(2, #screen.rows)
      assertions.equal(3, screen.rows[1].columns)
      screen.rows[1].cells[1].text = "x"
      assertions.equal("", screen.rows[2].cells[1].text)
    end,
  },
  {
    name = "screen returns valid rows and clears their damage",
    run = function()
      local screen = assert(Screen.new(2, 2))
      assertions.equal(screen.rows[2], assert(screen:row(2)))
      screen:clear_damage()
      assertions.falsy(screen.rows[1]:dirty_range())
      assertions.falsy(screen.rows[2]:dirty_range())
    end,
  },
  {
    name = "screen rejects invalid dimensions and row indexes",
    run = function()
      local screen, screen_error = Screen.new(2)
      assertions.falsy(screen)
      assertions.equal("config_error", screen_error.kind)

      screen = assert(Screen.new(2, 2))
      local row, row_error = screen:row(3)
      assertions.falsy(row)
      assertions.equal("config_error", row_error.kind)
    end,
  },
}
