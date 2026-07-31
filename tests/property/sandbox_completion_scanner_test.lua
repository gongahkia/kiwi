local assertions = require("support.assertions")
local Scanner = require("shell.completion_scanner")

local bytes = { "a", "Z", " ", "\t", "'", '"', "\\", "\0", "\255" }

local function encode_argument(argument)
  return '"' .. argument:gsub('[\\"]', "\\%0") .. '"'
end

local function generated_line()
  local arguments = {}
  for index = 1, math.random(0, 8) do
    local argument = {}
    for byte_index = 1, math.random(0, 12) do
      argument[byte_index] = bytes[math.random(1, #bytes)]
    end
    arguments[index] = encode_argument(table.concat(argument))
  end
  return table.concat(arguments, " ")
end

return {
  {
    name = "property generated completion scans preserve bounded cursor invariants",
    run = function()
      for iteration = 1, 256 do
        local line = generated_line()
        local scan = assert(Scanner.scan(line, math.random(0, #line)))
        assertions.truthy(scan.active_start <= scan.cursor_offset, "start iteration " .. iteration)
        assertions.truthy(scan.cursor_offset <= #line, "cursor iteration " .. iteration)
        assertions.truthy(scan.argument_index >= 1, "argument iteration " .. iteration)
        assertions.truthy(#scan.active_prefix <= 4096, "prefix iteration " .. iteration)
      end
    end,
  },
  {
    name = "property generated incomplete completion grammar never requires dispatch",
    run = function()
      for iteration = 1, 256 do
        local line = generated_line() .. ({ "'", '"', "\\" })[math.random(1, 3)]
        local scan, scan_error = Scanner.scan(line, #line)
        assertions.falsy(scan_error, "error iteration " .. iteration)
        assertions.truthy(scan, "scan iteration " .. iteration)
      end
    end,
  },
}
