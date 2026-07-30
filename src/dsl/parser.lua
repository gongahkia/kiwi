local ast = require("src.dsl.ast")
local lexer = require("src.dsl.lexer")

local parser = {}

local comparison_operators = {
  ["<"] = true,
  ["<="] = true,
  ["=="] = true,
  ["!="] = true,
  [">"] = true,
  [">="] = true,
}

local addition_operators = {
  ["+"] = true,
  ["-"] = true,
}

local multiplication_operators = {
  ["*"] = true,
  ["/"] = true,
}

local function copy_span(source)
  return {
    start_byte = source.start_byte,
    end_byte = source.end_byte,
    start_line = source.start_line,
    start_column = source.start_column,
    end_line = source.end_line,
    end_column = source.end_column,
  }
end

local function parse_source(source)
  local tokens, lexical_diagnostics = lexer.lex(source)
  local state = { index = 1, diagnostics = {} }

  for _, diagnostic in ipairs(lexical_diagnostics) do
    state.diagnostics[#state.diagnostics + 1] = {
      code = diagnostic.code,
      message = diagnostic.message,
      span = copy_span(diagnostic.span),
      expected = {},
    }
  end

  local function current()
    return tokens[state.index] or tokens[#tokens]
  end

  local function check(kind)
    return current().kind == kind
  end

  local function advance()
    local token = current()
    if token.kind ~= "EOF" then
      state.index = state.index + 1
    end
    return token
  end

  local function add_diagnostic(code, message, expected, token)
    token = token or current()
    state.diagnostics[#state.diagnostics + 1] = {
      code = code,
      message = message,
      span = copy_span(token.span),
      expected = expected or {},
    }
  end

  local function expect(kind, label)
    if check(kind) then
      return advance()
    end
    add_diagnostic(
      "expected_token",
      "expected " .. (label or kind) .. ", found " .. current().kind,
      { kind }
    )
    return nil
  end

  local function make_node(kind, first, last, fields)
    return ast.node(kind, ast.combine_spans(first, last), fields)
  end

  local function make_identifier(token)
    return ast.node("Identifier", token.span, { name = token.lexeme })
  end

  local function make_error_identifier()
    local token = current()
    add_diagnostic(
      "expected_identifier",
      "expected identifier, found " .. token.kind,
      { "LOWER_IDENTIFIER" }
    )
    if token.kind ~= "EOF" then
      advance()
    end
    return ast.node("ErrorIdentifier", token.span, {})
  end

  local function parse_lower_identifier()
    if check("LOWER_IDENTIFIER") then
      return make_identifier(advance())
    end
    return make_error_identifier()
  end

  local function skip_newlines()
    while check("NEWLINE") do
      advance()
    end
  end

  local function expect_after_optional_newlines(kind, label)
    if check(kind) then
      return advance()
    end
    local saved_index = state.index
    skip_newlines()
    if check(kind) then
      return advance()
    end
    state.index = saved_index
    return expect(kind, label)
  end

  local function skip_delimited_layout()
    while check("NEWLINE") or check("INDENT") or check("DEDENT") do
      advance()
    end
  end

  local function is_literal_start(token)
    return token.kind == "INTEGER"
      or token.kind == "FLOAT"
      or token.kind == "QUANTITY"
      or token.kind == "STRING"
      or token.kind == "BOOL"
  end

  local function parse_literal()
    local token = advance()
    if token.kind == "INTEGER" then
      return ast.node("IntegerLiteral", token.span, { lexeme = token.lexeme })
    end
    if token.kind == "FLOAT" then
      return ast.node("FloatLiteral", token.span, { lexeme = token.lexeme })
    end
    if token.kind == "QUANTITY" then
      return ast.node("QuantityLiteral", token.span, { lexeme = token.lexeme, unit = token.unit })
    end
    if token.kind == "STRING" then
      local body = token.lexeme:sub(2, -2)
      local value = body:gsub("\\(.)", function(character)
        if character == "n" then
          return "\n"
        end
        if character == "r" then
          return "\r"
        end
        if character == "t" then
          return "\t"
        end
        return character
      end)
      return ast.node("StringLiteral", token.span, { value = value })
    end
    return ast.node("BoolLiteral", token.span, { value = token.lexeme == "true" })
  end

  local parse_expression
  local parse_pattern

  local function parse_block_expression()
    if check("NEWLINE") then
      skip_newlines()
      if check("INDENT") then
        advance()
        local expression = parse_expression()
        skip_newlines()
        expect("DEDENT", "end of indented expression")
        return expression
      end
    end
    return parse_expression()
  end

  local function parse_parenthesised()
    local start = advance()
    skip_delimited_layout()
    if check("RIGHT_PAREN") then
      local finish = advance()
      return make_node("UnitLiteral", start, finish, {})
    end

    local first = parse_expression()
    skip_delimited_layout()
    if not check("COMMA") then
      local finish = expect("RIGHT_PAREN", "closing parenthesis") or first
      return make_node("GroupExpression", start, finish, { expression = first })
    end

    local items = { first }
    while check("COMMA") do
      advance()
      skip_delimited_layout()
      if check("RIGHT_PAREN") then
        add_diagnostic(
          "expected_expression",
          "tuple requires an expression after comma",
          { "expression" }
        )
        break
      end
      items[#items + 1] = parse_expression()
      skip_delimited_layout()
    end
    local finish = expect("RIGHT_PAREN", "closing parenthesis") or items[#items]
    return make_node("TupleExpression", start, finish, { items = ast.list(items) })
  end

  local function parse_record()
    local start = advance()
    local fields = {}
    skip_delimited_layout()

    while not check("RIGHT_BRACE") and not check("EOF") do
      local field_start = current()
      local name = parse_lower_identifier()
      expect("EQUAL", "equals sign")
      local value = parse_expression()
      fields[#fields + 1] =
        make_node("RecordField", field_start, value, { name = name, value = value })
      skip_delimited_layout()
      if check("COMMA") then
        advance()
        skip_delimited_layout()
      elseif not check("RIGHT_BRACE") then
        add_diagnostic(
          "expected_record_separator",
          "expected comma or closing brace",
          { "COMMA", "RIGHT_BRACE" }
        )
        if not check("EOF") then
          advance()
        end
      end
    end

    local finish = expect("RIGHT_BRACE", "closing brace") or (fields[#fields] or start)
    return make_node("RecordExpression", start, finish, { fields = ast.list(fields) })
  end

  local function parse_list()
    local start = advance()
    local items = {}
    skip_delimited_layout()

    while not check("RIGHT_BRACKET") and not check("EOF") do
      items[#items + 1] = parse_expression()
      skip_delimited_layout()
      if check("COMMA") then
        advance()
        skip_delimited_layout()
      elseif not check("RIGHT_BRACKET") then
        add_diagnostic(
          "expected_list_separator",
          "expected comma or closing bracket",
          { "COMMA", "RIGHT_BRACKET" }
        )
        if not check("EOF") then
          advance()
        end
      end
    end

    local finish = expect("RIGHT_BRACKET", "closing bracket") or (items[#items] or start)
    return make_node("ListExpression", start, finish, { items = ast.list(items) })
  end

  local function parse_primary()
    local token = current()
    if is_literal_start(token) then
      return parse_literal()
    end
    if token.kind == "LOWER_IDENTIFIER" then
      local identifier = make_identifier(advance())
      if identifier.name == "_" then
        add_diagnostic(
          "invalid_expression",
          "wildcard is only valid in patterns",
          { "expression" },
          token
        )
        return ast.node("ErrorExpression", token.span, {})
      end
      return make_node("VariableExpression", identifier, identifier, { name = identifier.name })
    end
    if token.kind == "UPPER_IDENTIFIER" then
      local identifier = make_identifier(advance())
      return make_node("ConstructorExpression", identifier, identifier, { name = identifier.name })
    end
    if token.kind == "LEFT_PAREN" then
      return parse_parenthesised()
    end
    if token.kind == "LEFT_BRACE" then
      return parse_record()
    end
    if token.kind == "LEFT_BRACKET" then
      return parse_list()
    end

    add_diagnostic(
      "expected_expression",
      "expected expression, found " .. token.kind,
      { "expression" }
    )
    if token.kind ~= "EOF" and token.kind ~= "NEWLINE" and token.kind ~= "DEDENT" then
      advance()
    end
    return ast.node("ErrorExpression", token.span, {})
  end

  local function parse_postfix()
    local expression = parse_primary()
    while check("DOT") do
      advance()
      local field = parse_lower_identifier()
      expression = make_node(
        "FieldAccessExpression",
        expression,
        field,
        { target = expression, field = field }
      )
    end
    return expression
  end

  local function is_primary_start(token)
    return is_literal_start(token)
      or token.kind == "LOWER_IDENTIFIER"
      or token.kind == "UPPER_IDENTIFIER"
      or token.kind == "LEFT_PAREN"
      or token.kind == "LEFT_BRACE"
      or token.kind == "LEFT_BRACKET"
  end

  local function parse_application()
    local expression = parse_postfix()
    while is_primary_start(current()) do
      local argument = parse_postfix()
      expression = make_node("ApplicationExpression", expression, argument, {
        callee = expression,
        argument = argument,
      })
    end
    return expression
  end

  local function parse_left_associative(next_expression, operators)
    local expression = next_expression()
    while check("OPERATOR") and operators[current().lexeme] do
      local operator = advance()
      local right = next_expression()
      expression = make_node("BinaryExpression", expression, right, {
        left = expression,
        operator = operator.lexeme,
        right = right,
      })
    end
    return expression
  end

  local function parse_multiplication()
    return parse_left_associative(parse_application, multiplication_operators)
  end

  local function parse_addition()
    return parse_left_associative(parse_multiplication, addition_operators)
  end

  local function parse_comparison()
    return parse_left_associative(parse_addition, comparison_operators)
  end

  local function parse_pipeline()
    local expression = parse_comparison()
    while check("PIPE") do
      advance()
      local stage = parse_comparison()
      expression =
        make_node("PipelineExpression", expression, stage, { input = expression, stage = stage })
    end
    return expression
  end

  local function parse_if()
    local start = advance()
    local condition = parse_expression()
    local then_token = expect_after_optional_newlines("KW_THEN", "then")
    local then_branch = then_token and parse_block_expression()
      or ast.node("ErrorExpression", current().span, {})
    local else_token = expect_after_optional_newlines("KW_ELSE", "else")
    local else_branch = else_token and parse_block_expression()
      or ast.node("ErrorExpression", current().span, {})
    return make_node("IfExpression", start, else_branch, {
      condition = condition,
      then_branch = then_branch,
      else_branch = else_branch,
    })
  end

  local function parse_let()
    local start = advance()
    local name = parse_lower_identifier()
    expect("EQUAL", "equals sign")
    local value = parse_block_expression()
    local in_token = expect_after_optional_newlines("KW_IN", "in")
    local body = in_token and parse_block_expression()
      or ast.node("ErrorExpression", current().span, {})
    return make_node("LetExpression", start, body, { name = name, value = value, body = body })
  end

  local function is_pattern_start(token)
    return token.kind == "LOWER_IDENTIFIER"
      or token.kind == "UPPER_IDENTIFIER"
      or token.kind == "LEFT_PAREN"
      or token.kind == "LEFT_BRACKET"
      or is_literal_start(token)
  end

  local function parse_pattern_parenthesised()
    local start = advance()
    local first = parse_pattern()
    expect("COMMA", "tuple pattern comma")
    local items = { first }
    while true do
      items[#items + 1] = parse_pattern()
      if not check("COMMA") then
        break
      end
      advance()
    end
    local finish = expect("RIGHT_PAREN", "closing parenthesis") or items[#items]
    return make_node("TuplePattern", start, finish, { items = ast.list(items) })
  end

  local function parse_pattern_list()
    local start = advance()
    local items = {}
    while not check("RIGHT_BRACKET") and not check("EOF") do
      items[#items + 1] = parse_pattern()
      if check("COMMA") then
        advance()
      elseif not check("RIGHT_BRACKET") then
        add_diagnostic(
          "expected_list_separator",
          "expected comma or closing bracket",
          { "COMMA", "RIGHT_BRACKET" }
        )
        break
      end
    end
    local finish = expect("RIGHT_BRACKET", "closing bracket") or (items[#items] or start)
    return make_node("ListPattern", start, finish, { items = ast.list(items) })
  end

  parse_pattern = function()
    local token = current()
    if token.kind == "LOWER_IDENTIFIER" then
      advance()
      if token.lexeme == "_" then
        return ast.node("WildcardPattern", token.span, {})
      end
      return ast.node("VariablePattern", token.span, { name = token.lexeme })
    end
    if token.kind == "UPPER_IDENTIFIER" then
      local start = advance()
      local arguments = {}
      while is_pattern_start(current()) do
        arguments[#arguments + 1] = parse_pattern()
      end
      local finish = arguments[#arguments] or start
      return make_node(
        "ConstructorPattern",
        start,
        finish,
        { name = start.lexeme, arguments = ast.list(arguments) }
      )
    end
    if is_literal_start(token) then
      local literal = parse_literal()
      return make_node("LiteralPattern", literal, literal, { literal = literal })
    end
    if token.kind == "LEFT_PAREN" then
      return parse_pattern_parenthesised()
    end
    if token.kind == "LEFT_BRACKET" then
      return parse_pattern_list()
    end

    add_diagnostic("expected_pattern", "expected pattern, found " .. token.kind, { "pattern" })
    if token.kind ~= "EOF" and token.kind ~= "NEWLINE" and token.kind ~= "DEDENT" then
      advance()
    end
    return ast.node("ErrorPattern", token.span, {})
  end

  local function parse_case_alternative()
    local pattern = parse_pattern()
    expect("ARROW", "case arrow")
    local body = parse_block_expression()
    return make_node("CaseAlternative", pattern, body, { pattern = pattern, body = body })
  end

  local function parse_case()
    local start = advance()
    local subject = parse_expression()
    expect("KW_OF", "of")
    if check("NEWLINE") then
      skip_newlines()
    else
      add_diagnostic("expected_token", "expected newline after of", { "NEWLINE" })
    end
    expect("INDENT", "indented case alternatives")

    local alternatives = {}
    while not check("DEDENT") and not check("EOF") do
      if check("NEWLINE") then
        advance()
      else
        alternatives[#alternatives + 1] = parse_case_alternative()
      end
    end
    if #alternatives == 0 then
      add_diagnostic(
        "expected_case_alternative",
        "case expression requires an alternative",
        { "pattern" }
      )
    end
    expect("DEDENT", "end of case alternatives")
    local finish = alternatives[#alternatives] or subject
    return make_node("CaseExpression", start, finish, {
      subject = subject,
      alternatives = ast.list(alternatives),
    })
  end

  parse_expression = function()
    if check("KW_LET") then
      return parse_let()
    end
    if check("KW_IF") then
      return parse_if()
    end
    if check("KW_CASE") then
      return parse_case()
    end
    return parse_pipeline()
  end

  local function parse_module()
    local start = advance()
    local name_token
    if check("UPPER_IDENTIFIER") then
      name_token = advance()
    else
      add_diagnostic(
        "expected_module_name",
        "expected module name, found " .. current().kind,
        { "UPPER_IDENTIFIER" }
      )
      name_token = current()
      if name_token.kind ~= "EOF" then
        advance()
      end
    end
    return make_node("ModuleDeclaration", start, name_token, { name = name_token.lexeme })
  end

  local function parse_expose()
    local start = advance()
    local names = { parse_lower_identifier() }
    while check("COMMA") do
      advance()
      names[#names + 1] = parse_lower_identifier()
    end
    return make_node("ExposeDeclaration", start, names[#names], { names = ast.list(names) })
  end

  local function parse_declaration()
    local name = parse_lower_identifier()
    local parameters = {}
    while check("LOWER_IDENTIFIER") do
      parameters[#parameters + 1] = parse_lower_identifier()
    end
    expect("EQUAL", "equals sign")
    local body = parse_block_expression()
    return make_node("FunctionDeclaration", name, body, {
      name = name,
      parameters = ast.list(parameters),
      body = body,
    })
  end

  local function synchronize_declaration()
    while not check("EOF") and not check("NEWLINE") do
      advance()
    end
    skip_newlines()
    while check("DEDENT") do
      advance()
    end
  end

  skip_newlines()
  local module_declaration
  local exposures = {}
  local declarations = {}
  local first
  local last

  if check("KW_MODULE") then
    module_declaration = parse_module()
    first = module_declaration
    last = module_declaration
    skip_newlines()
  end

  while check("KW_EXPOSE") do
    local exposure = parse_expose()
    exposures[#exposures + 1] = exposure
    first = first or exposure
    last = exposure
    skip_newlines()
  end

  while not check("EOF") do
    if check("NEWLINE") then
      advance()
    elseif check("LOWER_IDENTIFIER") then
      local declaration = parse_declaration()
      declarations[#declarations + 1] = declaration
      first = first or declaration
      last = declaration
    else
      add_diagnostic(
        "expected_declaration",
        "expected function declaration, found " .. current().kind,
        { "LOWER_IDENTIFIER" }
      )
      synchronize_declaration()
    end
  end

  local eof = current()
  first = first or eof
  last = last or eof
  return make_node("Program", first, last, {
    module = module_declaration,
    exposures = ast.list(exposures),
    declarations = ast.list(declarations),
  }),
    state.diagnostics
end

function parser.parse(source)
  local ok, program, diagnostics = pcall(parse_source, source)
  if ok then
    return program, diagnostics
  end
  return nil,
    {
      {
        code = "parser_internal_error",
        message = "parser failed safely: " .. tostring(program),
        span = {
          start_byte = 0,
          end_byte = 0,
          start_line = 1,
          start_column = 1,
          end_line = 1,
          end_column = 1,
        },
        expected = {},
      },
    }
end

return parser
