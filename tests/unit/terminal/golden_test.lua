local assertions = require("support.assertions")
local cases = require("golden.terminal.cases")
local Snapshot = require("support.terminal_snapshot")
local Terminal = require("terminal.terminal")

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read("*a"))
  assert(file:close())
  return contents
end

local function collect_diagnostics(events, diagnostics)
  for _, event in ipairs(events) do
    if event.kind == "unsupported_sequence" or event.kind == "malformed_sequence" then
      diagnostics[#diagnostics + 1] = event
    end
  end
end

local tests = {}
for _, case in ipairs(cases) do
  tests[#tests + 1] = {
    name = "terminal golden " .. case.name,
    run = function()
      local terminal = assert(Terminal.new(case.config))
      local diagnostics = {}
      for _, chunk in ipairs(case.chunks) do
        local events = assert(terminal:feed_output(chunk))
        collect_diagnostics(events, diagnostics)
      end
      assertions.equal(read_file(case.path), Snapshot.render(terminal, diagnostics), case.name)
    end,
  }
end

return tests
