local assertions = require("support.assertions")
local Terminal = require("terminal.terminal")

local fragments = {
  "A",
  "\0",
  "\7",
  "\b",
  "\t",
  "\n",
  "\r",
  "é",
  "\195",
  "\27[2J",
  "\27[2;3H",
  "\27[31m",
  "\27[38;2;1;2;3m",
  "\27[1P",
  "\27[1S",
  "\27" .. "7",
  "\27" .. "8",
  "\27[?1049h",
  "\27[?1049l",
  "\27[999z",
  "\27]0;title\7",
}

local function hex(bytes)
  local encoded = {}
  for index = 1, #bytes do
    encoded[index] = string.format("%02X", bytes:byte(index))
  end
  return table.concat(encoded)
end

local function generated_stream()
  local stream = {}
  local count = math.random(1, 24)
  for index = 1, count do
    stream[index] = fragments[math.random(1, #fragments)]
  end
  return table.concat(stream)
end

local function apply_in_chunks(terminal, bytes)
  local offset = 1
  while offset <= #bytes do
    local size = math.random(1, math.min(7, #bytes - offset + 1))
    assert(terminal:feed_output(bytes:sub(offset, offset + size - 1)))
    offset = offset + size
  end
end

return {
  {
    name = "property terminal digest is invariant under generated chunking",
    run = function()
      for iteration = 1, 128 do
        local bytes = generated_stream()
        local direct = assert(Terminal.new({ columns = 8, rows = 3, scrollback_limit = 4 }))
        local chunked = assert(Terminal.new({ columns = 8, rows = 3, scrollback_limit = 4 }))
        assert(direct:feed_output(bytes))
        apply_in_chunks(chunked, bytes)
        assertions.equal(
          assert(direct:digest()),
          assert(chunked:digest()),
          "chunk property iteration " .. iteration .. " bytes=" .. hex(bytes)
        )
      end
    end,
  },
}
