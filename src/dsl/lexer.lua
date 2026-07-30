local lexer = {}

local keyword_kinds = {
  ["module"] = "KW_MODULE",
  ["expose"] = "KW_EXPOSE",
  ["let"] = "KW_LET",
  ["in"] = "KW_IN",
  ["if"] = "KW_IF",
  ["then"] = "KW_THEN",
  ["else"] = "KW_ELSE",
  ["case"] = "KW_CASE",
  ["of"] = "KW_OF",
}

local function is_digit(character)
  return character >= "0" and character <= "9"
end

local function is_lower(character)
  return character >= "a" and character <= "z"
end

local function is_upper(character)
  return character >= "A" and character <= "Z"
end

local function is_identifier_continue(character)
  return is_lower(character) or is_upper(character) or is_digit(character) or character == "_"
end

local function copy_point(state)
  return {
    byte = state.index - 1,
    line = state.line,
    column = state.column,
  }
end

local function span(start_point, end_point)
  return {
    start_byte = start_point.byte,
    end_byte = end_point.byte,
    start_line = start_point.line,
    start_column = start_point.column,
    end_line = end_point.line,
    end_column = end_point.column,
  }
end

local function zero_span()
  return {
    start_byte = 0,
    end_byte = 0,
    start_line = 1,
    start_column = 1,
    end_line = 1,
    end_column = 1,
  }
end

