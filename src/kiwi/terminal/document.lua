-- Ephemeral, read-only access to retained rows. Never store this view in State:
-- configuration transactions must not retain a closure pointing at live rows.
local Document = {}
Document.__index = Document

function Document.new(state, scope)
  assert(scope == "primary" or scope == "alternate", "invalid document scope")
  return setmetatable({ state = state, scope = scope }, Document)
end

function Document:count()
  return self.state.rows + (self.scope == "primary" and self.state.scrollback:size() or 0)
end

function Document.row_at(state, index, scope)
  if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then return nil end
  local row
  if scope == "primary" then
    local history = state.scrollback:size()
    row = index <= history and state.scrollback:peek(index) or state.primary.rows[index - history - 1]
  elseif scope == "alternate" then row = state.alternate.rows[index - 1] end
  if row then return { line_id = row.line_id, row = row } end
end

function Document:row(index) return Document.row_at(self.state, index, self.scope) end

function Document:position(line_id, hint)
  if line_id == nil then return nil end
  if hint then
    local entry = self:row(hint)
    if entry and entry.line_id == line_id then return hint end
  end
  local history = self.scope == "primary" and self.state.scrollback:size() or 0
  if self.scope == "primary" then
    local index = self.state.scrollback:position(line_id)
    if index then return index end
  end
  local screen = self.scope == "primary" and self.state.primary or self.state.alternate
  for row = 0, self.state.rows - 1 do
    if screen.rows[row].line_id == line_id then return history + row + 1 end
  end
end

function Document:top()
  return self.scope == "primary" and self.state.scrollback:size() - self.state.history_offset + 1 or 1
end

return Document
