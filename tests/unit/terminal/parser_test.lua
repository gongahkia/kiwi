local assertions = require("support.assertions")
local Parser = require("terminal.parser")

return {
  {
    name = "parser preserves CSI state across byte chunks",
    run = function()
      local parser = assert(Parser.new())
      local events = assert(parser:feed("A\27[?2"))
      assertions.equal(1, #events)
      assertions.equal("print", events[1].kind)
      assertions.equal(string.byte("A"), events[1].byte)
      assertions.equal("csi_parameter", parser:snapshot().state)
      events = assert(parser:feed("5h"))
      assertions.equal(1, #events)
      assertions.equal("csi", events[1].kind)
      assertions.equal(string.byte("h"), events[1].final)
      assertions.equal("?25", events[1].parameters)
      assertions.equal("", events[1].intermediates)
      assertions.equal("ground", parser:snapshot().state)
      assertions.equal(7, parser:snapshot().byte_offset)
    end,
  },
  {
    name = "parser emits ESC and CSI intermediate dispatches",
    run = function()
      local parser = assert(Parser.new())
      local events = assert(parser:feed("\27 F\27[1 $p"))
      assertions.equal(2, #events)
      assertions.equal("esc", events[1].kind)
      assertions.equal(string.byte("F"), events[1].final)
      assertions.equal(" ", events[1].intermediates)
      assertions.equal("csi", events[2].kind)
      assertions.equal(string.byte("p"), events[2].final)
      assertions.equal("1", events[2].parameters)
      assertions.equal(" $", events[2].intermediates)
    end,
  },
  {
    name = "parser preserves OSC payload across chunks and ST termination",
    run = function()
      local parser = assert(Parser.new())
      assertions.equal(0, #assert(parser:feed("\27]0;title\27")))
      assertions.equal("osc_escape", parser:snapshot().state)
      local events = assert(parser:feed("\\"))
      assertions.equal(1, #events)
      assertions.equal("osc", events[1].kind)
      assertions.equal("0;title", events[1].payload)
      assertions.equal("st", events[1].terminator)
      assertions.equal("ground", parser:snapshot().state)
    end,
  },
  {
    name = "parser executes C0 controls and recovers through CSI ignore",
    run = function()
      local parser = assert(Parser.new())
      local events = assert(parser:feed("\27[12\8H"))
      assertions.equal(2, #events)
      assertions.equal("control", events[1].kind)
      assertions.equal(0x08, events[1].byte)
      assertions.equal("csi", events[2].kind)
      assertions.equal("12", events[2].parameters)

      events = assert(parser:feed("\27[\127"))
      assertions.equal(1, #events)
      assertions.equal("invalid_csi", events[1].reason)
      assertions.equal("csi_ignore", parser:snapshot().state)
      assertions.equal(0, #assert(parser:feed("m")))
      assertions.equal("ground", parser:snapshot().state)
    end,
  },
  {
    name = "parser recovers from cancellation and bounded OSC overflow",
    run = function()
      local parser = assert(Parser.new({ max_osc_bytes = 2 }))
      local events = assert(parser:feed("\27[1\24"))
      assertions.equal(1, #events)
      assertions.equal("malformed", events[1].kind)
      assertions.equal("cancelled", events[1].reason)
      assertions.equal("ground", parser:snapshot().state)

      events = assert(parser:feed("\27]abc"))
      assertions.equal(1, #events)
      assertions.equal("osc_limit", events[1].reason)
      assertions.equal("osc_ignore", parser:snapshot().state)
      assertions.equal(0, #assert(parser:feed("ignored\7")))
      assertions.equal("ground", parser:snapshot().state)
    end,
  },
  {
    name = "parser validates config and input bytes",
    run = function()
      local parser, config_error = Parser.new({ max_csi_bytes = 0 })
      assertions.falsy(parser)
      assertions.equal("config_error", config_error.kind)

      parser = assert(Parser.new())
      local events, input_error = parser:feed(nil)
      assertions.falsy(events)
      assertions.equal("config_error", input_error.kind)
    end,
  },
}
