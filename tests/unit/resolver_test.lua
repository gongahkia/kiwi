local ast = require("src.dsl.ast")
local parser = require("src.dsl.parser")
local resolver = require("src.dsl.resolver")

local function declaration(program, index)
  return ast.at(program.declarations, index)
end

local function register(test)
  test.case("resolver binds declarations and nested lexical scopes", function()
    local source = [[module FieldPolicy
expose act
helper value = value
act view =
  let value = helper view
  in
  case Some value of
    Some value -> value
    None -> view
]]
    local program, parse_diagnostics = parser.parse(source)
    local resolution, diagnostics = resolver.resolve(program)
    local helper = declaration(program, 1)
    local act = declaration(program, 2)
    local let_expression = act.body
    local case_expression = let_expression.body
    local some_alternative = ast.at(case_expression.alternatives, 1)
    local none_alternative = ast.at(case_expression.alternatives, 2)
    local helper_application = let_expression.value

    test.equals(#parse_diagnostics, 0)
    test.equals(#diagnostics, 0)
    test.equals(resolution.program, program)
    test.equals(resolver.binding_for(resolution, helper).kind, "function")
    test.equals(resolver.binding_for(resolution, helper_application.callee), resolver.binding_for(resolution, helper))
    test.equals(
      resolver.binding_for(resolution, helper_application.argument),
      resolver.binding_for(resolution, act.parameters[1])
    )
    test.equals(resolver.binding_for(resolution, let_expression.name).kind, "let")
    test.equals(
      resolver.binding_for(resolution, case_expression.subject.argument),
      resolver.binding_for(resolution, let_expression.name)
    )
    test.equals(resolver.binding_for(resolution, case_expression.subject.callee).kind, "constructor")
    test.equals(resolver.binding_for(resolution, some_alternative.pattern.arguments[1]).kind, "pattern")
    test.equals(
      resolver.binding_for(resolution, some_alternative.body),
      resolver.binding_for(resolution, some_alternative.pattern.arguments[1])
    )
    test.equals(
      resolver.binding_for(resolution, none_alternative.body),
      resolver.binding_for(resolution, act.parameters[1])
    )
    test.truthy(resolver.binding_for(resolution, some_alternative.body).id ~= resolver.binding_for(resolution, let_expression.name).id)
  end)

  test.case("resolver resolves forward declarations and configured values", function()
    local program, parse_diagnostics = parser.parse([[act input = choose later input
later value = external value
]])
    local resolution, diagnostics = resolver.resolve(program, { values = { "choose", "external" } })
    local act = declaration(program, 1)
    local later = declaration(program, 2)
    local choose = act.body.callee.callee
    local later_reference = act.body.callee.argument
    local external = later.body.callee

    test.equals(#parse_diagnostics, 0)
    test.equals(#diagnostics, 0)
    test.equals(resolver.binding_for(resolution, later_reference), resolver.binding_for(resolution, later))
    test.equals(resolver.binding_for(resolution, choose).kind, "value")
    test.equals(resolver.binding_for(resolution, external).kind, "value")
  end)

  test.case("resolver reports duplicate bindings and unresolved names with source spans", function()
    local source = [[expose absent, act, act
act value value = missing value
act = Unknown
]]
    local program, parse_diagnostics = parser.parse(source)
    local _, diagnostics = resolver.resolve(program)

    test.equals(#parse_diagnostics, 0)
    test.equals(#diagnostics, 5)
    test.error_code(diagnostics[1], "unknown_exposed_name")
    test.error_code(diagnostics[2], "duplicate_exposed_name")
    test.error_code(diagnostics[3], "duplicate_binding")
    test.error_code(diagnostics[4], "duplicate_binding")
    test.error_code(diagnostics[5], "unresolved_value_name")
    test.equals(diagnostics[1].span.start_byte, source:find("absent", 1, true) - 1)
    test.equals(diagnostics[5].span.start_byte, source:find("missing", 1, true) - 1)
  end)

  test.case("resolver creates isolated bindings for case alternatives", function()
    local program, parse_diagnostics = parser.parse([[act input =
  case input of
    Some value -> value
    Some value -> value
]])
    local resolution, diagnostics = resolver.resolve(program)
    local alternatives = declaration(program, 1).body.alternatives
    local first = ast.at(alternatives, 1)
    local second = ast.at(alternatives, 2)

    test.equals(#parse_diagnostics, 0)
    test.equals(#diagnostics, 0)
    test.truthy(resolver.binding_for(resolution, first.pattern.arguments[1]).id ~= resolver.binding_for(resolution, second.pattern.arguments[1]).id)
    test.equals(resolver.binding_for(resolution, first.body), resolver.binding_for(resolution, first.pattern.arguments[1]))
    test.equals(resolver.binding_for(resolution, second.body), resolver.binding_for(resolution, second.pattern.arguments[1]))
  end)

  test.case("resolver rejects invalid programs and external name lists structurally", function()
    local resolution, diagnostics = resolver.resolve({}, { values = { "valid", 3 } })

    test.equals(resolution, nil)
    test.equals(#diagnostics, 1)
    test.error_code(diagnostics[1], "invalid_program")

    local program = assert(parser.parse("act = external"))
    resolution, diagnostics = resolver.resolve(program, { values = { "external", 3 } })
    test.equals(resolution, nil)
    test.equals(#diagnostics, 1)
    test.error_code(diagnostics[1], "invalid_resolver_options")
  end)
end

return register
