local printer = require("src.dsl.ast_printer")
local parser = require("src.dsl.parser")

local function read_fixture(path)
  local file, err = io.open(path, "rb")
  if not file then
    error("cannot open fixture " .. path .. ": " .. tostring(err))
  end
  local contents = file:read("*a")
  file:close()
  return contents
end

local function read_expected(path)
  return (read_fixture(path):gsub("\n$", ""))
end

local function format_diagnostics(diagnostics)
  local lines = {}
  for _, diagnostic in ipairs(diagnostics) do
    lines[#lines + 1] = string.format(
      "%s @%d:%d expected=[%s]",
      diagnostic.code,
      diagnostic.span.start_byte,
      diagnostic.span.end_byte,
      table.concat(diagnostic.expected, ",")
    )
  end
  return table.concat(lines, "\n")
end

local function register(test)
  test.case("parser AST matches the canonical policy golden", function()
    local source = read_fixture("tests/golden/parser/canonical_policy.dsl")
    local expected = read_expected("tests/golden/parser/canonical_policy.ast")
    local program, diagnostics = parser.parse(source)
    local actual, err = printer.format(program)

    test.equals(#diagnostics, 0)
    test.equals(err, nil)
    test.equals(actual, expected)
  end)

  test.case("parser diagnostics match the recovery golden", function()
    local source = read_fixture("tests/golden/parser/recovery.dsl")
    local expected = read_expected("tests/golden/parser/recovery.diagnostics")
    local _, diagnostics = parser.parse(source)

    test.equals(format_diagnostics(diagnostics), expected)
  end)
end

return register
