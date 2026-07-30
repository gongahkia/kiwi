local ast = require("src.dsl.ast")
local printer = require("src.dsl.ast_printer")
local parser = require("src.dsl.parser")

local function register(test)
  test.case("AST printer renders a stable simple tree", function()
    local program, diagnostics = parser.parse("act = 1")
    local output, err = printer.format(program)

    test.equals(#diagnostics, 0)
    test.equals(err, nil)
    test.equals(
      output,
      [[Program @0:7
  module: null
  exposures: []
  declarations:
    - FunctionDeclaration @0:7
      name:
        Identifier name="act" @0:3
      parameters: []
      body:
        IntegerLiteral lexeme="1" @6:7]]
    )
  end)

  test.case("AST printer preserves nested field order deterministically", function()
    local program, diagnostics = parser.parse("act x = { target = x, plan = [Move x] } |> choose")
    local first = printer.format(program)
    local second = printer.format(program)

    test.equals(#diagnostics, 0)
    test.equals(first, second)
    test.truthy(first:find("PipelineExpression", 1, true) ~= nil)
    test.truthy(first:find("RecordExpression", 1, true) ~= nil)
    test.truthy(first:find("ListExpression", 1, true) ~= nil)
  end)

  test.case("AST printer renders parser error nodes", function()
    local program = parser.parse("act = @")
    local output, err = printer.format(program)

    test.equals(err, nil)
    test.truthy(output:find("ErrorExpression @6:7", 1, true) ~= nil)
  end)

  test.case("AST printer reports unsupported input structurally", function()
    local output, err = printer.format({})
    test.equals(output, nil)
    test.error_code(err, "invalid_ast")

    local future = ast.node("FutureNode", {
      start_byte = 0,
      end_byte = 0,
      start_line = 1,
      start_column = 1,
      end_line = 1,
      end_column = 1,
    }, {})
    output, err = printer.format(future)
    test.equals(output, nil)
    test.error_code(err, "unsupported_ast_node")
  end)
end

return register
