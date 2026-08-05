local assertions = require("support.assertions")
local Clean = require("effects.clean")
local Host = require("effects.host")
local Terminal = require("terminal.terminal")

return {
  {
    name = "clean effect is an explicit static no-op chain entry",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      local before = assert(terminal:digest())
      local effect = assert(Clean.new())
      assertions.equal(Clean.id, effect:manifest().id)
      local host = assert(Host.new({ effect }))
      assert(host:update(100))
      assert(host:emit("bell", {}, 100))
      assertions.equal(before, assert(terminal:digest()))
      assertions.truthy(host:status().effects[1].enabled)
    end,
  },
}
