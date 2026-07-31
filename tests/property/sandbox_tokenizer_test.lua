local assertions = require("support.assertions")
local Dispatcher = require("shell.dispatcher")
local Tokenizer = require("shell.tokenizer")

local bytes = {
  "a",
  "Z",
  "0",
  " ",
  "\t",
  "'",
  '"',
  "\\",
  "$",
  "*",
  "?",
  "|",
  ">",
  "<",
  ";",
  "&",
  "#",
  "(",
  ")",
  "`",
  string.char(0),
  string.char(128),
  string.char(255),
}

local function generated_argv()
  local argv = {}
  for index = 1, math.random(0, 8) do
    local argument = {}
    for byte_index = 1, math.random(0, 16) do
      argument[byte_index] = bytes[math.random(1, #bytes)]
    end
    argv[index] = table.concat(argument)
  end
  return argv
end

local function encode_argument(argument)
  if argument == "" then
    return '""'
  end
  return '"' .. argument:gsub('[\\"]', "\\%0") .. '"'
end

local function encode(argv)
  local encoded = {}
  for index, argument in ipairs(argv) do
    encoded[index] = encode_argument(argument)
  end
  return table.concat(encoded, " ")
end

local function assert_equal_argv(expected, actual, message)
  assertions.equal(#expected, #actual, message)
  for index, argument in ipairs(expected) do
    assertions.equal(argument, actual[index], message .. " argument " .. index)
  end
end

return {
  {
    name = "property generated sandbox argv round trips through the canonical byte encoder",
    run = function()
      for iteration = 1, 256 do
        local expected = generated_argv()
        local actual = assert(Tokenizer.tokenize(encode(expected)))
        assert_equal_argv(expected, actual, "round-trip iteration " .. iteration)
      end
    end,
  },
  {
    name = "property generated malformed sandbox commands never dispatch or return partial argv",
    run = function()
      for iteration = 1, 256 do
        local valid = encode(generated_argv())
        local malformed = valid .. ({ "'", '"', "\\" })[math.random(1, 3)]
        local argv, token_error = Tokenizer.tokenize(malformed)
        assertions.falsy(argv, "tokenizer iteration " .. iteration)
        assertions.equal("sandbox_command_error", token_error.kind)
        local lookups = 0
        local dispatcher = assert(Dispatcher.new({
          command = function()
            lookups = lookups + 1
          end,
        }))
        local outcome, dispatch_error = dispatcher:dispatch(malformed)
        assertions.falsy(outcome, "dispatcher iteration " .. iteration)
        assertions.equal("sandbox_command_error", dispatch_error.kind)
        assertions.equal(0, lookups, "lookup iteration " .. iteration)
      end
    end,
  },
}
