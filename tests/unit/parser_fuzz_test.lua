local printer = require("src.dsl.ast_printer")
local parser = require("src.dsl.parser")
local prng = require("src.util.prng")

local fragments = {
  "act",
  "view",
  "Some",
  "None",
  "=",
  "->",
  "|>",
  "if",
  "then",
  "else",
  "let",
  "in",
  "case",
  "of",
  "{",
  "}",
  "[",
  "]",
  "(",
  ")",
  ",",
  ".",
  "<",
  "0.25",
  "5ms",
  '"',
  "\\q",
  "--",
  "\n",
  "  ",
  "\t",
  "\r",
  "@",
  "\0",
  "\255",
}

local function format_diagnostics(diagnostics)
  local lines = {}
  for _, diagnostic in ipairs(diagnostics) do
    lines[#lines + 1] = table.concat({
      diagnostic.code,
      diagnostic.message,
      diagnostic.span.start_byte,
      diagnostic.span.end_byte,
      table.concat(diagnostic.expected, ","),
    }, "|")
  end
  return table.concat(lines, "\n")
end

local function next_source(rng)
  local parts = {}
  local length = 0
  local target_length = assert(rng:next_int(0, 128))
  while length < target_length do
    local index = assert(rng:next_int(1, #fragments))
    local fragment = fragments[index]
    if length + #fragment > target_length then
      fragment = fragment:sub(1, target_length - length)
    end
    parts[#parts + 1] = fragment
    length = length + #fragment
  end
  return table.concat(parts)
end

local function register(test)
  test.case("parser fuzzes bounded malformed input deterministically", function()
    local rng = assert(prng.new(13371337)):fork("parser_malformed_input")

    for _ = 1, 256 do
      local source = next_source(rng)
      local first_program, first_diagnostics = parser.parse(source)
      local second_program, second_diagnostics = parser.parse(source)
      local first_output, first_error = printer.format(first_program)
      local second_output, second_error = printer.format(second_program)

      test.truthy(first_program)
      test.truthy(second_program)
      test.equals(first_program.kind, "Program")
      test.equals(second_program.kind, "Program")
      test.equals(first_error, nil)
      test.equals(second_error, nil)
      test.equals(first_output, second_output)
      test.equals(format_diagnostics(first_diagnostics), format_diagnostics(second_diagnostics))
      test.truthy(#first_diagnostics <= 512)
      for _, diagnostic in ipairs(first_diagnostics) do
        test.truthy(diagnostic.code ~= "parser_internal_error")
        test.equals(type(diagnostic.span), "table")
        test.equals(type(diagnostic.expected), "table")
      end
    end
  end)
end

return register
