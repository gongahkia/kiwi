local lexer = require("src.dsl.lexer")

local function register(test)
  local function token_kinds(tokens)
    local kinds = {}
    for index, token in ipairs(tokens) do
      kinds[index] = token.kind
    end
    return table.concat(kinds, ",")
  end

  test.case("lexer emits documented tokens and exact byte spans", function()
    local tokens, diagnostics = lexer.lex("act view = 5ms\n")

    test.equals(#diagnostics, 0)
    test.equals(token_kinds(tokens), "LOWER_IDENTIFIER,LOWER_IDENTIFIER,EQUAL,QUANTITY,NEWLINE,EOF")
    test.equals(tokens[1].lexeme, "act")
    test.equals(tokens[1].span.start_byte, 0)
    test.equals(tokens[1].span.end_byte, 3)
    test.equals(tokens[1].span.start_line, 1)
    test.equals(tokens[1].span.start_column, 1)
    test.equals(tokens[4].unit, "ms")
    test.equals(tokens[4].span.start_byte, 11)
    test.equals(tokens[4].span.end_byte, 14)
    test.equals(tokens[4].span.end_column, 15)
    test.equals(tokens[5].span.start_byte, 14)
    test.equals(tokens[5].span.end_byte, 15)
    test.equals(tokens[5].span.end_line, 2)
    test.equals(tokens[5].span.end_column, 1)
    test.equals(tokens[6].span.start_byte, 15)
    test.equals(tokens[6].span.end_byte, 15)
  end)

  test.case("lexer emits deterministic layout tokens", function()
    local source = "case target of\n  Some ally -> ally\n  None -> target\n"
    local tokens, diagnostics = lexer.lex(source)

    test.equals(#diagnostics, 0)
    test.equals(
      token_kinds(tokens),
      "KW_CASE,LOWER_IDENTIFIER,KW_OF,NEWLINE,INDENT,UPPER_IDENTIFIER,LOWER_IDENTIFIER,ARROW,LOWER_IDENTIFIER,NEWLINE,UPPER_IDENTIFIER,ARROW,LOWER_IDENTIFIER,NEWLINE,DEDENT,EOF"
    )
    test.equals(tokens[5].span.start_byte, 17)
    test.equals(tokens[5].span.end_byte, 17)
    test.equals(tokens[5].span.start_line, 2)
    test.equals(tokens[5].span.start_column, 3)
    test.equals(tokens[15].span.start_byte, #source)
    test.equals(tokens[15].span.end_byte, #source)
  end)

  test.case("lexer accepts zero-valued integer and float quantities", function()
    local tokens, diagnostics = lexer.lex("act = [0ms, 0.5m, 30deg]")

    test.equals(#diagnostics, 0)
    test.equals(
      token_kinds(tokens),
      "LOWER_IDENTIFIER,EQUAL,LEFT_BRACKET,QUANTITY,COMMA,QUANTITY,COMMA,QUANTITY,RIGHT_BRACKET,EOF"
    )
    test.equals(tokens[4].unit, "ms")
    test.equals(tokens[6].unit, "m")
    test.equals(tokens[8].unit, "deg")
  end)

  test.case("lexer ignores comments and blank lines for layout", function()
    local source = "act =\n  -- comment\n\n  Wait 5ms\n"
    local tokens, diagnostics = lexer.lex(source)

    test.equals(#diagnostics, 0)
    test.equals(
      token_kinds(tokens),
      "LOWER_IDENTIFIER,EQUAL,NEWLINE,NEWLINE,NEWLINE,INDENT,UPPER_IDENTIFIER,QUANTITY,NEWLINE,DEDENT,EOF"
    )
  end)

  test.case("lexer reports malformed source without throwing", function()
    local source = '\tact = "bad\\q"\r5s @'
    local ok, tokens, diagnostics = pcall(lexer.lex, source)

    test.truthy(ok)
    test.equals(type(tokens), "table")
    test.equals(type(diagnostics), "table")
    test.equals(#diagnostics, 5)
    test.error_code(diagnostics[1], "invalid_indentation")
    test.error_code(diagnostics[2], "invalid_escape")
    test.error_code(diagnostics[3], "invalid_line_ending")
    test.error_code(diagnostics[4], "invalid_quantity")
    test.error_code(diagnostics[5], "unknown_character")
    for _, diagnostic in ipairs(diagnostics) do
      test.equals(type(diagnostic.span), "table")
      test.truthy(diagnostic.span.end_byte >= diagnostic.span.start_byte)
    end
  end)

  test.case("lexer handles bounded arbitrary byte input", function()
    local samples = {
      "",
      "\0",
      "\255\254",
      "-- comment",
      "{ x = [Some 1, None] }",
      'if true then "ok" else "no"',
      "case x of\n  _ -> x",
    }

    for _, source in ipairs(samples) do
      local ok, tokens, diagnostics = pcall(lexer.lex, source)
      test.truthy(ok)
      test.equals(type(tokens), "table")
      test.equals(type(diagnostics), "table")
      test.equals(tokens[#tokens].kind, "EOF")
    end
  end)
end

return register
