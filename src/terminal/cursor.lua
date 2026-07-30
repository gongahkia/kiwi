local Errors = require("runtime.errors")

local Cursor = {}

Cursor.contract = {
  copy = "copy(cursor) -> cursor | nil, error",
  new = "new(options?) -> cursor | nil, error",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function coordinate(value, name)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 then
    return config_error(name .. " must be a positive integer", { provided = value })
  end
  return value
end

function Cursor.new(options)
  if options == nil then
    options = {}
  end
  if type(options) ~= "table" then
    return config_error("cursor options must be a table")
  end
  for name in pairs(options) do
    if name ~= "column" and name ~= "pending_wrap" and name ~= "row" then
      return config_error("unknown cursor option", { option = name })
    end
  end
  local column = options.column
  if column == nil then
    column = 1
  end
  local valid_column, column_error = coordinate(column, "cursor column")
  if not valid_column then
    return nil, column_error
  end
  local row = options.row
  if row == nil then
    row = 1
  end
  local valid_row, row_error = coordinate(row, "cursor row")
  if not valid_row then
    return nil, row_error
  end
  local pending_wrap = options.pending_wrap
  if pending_wrap == nil then
    pending_wrap = false
  end
  if type(pending_wrap) ~= "boolean" then
    return config_error("cursor pending_wrap must be a boolean")
  end
  return {
    column = valid_column,
    pending_wrap = pending_wrap,
    row = valid_row,
  }
end

function Cursor.copy(cursor)
  return Cursor.new(cursor)
end

return Cursor
