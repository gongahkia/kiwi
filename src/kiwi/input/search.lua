local Utf8 = require("kiwi.terminal.utf8")

local Search = {}
Search.__index = Search

Search.maximum_query_bytes = 1024
Search.maximum_matches = 256

local function valid_direction(direction)
  return direction == "forward" or direction == "backward"
end

local function valid_utf8(text)
  if text:find("\0", 1, true) then return false end
  local valid = true
  local decoder = Utf8.Decoder.new(function(_, _, replaced)
    if replaced then valid = false end
  end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  return valid
end

local function row_text(row, columns)
  local fragments = {}
  local spans = {}
  local length = 0
  for column = 0, columns - 1 do
    local cell = row.cells[column]
    if cell and not cell.continuation then
      local glyph = cell.glyph
      local first = length + 1
      length = length + #glyph
      fragments[#fragments + 1] = glyph
      spans[#spans + 1] = {
        first = first,
        last = length,
        finish_column = math.min(columns, column + math.max(1, cell.width or 1)),
        start_column = column,
      }
    end
  end
  return table.concat(fragments), spans
end

local function span_at(spans, byte)
  for _, span in ipairs(spans) do
    if byte >= span.first and byte <= span.last then return span end
  end
end

local function copy_match(match)
  return {
    finish_column = match.finish_column,
    line_id = match.line_id,
    start_column = match.start_column,
  }
end

function Search.new(options)
  options = options or {}
  local maximum_query_bytes = options.maximum_query_bytes or Search.maximum_query_bytes
  local maximum_matches = options.maximum_matches or Search.maximum_matches
  assert(type(maximum_query_bytes) == "number" and maximum_query_bytes >= 1 and maximum_query_bytes % 1 == 0, "search query limit must be a positive integer")
  assert(type(maximum_matches) == "number" and maximum_matches >= 1 and maximum_matches % 1 == 0, "search match limit must be a positive integer")
  return setmetatable({
    current = 0,
    editing = false,
    generation = nil,
    matches = {},
    maximum_matches = maximum_matches,
    maximum_query_bytes = maximum_query_bytes,
    query = "",
    scope = nil,
    status = "inactive",
  }, Search)
end

function Search:clear()
  self.current = 0
  self.editing = false
  self.generation = nil
  self.matches = {}
  self.query = ""
  self.scope = nil
  self.status = "inactive"
end

function Search:begin(scope, direction)
  assert(type(scope) == "string", "search scope must be a string")
  assert(valid_direction(direction), "search direction must be forward or backward")
  self:clear()
  self.editing = true
  self.scope = scope
  self.status = "query"
end

function Search:append(text)
  assert(type(text) == "string" and valid_utf8(text), "search text must be NUL-free UTF-8")
  if not self.editing then return false, "inactive" end
  if #self.query + #text > self.maximum_query_bytes then return false, "over-limit" end
  self.query = self.query .. text
  self.current = 0
  self.generation = nil
  self.matches = {}
  self.status = "query"
  return true, "query"
end

function Search:backspace()
  if not self.editing then return false, "inactive" end
  local first = #self.query
  while first > 1 and self.query:byte(first) >= 0x80 and self.query:byte(first) <= 0xbf do
    first = first - 1
  end
  if first == 0 then return false, "query" end
  self.query = self.query:sub(1, first - 1)
  self.current = 0
  self.generation = nil
  self.matches = {}
  self.status = "query"
  return true, "query"
end

function Search:submit(document, columns, generation, scope, direction)
  assert(type(document) == "table", "search document must be a table")
  assert(type(columns) == "number" and columns >= 1 and columns % 1 == 0, "search columns must be a positive integer")
  assert(type(generation) == "number" and generation >= 0 and generation % 1 == 0, "search generation must be a non-negative integer")
  assert(type(scope) == "string", "search scope must be a string")
  assert(valid_direction(direction), "search direction must be forward or backward")
  self.editing = false
  self.scope = scope
  self.generation = generation
  self.matches = {}
  self.current = 0
  if #self.query == 0 then
    self.status = "empty"
    return nil, self.status
  end
  for _, entry in ipairs(document) do
    local text, spans = row_text(entry.row, columns)
    local offset = 1
    while offset <= #text and #self.matches < self.maximum_matches do
      local first, last = text:find(self.query, offset, true)
      if first == nil then break end
      local start_span = span_at(spans, first)
      local finish_span = span_at(spans, last)
      if start_span and finish_span then
        self.matches[#self.matches + 1] = {
          finish_column = finish_span.finish_column,
          line_id = entry.line_id,
          start_column = start_span.start_column,
        }
      end
      offset = first + 1
    end
    if #self.matches >= self.maximum_matches then break end
  end
  if #self.matches == 0 then
    self.status = "no-match"
    return nil, self.status
  end
  self.status = "matches"
  self.current = direction == "backward" and #self.matches or 1
  return copy_match(self.matches[self.current]), self.status
end

function Search:navigate(direction, generation, scope)
  assert(valid_direction(direction), "search direction must be forward or backward")
  if self.status == "inactive" then return nil, "inactive" end
  if self.scope ~= scope then return nil, "hidden" end
  if self.generation == nil or self.generation ~= generation then return nil, "stale" end
  if #self.matches == 0 then return nil, self.status end
  if direction == "forward" then
    self.current = self.current % #self.matches + 1
  else
    self.current = (self.current - 2) % #self.matches + 1
  end
  self.status = "matches"
  return copy_match(self.matches[self.current]), self.status
end

function Search:view(generation, visible_scope)
  local active = self.status ~= "inactive"
  local stale = active and self.generation ~= nil and self.generation ~= generation
  local matches = {}
  if not stale then
    for index, match in ipairs(self.matches) do matches[index] = copy_match(match) end
  end
  local current = not stale and self.matches[self.current] and copy_match(self.matches[self.current]) or nil
  return {
    active = active,
    current = current,
    current_index = stale and 0 or self.current,
    editing = self.editing,
    generation = self.generation,
    match_count = stale and 0 or #matches,
    matches = matches,
    query = self.query,
    scope = self.scope,
    status = stale and "stale" or self.status,
    visible = active and self.scope == visible_scope,
  }
end

return Search
