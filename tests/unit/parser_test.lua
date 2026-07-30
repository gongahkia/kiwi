local ast = require("src.dsl.ast")
local parser = require("src.dsl.parser")

local function register(test)
  test.case("parser produces an immutable AST for the canonical policy", function()
    local source = [[module FieldPolicy
expose act
act view memory =
  let danger = dangerScore view
  in
  case nearestCasualty view of
    Some ally ->
      if danger < 0.60
      then (memory, moveAndStabilise view ally)
      else (memory, requestCover ally.position)
    None ->
      engageOrAdvance view memory
]]
    local program, diagnostics = parser.parse(source)

    test.equals(#diagnostics, 0)
    test.equals(program.kind, "Program")
    test.equals(program.module.name, "FieldPolicy")
    test.equals(ast.length(program.exposures), 1)
    local exposure = ast.at(program.exposures, 1)
    test.equals(ast.at(exposure.names, 1).name, "act")
    test.equals(ast.length(program.declarations), 1)

    local declaration = ast.at(program.declarations, 1)
    test.equals(declaration.kind, "FunctionDeclaration")
    test.equals(declaration.name.name, "act")
    test.equals(ast.length(declaration.parameters), 2)
    test.equals(declaration.body.kind, "LetExpression")
    test.equals(declaration.body.body.kind, "CaseExpression")
    test.equals(ast.length(declaration.body.body.alternatives), 2)
    test.equals(ast.at(declaration.body.body.alternatives, 1).pattern.kind, "ConstructorPattern")
    test.equals(ast.at(declaration.body.body.alternatives, 1).body.kind, "IfExpression")
    test.equals(declaration.span.start_byte, source:find("act view", 1, true) - 1)
    test.equals(declaration.span.end_byte, #source - 1)

    local node_write_ok = pcall(function()
      declaration.kind = "Mutated"
    end)
    local list_write_ok = pcall(function()
      declaration.parameters[1] = nil
    end)
    local span_write_ok = pcall(function()
      declaration.span.start_byte = -1
    end)
    test.equals(node_write_ok, false)
    test.equals(list_write_ok, false)
    test.equals(span_write_ok, false)
  end)

  test.case("parser preserves record list field and pipeline syntax", function()
    local source = "act view = { destination = view.assignment.destination, plan = [Move view, Wait 5ms] } |> choose"
    local program, diagnostics = parser.parse(source)
    local declaration = ast.at(program.declarations, 1)

    test.equals(#diagnostics, 0)
    test.equals(declaration.body.kind, "PipelineExpression")
    test.equals(declaration.body.input.kind, "RecordExpression")
    test.equals(ast.length(declaration.body.input.fields), 2)
    test.equals(ast.at(declaration.body.input.fields, 1).value.kind, "FieldAccessExpression")
    test.equals(ast.at(declaration.body.input.fields, 2).value.kind, "ListExpression")
    test.equals(ast.length(ast.at(declaration.body.input.fields, 2).value.items), 2)
  end)

  test.case("parser recovers after multiple declaration errors", function()
    local source = [[broken = if true then else 1
good = 2
also_bad = let x = in x
last = 3
]]
    local program, diagnostics = parser.parse(source)

    test.truthy(#diagnostics >= 2)
    test.equals(ast.length(program.declarations), 4)
    test.equals(ast.at(program.declarations, 2).name.name, "good")
    test.equals(ast.at(program.declarations, 4).name.name, "last")
    for _, diagnostic in ipairs(diagnostics) do
      test.equals(type(diagnostic.code), "string")
      test.equals(type(diagnostic.message), "string")
      test.equals(type(diagnostic.span), "table")
      test.equals(type(diagnostic.expected), "table")
    end
  end)

  test.case("parser propagates lexical diagnostics as structured errors", function()
    local _, diagnostics = parser.parse("act = @")

    test.truthy(#diagnostics >= 1)
    test.error_code(diagnostics[1], "unknown_character")
    test.equals(diagnostics[1].span.start_byte, 6)
  end)
end

return register
