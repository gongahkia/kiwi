local assertions = require("support.assertions")
local Cell = require("terminal.cell")
local Digest = require("terminal.digest")
local Terminal = require("terminal.terminal")

return {
  {
    name = "terminal digest is stable for equal semantic state",
    run = function()
      local first = assert(Terminal.new({ columns = 2, rows = 1, scrollback_limit = 1 }))
      local second = assert(Terminal.new({ columns = 2, rows = 1, scrollback_limit = 1 }))
      first.primary_screen.rows[1]:clear_damage()
      first.primary_screen.rows[1].revision = 10
      assertions.equal(assert(Digest.terminal(second)), assert(Digest.terminal(first)))
      assertions.equal(assert(Digest.terminal(first)), assert(first:digest()))
    end,
  },
  {
    name = "terminal digest changes for semantic screen and scrollback state",
    run = function()
      local terminal = assert(Terminal.new({ columns = 1, rows = 1, scrollback_limit = 1 }))
      local baseline = assert(Digest.terminal(terminal))
      assert(terminal.primary_screen.rows[1]:replace(1, assert(Cell.new({ text = "\0\n" }))))
      local screen_changed = assert(Digest.terminal(terminal))
      assertions.falsy(baseline == screen_changed)
      assertions.truthy(screen_changed:find("000A", 1, true) ~= nil)
      assert(terminal.scrollback:push(terminal.primary_screen.rows[1]))
      assertions.falsy(screen_changed == assert(Digest.terminal(terminal)))
    end,
  },
  {
    name = "terminal digest includes alternate screen semantic state",
    run = function()
      local terminal = assert(Terminal.new({ columns = 1, rows = 1 }))
      local baseline = assert(Digest.terminal(terminal))
      terminal.alternate_screen.rows[1].cells[1].text = "a"
      assertions.falsy(baseline == assert(Digest.terminal(terminal)))
    end,
  },
  {
    name = "terminal digest rejects malformed state",
    run = function()
      local digest, error_value = Digest.terminal({})
      assertions.falsy(digest)
      assertions.equal("internal_invariant_error", error_value.kind)

      local terminal = assert(Terminal.new({ columns = 1, rows = 1 }))
      terminal.primary_screen.rows[1].cells[1] = nil
      digest, error_value = Digest.terminal(terminal)
      assertions.falsy(digest)
      assertions.equal("internal_invariant_error", error_value.kind)
    end,
  },
}
