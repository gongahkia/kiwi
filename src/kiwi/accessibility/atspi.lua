local Model = require("kiwi.accessibility.model")

local Atspi = {}
Atspi.__index = Atspi

local function codepoint_count(value)
  local count = 0
  -- Terminal cells contain validated UTF-8 glyphs.  Match one non-continuation
  -- byte followed by its continuation bytes; Lua patterns cannot express the
  -- discontiguous range of valid UTF-8 lead bytes directly.
  for _ in value:gmatch("[^\128-\191][\128-\191]*") do count = count + 1 end
  return count
end

local function endpoint_offset(lines, endpoint)
  if endpoint == nil then return -1 end
  local line = lines[endpoint.line_id]
  if line == nil then return -1 end
  local column = math.max(0, math.min(endpoint.column, line.columns))
  return line.start + (line.columns_to_offsets[column] or line.characters)
end

function Atspi.new(options)
  options = options or {}
  local max_rows = options.max_rows or 256
  local max_bytes = options.max_bytes or 64 * 1024
  assert(type(max_rows) == "number" and max_rows >= 1 and max_rows % 1 == 0, "AT-SPI max_rows must be a positive integer")
  assert(type(max_bytes) == "number" and max_bytes >= max_rows and max_bytes % 1 == 0, "AT-SPI max_bytes must leave one byte per row")
  return setmetatable({
    max_bytes = max_bytes,
    max_rows = max_rows,
    model = Model.new({ max_rows = max_rows, max_bytes = max_bytes - max_rows }),
  }, Atspi)
end

function Atspi:project(state)
  local viewport = self.model:viewport(state)
  local lines = {}
  local parts = {}
  local bytes = 0
  local characters = 0
  local final_row = viewport.start_row + viewport.exported_rows - 1
  local truncated = false
  for row_index = viewport.start_row, final_row do
    local source = state:visible_row(row_index)
    local line = { columns = state.columns, columns_to_offsets = {}, start = characters, characters = 0 }
    lines[source.line_id] = line
    local row_parts = {}
    for column = 0, state.columns - 1 do
      line.columns_to_offsets[column] = line.characters
      local cell = source.cells[column]
      if not cell.continuation then
        local glyph = cell.glyph or ""
        if bytes + #glyph > self.max_bytes then
          truncated = true
          break
        end
        row_parts[#row_parts + 1] = glyph
        bytes = bytes + #glyph
        local count = codepoint_count(glyph)
        line.characters = line.characters + count
        characters = characters + count
      end
    end
    line.columns_to_offsets[state.columns] = line.characters
    parts[#parts + 1] = table.concat(row_parts)
    if truncated then break end
    if row_index < final_row then
      if bytes + 1 > self.max_bytes then
        truncated = true
        break
      end
      parts[#parts + 1] = "\n"
      bytes = bytes + 1
      characters = characters + 1
    end
  end
  local caret = self.model:caret(state)
  local selection = self.model:selection(state)
  return {
    caret_offset = endpoint_offset(lines, caret),
    character_count = characters,
    selection_end = selection.active and endpoint_offset(lines, selection.finish) or -1,
    selection_start = selection.active and endpoint_offset(lines, selection.start) or -1,
    text = table.concat(parts),
    truncated = truncated,
  }
end

return Atspi
