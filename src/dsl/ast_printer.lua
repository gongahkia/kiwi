local ast = require("src.dsl.ast")

local printer = {}

local schemas = {
  Program = {
    { name = "module", type = "node", optional = true },
    { name = "exposures", type = "list" },
    { name = "declarations", type = "list" },
  },
  ModuleDeclaration = { { name = "name", type = "scalar" } },
  ExposeDeclaration = { { name = "names", type = "list" } },
  Identifier = { { name = "name", type = "scalar" } },
  ErrorIdentifier = {},
  FunctionDeclaration = {
    { name = "name", type = "node" },
    { name = "parameters", type = "list" },
    { name = "body", type = "node" },
  },
  IntegerLiteral = { { name = "lexeme", type = "scalar" } },
  FloatLiteral = { { name = "lexeme", type = "scalar" } },
  QuantityLiteral = {
    { name = "lexeme", type = "scalar" },
    { name = "unit", type = "scalar" },
  },
  StringLiteral = { { name = "value", type = "scalar" } },
  BoolLiteral = { { name = "value", type = "scalar" } },
  UnitLiteral = {},
  ErrorExpression = {},
  VariableExpression = { { name = "name", type = "scalar" } },
  ConstructorExpression = { { name = "name", type = "scalar" } },
  GroupExpression = { { name = "expression", type = "node" } },
  TupleExpression = { { name = "items", type = "list" } },
  RecordExpression = { { name = "fields", type = "list" } },
  RecordField = {
    { name = "name", type = "node" },
    { name = "value", type = "node" },
  },
  ListExpression = { { name = "items", type = "list" } },
  FieldAccessExpression = {
    { name = "target", type = "node" },
    { name = "field", type = "node" },
  },
  ApplicationExpression = {
    { name = "callee", type = "node" },
    { name = "argument", type = "node" },
  },
  BinaryExpression = {
    { name = "left", type = "node" },
    { name = "operator", type = "scalar" },
    { name = "right", type = "node" },
  },
  PipelineExpression = {
    { name = "input", type = "node" },
    { name = "stage", type = "node" },
  },
  LetExpression = {
    { name = "name", type = "node" },
    { name = "value", type = "node" },
    { name = "body", type = "node" },
  },
  IfExpression = {
    { name = "condition", type = "node" },
    { name = "then_branch", type = "node" },
    { name = "else_branch", type = "node" },
  },
  CaseExpression = {
    { name = "subject", type = "node" },
    { name = "alternatives", type = "list" },
  },
  CaseAlternative = {
    { name = "pattern", type = "node" },
    { name = "body", type = "node" },
  },
  ErrorPattern = {},
  WildcardPattern = {},
  VariablePattern = { { name = "name", type = "scalar" } },
  ConstructorPattern = {
    { name = "name", type = "scalar" },
    { name = "arguments", type = "list" },
  },
  LiteralPattern = { { name = "literal", type = "node" } },
  TuplePattern = { { name = "items", type = "list" } },
  ListPattern = { { name = "items", type = "list" } },
}

local function quote(value)
  if type(value) == "boolean" then
    return value and "true" or "false"
  end
  if type(value) ~= "string" then
    return nil
  end

  local output = { '"' }
  for index = 1, #value do
    local byte = string.byte(value, index)
    if byte == 34 then
      output[#output + 1] = '\\"'
    elseif byte == 92 then
      output[#output + 1] = "\\\\"
    elseif byte == 10 then
      output[#output + 1] = "\\n"
    elseif byte == 13 then
      output[#output + 1] = "\\r"
    elseif byte == 9 then
      output[#output + 1] = "\\t"
    elseif byte < 32 or byte > 126 then
      output[#output + 1] = string.format("\\x%02x", byte)
    else
      output[#output + 1] = string.char(byte)
    end
  end
  output[#output + 1] = '"'
  return table.concat(output)
end

local function diagnostic(code, message, node)
  local span = node and node.span
  return {
    code = code,
    message = message,
    span = span and {
      start_byte = span.start_byte,
      end_byte = span.end_byte,
      start_line = span.start_line,
      start_column = span.start_column,
      end_line = span.end_line,
      end_column = span.end_column,
    } or {
      start_byte = 0,
      end_byte = 0,
      start_line = 1,
      start_column = 1,
      end_line = 1,
      end_column = 1,
    },
  }
end

local function format_node(node, indentation, prefix, output)
  if not ast.is_node(node) then
    return nil, diagnostic("invalid_ast", "expected immutable AST node")
  end
  local schema = schemas[node.kind]
  if not schema then
    return nil, diagnostic("unsupported_ast_node", "unsupported AST node " .. node.kind, node)
  end

  local attributes = {}
  for _, field in ipairs(schema) do
    local value = node[field.name]
    if field.type == "scalar" then
      local formatted = quote(value)
      if not formatted then
        return nil, diagnostic("invalid_ast", "invalid scalar field " .. field.name, node)
      end
      attributes[#attributes + 1] = field.name .. "=" .. formatted
    elseif field.type == "node" and not field.optional and not ast.is_node(value) then
      return nil, diagnostic("invalid_ast", "invalid node field " .. field.name, node)
    elseif field.type == "list" and not ast.is_list(value) then
      return nil, diagnostic("invalid_ast", "invalid list field " .. field.name, node)
    end
  end

  local line = indentation .. (prefix or "") .. node.kind
  if #attributes > 0 then
    line = line .. " " .. table.concat(attributes, " ")
  end
  output[#output + 1] = line .. " @" .. node.span.start_byte .. ":" .. node.span.end_byte

  for _, field in ipairs(schema) do
    if field.type == "node" then
      local value = node[field.name]
      if not value then
        output[#output + 1] = indentation .. "  " .. field.name .. ": null"
      else
        output[#output + 1] = indentation .. "  " .. field.name .. ":"
        local ok, err = format_node(value, indentation .. "    ", nil, output)
        if not ok then
          return nil, err
        end
      end
    elseif field.type == "list" then
      local value = node[field.name]
      if ast.length(value) == 0 then
        output[#output + 1] = indentation .. "  " .. field.name .. ": []"
      else
        output[#output + 1] = indentation .. "  " .. field.name .. ":"
        for _, item in ast.each(value) do
          local ok, err = format_node(item, indentation .. "    ", "- ", output)
          if not ok then
            return nil, err
          end
        end
      end
    end
  end
  return true
end

function printer.format(node)
  local output = {}
  local ok, err = format_node(node, "", nil, output)
  if not ok then
    return nil, err
  end
  return table.concat(output, "\n")
end

return printer
