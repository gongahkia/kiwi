local ordered = require("src.util.ordered")

local ast = {}
local node_values = setmetatable({}, { __mode = "k" })
local list_values = setmetatable({}, { __mode = "k" })
local span_values = setmetatable({}, { __mode = "k" })

local span_keys = {
  "start_byte",
  "end_byte",
  "start_line",
  "start_column",
  "end_line",
  "end_column",
}

local function immutable_proxy(values)
  return setmetatable({}, {
    __index = values,
    __newindex = function()
      error("AST values are immutable", 2)
    end,
    __metatable = "immutable AST value",
  })
end

local function is_span(value)
  return span_values[value] ~= nil
end

local function span_source(value)
  if ast.is_node(value) then
    return value.span
  end
  return value
end

function ast.span(source)
  if is_span(source) then
    return source
  end
  if type(source) ~= "table" then
    error("AST span must be a table", 2)
  end

  local values = {}
  for _, key in ipairs(span_keys) do
    if type(source[key]) ~= "number" then
      error("AST span field " .. key .. " must be a number", 2)
    end
    values[key] = source[key]
  end

  local value = immutable_proxy(values)
  span_values[value] = values
  return value
end

function ast.combine_spans(first, last)
  local first_span = span_source(first)
  local last_span = span_source(last)
  if type(first_span) ~= "table" or type(last_span) ~= "table" then
    error("AST span range requires nodes or spans", 2)
  end
  return {
    start_byte = first_span.start_byte,
    end_byte = last_span.end_byte,
    start_line = first_span.start_line,
    start_column = first_span.start_column,
    end_line = last_span.end_line,
    end_column = last_span.end_column,
  }
end

function ast.list(items)
  if type(items) ~= "table" then
    error("AST list items must be a table", 2)
  end

  local values = {}
  local length = #items
  for index = 1, length do
    values[index] = items[index]
  end
  values.length = length

  local value = immutable_proxy(values)
  list_values[value] = values
  return value
end

function ast.length(value)
  local values = list_values[value]
  if not values then
    error("expected AST list", 2)
  end
  return values.length
end

function ast.at(value, index)
  local values = list_values[value]
  if not values then
    error("expected AST list", 2)
  end
  if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > values.length then
    return nil
  end
  return values[index]
end

function ast.each(value)
  local values = list_values[value]
  if not values then
    error("expected AST list", 2)
  end
  local index = 0
  return function()
    index = index + 1
    if index <= values.length then
      return index, values[index]
    end
  end
end

function ast.is_node(value)
  return node_values[value] ~= nil
end

function ast.node(kind, source_span, fields)
  if type(kind) ~= "string" then
    error("AST node kind must be a string", 2)
  end
  if fields ~= nil and type(fields) ~= "table" then
    error("AST node fields must be a table", 2)
  end

  local values = { kind = kind, span = ast.span(source_span) }
  if fields then
    local keys, err = ordered.sorted_keys(fields)
    if not keys then
      error(err.message, 2)
    end
    for _, key in ipairs(keys) do
      local value = fields[key]
      if type(value) == "table" and not ast.is_node(value) and not list_values[value] and not is_span(value) then
        error("AST fields must use immutable AST values", 2)
      end
      values[key] = value
    end
  end

  local value = immutable_proxy(values)
  node_values[value] = values
  return value
end

return ast
