local assertions = require("support.assertions")
local Event = require("runtime.event")

return {
  {
    name = "output events preserve arbitrary bytes",
    run = function()
      local event = assert(Event.output("\0\255\n", 42, 7))
      assertions.equal("output", event.kind)
      assertions.equal("\0\255\n", event.data)
      assertions.equal(42, event.delta_us)
      assertions.equal(7, event.source_sequence)
    end,
  },
  {
    name = "event validation normalises event tables without mutating input",
    run = function()
      local input = { kind = "resize", columns = 80, rows = 24, delta_us = 1 }
      local event = assert(Event.validate(input))
      assertions.equal(0, event.pixel_width)
      assertions.equal(0, event.pixel_height)
      assertions.equal(nil, input.pixel_width)
    end,
  },
  {
    name = "event validation rejects malformed external events",
    run = function()
      local event, error_value = Event.validate({ kind = "resize", columns = 0, rows = 24 })
      assertions.falsy(event)
      assertions.equal("backend_protocol_error", error_value.kind)
    end,
  },
}