function lexer.lex(source)
  if type(source) ~= "string" then
    return {
      { kind = "EOF", lexeme = "", span = zero_span() },
    }, {
      {
        code = "invalid_source",
        message = "source must be a string",
        span = zero_span(),
      },
    }
  end

  local source_length = #source
  local state = { index = 1, line = 1, column = 1 }
  local tokens = {}
  local diagnostics = {}
  local indentation = { 0 }
  local at_line_start = true

  local function current()
    if state.index > source_length then
      return nil
    end
    return source:sub(state.index, state.index)
  end

  local function peek()
    if state.index + 1 > source_length then
      return nil
    end
    return source:sub(state.index + 1, state.index + 1)
  end

  local function advance()
    state.index = state.index + 1
    state.column = state.column + 1
  end

  local function add_token(kind, start_point, start_index, extra)
    local token = {
      kind = kind,
      lexeme = source:sub(start_index, state.index - 1),
      span = span(start_point, copy_point(state)),
    }
    if extra then
      token.unit = extra.unit
    end
    tokens[#tokens + 1] = token
  end

  local function add_layout_token(kind)
    local point = copy_point(state)
    tokens[#tokens + 1] = {
      kind = kind,
      lexeme = "",
      span = span(point, point),
    }
  end

  local function add_diagnostic(code, message, start_point)
    diagnostics[#diagnostics + 1] = {
      code = code,
      message = message,
      span = span(start_point, copy_point(state)),
    }
  end

  local function consume_newline()
    local start_point = copy_point(state)
    local start_index = state.index
    if current() == "\r" and peek() ~= "\n" then
      advance()
      add_diagnostic("invalid_line_ending", "use LF or CRLF line endings", start_point)
    elseif current() == "\r" then
      state.index = state.index + 2
    else
      state.index = state.index + 1
    end
    state.line = state.line + 1
    state.column = 1
    add_token("NEWLINE", start_point, start_index)
    at_line_start = true
  end

  local function scan_identifier()
    local start_point = copy_point(state)
    local start_index = state.index
    local starts_upper = is_upper(current())
    repeat
      advance()
    until not is_identifier_continue(current() or "")
    local lexeme = source:sub(start_index, state.index - 1)
    local kind = keyword_kinds[lexeme]
    if lexeme == "true" or lexeme == "false" then
      kind = "BOOL"
    elseif not kind then
      kind = starts_upper and "UPPER_IDENTIFIER" or "LOWER_IDENTIFIER"
    end
    add_token(kind, start_point, start_index)
  end

  local function scan_number()
    local start_point = copy_point(state)
    local start_index = state.index
    local leading_zero = current() == "0"
    repeat
      advance()
    until not is_digit(current() or "")
    local integer_end = state.index
    local invalid_leading_zero = leading_zero and integer_end - start_index > 1

    local is_float = false
    if current() == "." and is_digit(peek() or "") then
      is_float = true
      advance()
      repeat
        advance()
      until not is_digit(current() or "")
    end

    local number_end = state.index
    if is_identifier_continue(current() or "") then
      repeat
        advance()
      until not is_identifier_continue(current() or "")
      local suffix = source:sub(number_end, state.index - 1)
      if not invalid_leading_zero and (suffix == "ms" or suffix == "m" or suffix == "deg") then
        add_token("QUANTITY", start_point, start_index, { unit = suffix })
      else
        add_diagnostic("invalid_quantity", "invalid quantity suffix", start_point)
        add_token("INVALID", start_point, start_index)
      end
    elseif invalid_leading_zero then
      add_diagnostic("invalid_number", "integer literals cannot have leading zeroes", start_point)
      add_token("INVALID", start_point, start_index)
    else
      add_token(is_float and "FLOAT" or "INTEGER", start_point, start_index)
    end
  end

  local function scan_string()
    local start_point = copy_point(state)
    local start_index = state.index
    local valid = true
    advance()

    while current() do
      local character = current()
      if character == '"' then
        advance()
        add_token(valid and "STRING" or "INVALID", start_point, start_index)
        return
      end
      if character == "\n" or character == "\r" then
        add_diagnostic("unterminated_string", "string literal is not terminated", start_point)
        add_token("INVALID", start_point, start_index)
        return
      end
      if character == "\\" then
        local escape_start = copy_point(state)
        advance()
        local escaped = current()
        if
          escaped == '"'
          or escaped == "\\"
          or escaped == "n"
          or escaped == "r"
          or escaped == "t"
        then
          advance()
        elseif escaped and escaped ~= "\n" and escaped ~= "\r" then
          advance()
          add_diagnostic("invalid_escape", "invalid string escape", escape_start)
          valid = false
        else
          add_diagnostic("unterminated_string", "string literal is not terminated", start_point)
          add_token("INVALID", start_point, start_index)
          return
        end
      else
        advance()
      end
    end

    add_diagnostic("unterminated_string", "string literal is not terminated", start_point)
    add_token("INVALID", start_point, start_index)
  end

  local function scan_punctuation_or_operator()
    local start_point = copy_point(state)
    local start_index = state.index
    local first = current()
    local second = peek()
    local pair = (first or "") .. (second or "")

    if pair == "->" then
      advance()
      advance()
      add_token("ARROW", start_point, start_index)
    elseif pair == "|>" then
      advance()
      advance()
      add_token("PIPE", start_point, start_index)
    elseif pair == "<=" or pair == "==" or pair == "!=" or pair == ">=" then
      advance()
      advance()
      add_token("OPERATOR", start_point, start_index)
    elseif
      first == "<"
      or first == ">"
      or first == "+"
      or first == "-"
      or first == "*"
      or first == "/"
    then
      advance()
      add_token("OPERATOR", start_point, start_index)
    elseif first == "(" then
      advance()
      add_token("LEFT_PAREN", start_point, start_index)
    elseif first == ")" then
      advance()
      add_token("RIGHT_PAREN", start_point, start_index)
    elseif first == "[" then
      advance()
      add_token("LEFT_BRACKET", start_point, start_index)
    elseif first == "]" then
      advance()
      add_token("RIGHT_BRACKET", start_point, start_index)
    elseif first == "{" then
      advance()
      add_token("LEFT_BRACE", start_point, start_index)
    elseif first == "}" then
      advance()
      add_token("RIGHT_BRACE", start_point, start_index)
    elseif first == "," then
      advance()
      add_token("COMMA", start_point, start_index)
    elseif first == "." then
      advance()
      add_token("DOT", start_point, start_index)
    elseif first == "=" then
      advance()
      add_token("EQUAL", start_point, start_index)
    else
      advance()
      add_diagnostic("unknown_character", "unknown character", start_point)
      add_token("INVALID", start_point, start_index)
    end
  end

  local function apply_indentation(width)
    local top = indentation[#indentation]
    if width > top then
      indentation[#indentation + 1] = width
      add_layout_token("INDENT")
      return
    end
    while width < indentation[#indentation] and #indentation > 1 do
      indentation[#indentation] = nil
      add_layout_token("DEDENT")
    end
    if width ~= indentation[#indentation] then
      local start_point = copy_point(state)
      add_diagnostic(
        "inconsistent_indentation",
        "indentation must match an active indentation depth",
        start_point
      )
    end
  end

  while current() do
    if at_line_start then
      local indentation_width = 0
      while current() == " " or current() == "\t" do
        if current() == "\t" then
          local tab_start = copy_point(state)
          advance()
          add_diagnostic("invalid_indentation", "tabs are not allowed in indentation", tab_start)
        else
          indentation_width = indentation_width + 1
          advance()
        end
      end

      if current() == "\n" or current() == "\r" then
        consume_newline()
      elseif current() == "-" and peek() == "-" then
        while current() and current() ~= "\n" and current() ~= "\r" do
          advance()
        end
      elseif not current() then
        break
      else
        apply_indentation(indentation_width)
        at_line_start = false
      end
    else
      local character = current()
      if character == " " or character == "\t" then
        advance()
      elseif character == "\n" or character == "\r" then
        consume_newline()
      elseif character == "-" and peek() == "-" then
        while current() and current() ~= "\n" and current() ~= "\r" do
          advance()
        end
      elseif is_lower(character) or is_upper(character) or character == "_" then
        scan_identifier()
      elseif is_digit(character) then
        scan_number()
      elseif character == '"' then
        scan_string()
      else
        scan_punctuation_or_operator()
      end
    end
  end

  while #indentation > 1 do
    indentation[#indentation] = nil
    add_layout_token("DEDENT")
  end
  add_layout_token("EOF")
  return tokens, diagnostics
end

return lexer
