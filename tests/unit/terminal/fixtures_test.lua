local Terminal = require("terminal.terminal")
local fixtures = require("fixtures.terminal.supported_sequences")

local cases = {}
for _, fixture in ipairs(fixtures) do
  cases[#cases + 1] = {
    name = "terminal fixture " .. fixture.name,
    run = function()
      local terminal = assert(Terminal.new(fixture.config))
      if fixture.setup then
        fixture.setup(terminal)
      end
      local events, parser_events = assert(terminal:feed_output(fixture.bytes))
      fixture.verify(terminal, events, parser_events)
    end,
  }
end

return cases
