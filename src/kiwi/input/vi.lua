-- Product navigation over retained cells; never move the application's cursor.
local Utf8 = require("kiwi.terminal.utf8")
local Vi = {}
Vi.__index = Vi
Vi.step_budget = 4096
Vi.maximum_work = 8 * 1024 * 1024
Vi.maximum_count = 9999

local function clamp(value, low, high) return math.max(low, math.min(value, high)) end
local function position(row, column, id) return { row_index = row, column = column, line_id = id } end
local function copy(point) return position(point.row_index, point.column, point.line_id) end
local function point(cell) return cell.codepoints and cell.codepoints[1] or Utf8.decode_one(cell.glyph) end
local function whitespace(value)
  return value == 32 or (value >= 9 and value <= 13) or value == 0x85 or value == 0xa0
    or value == 0x1680 or (value >= 0x2000 and value <= 0x200a) or value == 0x2028
    or value == 0x2029 or value == 0x202f or value == 0x205f or value == 0x3000
end
local function class(cell, big)
  local value = point(cell)
  if whitespace(value) then return 0 end
  if big or value >= 0x80 or value == 95 or (value >= 48 and value <= 57)
      or (value >= 65 and value <= 90) or (value >= 97 and value <= 122) then return 1 end
  return 2
end
local function anchor(row, column, columns)
  column = clamp(column, 0, columns - 1)
  return row.cells[column].continuation and row.cells[column].anchor_column or column
end
local function width(row, column) return math.max(1, row.cells[column].width or 1) end

function Vi.new()
  return setmetatable({ active = false, status = "inactive", count = "" }, Vi)
end

function Vi:leave(state, live)
  if self.visual then state:clear_selection() end
  self.active, self.cursor, self.anchor, self.visual, self.job = false, nil, nil, nil, nil
  self.prefix, self.count, self.status, self.awaiting = nil, "", "inactive", nil
  self.last_inline = nil
  self.selection_job = nil
  if live and state.history_offset ~= 0 then state:scroll_history(-state.history_offset) end
end

function Vi:reconcile(state)
  if not self.active then return false end
  if state:selection_scope() ~= self.scope then self:leave(state); return false end
  local document = state:document(self.scope)
  local index = document:position(self.cursor.line_id, self.cursor.row_index)
  if not index then index = 1; self.status = "history-evicted" end
  local entry = document:row(index)
  self.cursor = position(index, anchor(entry.row, self.cursor.column, state.columns), entry.line_id)
  if self.anchor then
    local at = document:position(self.anchor.line_id, self.anchor.row_index)
    if at then
      self.anchor.row_index = at
      self.anchor.column = anchor(document:row(at).row, self.anchor.column, state.columns)
    else
      self.anchor, self.visual, self.selection_job = nil, nil, nil
      state:clear_selection(); self.status = "selection-evicted"
    end
  end
  if self.job and self.job.generation ~= state.search_generation then
    self.job, self.status = nil, "output-changed"
  end
  if self.selection_job and self.selection_job.generation ~= state.search_generation then
    self.selection_job, self.status = nil, "output-changed"
    state:clear_selection()
  end
  return true
end

local function viewport(state, top)
  if state:selection_scope() ~= "primary" then return end
  local offset = clamp(state.scrollback:size() + 1 - top, 0, state.scrollback:size())
  if offset ~= state.history_offset then
    state.history_offset = offset
    state:sync_cursor_visibility(); state.damage:mark_all(); state.text_damage:mark_all()
  end
end

function Vi:reveal(state, center)
  local top = state:document(self.scope):top()
  local row = self.cursor.row_index
  if center then viewport(state, row - math.floor(state.rows / 2))
  elseif row < top then viewport(state, row)
  elseif row >= top + state.rows then viewport(state, row - state.rows + 1) end
end

function Vi:selection_completed(state)
  self.primary_revision = (self.primary_revision or 0) + 1
  self.primary_generation = state.search_generation
end

function Vi:update_selection(state, defer)
  self.selection_job = nil
  if not self.visual or not self.anchor then return end
  local document = state:document(self.scope)
  local a, b = copy(self.anchor), copy(self.cursor)
  local arow, brow = document:row(a.row_index).row, document:row(b.row_index).row
  if self.visual == "block" then
    local left = math.min(a.column, b.column)
    local right = math.max(a.column + width(arow, a.column), b.column + width(brow, b.column))
    a.column, b.column = left, math.min(state.columns, right)
    state.selection:set(self.scope, a, b, document, state.columns, "block")
    self:selection_completed(state)
    return
  end
  if a.row_index > b.row_index or (a.row_index == b.row_index and a.column > b.column) then a, b, arow, brow = b, a, brow, arow end
  if self.visual == "line" or self.visual == "word" then
    self.selection_job = { first = a, last = b, phase = "first", mode = self.visual,
      first_class = class(arow.cells[a.column]), last_class = class(brow.cells[b.column]),
      generation = state.search_generation, work = 0 }
    if self.visual == "line" then a.column, b.column = 0, state.columns
    else b.column = math.min(state.columns, b.column + width(brow, b.column)) end
    self.status = "selecting"
    state:clear_selection()
    if not defer then self:step_selection(state, 256) end
    return
  end
  b.column = math.min(state.columns, b.column + width(brow, b.column))
  state.selection:set(self.scope, a, b, document, state.columns)
  self:selection_completed(state)
end

function Vi:step_selection(state, budget)
  self.last_step_work = 0
  if not self:reconcile(state) or not self.selection_job then return false end
  local job, document = self.selection_job, state:document(self.scope)
  -- Borrow a row only within this slice, never in resumable/transaction data.
  local cached_index, cached_entry
  local function row(index)
    if cached_index ~= index then cached_index, cached_entry = index, document:row(index) end
    return cached_entry
  end
  while self.selection_job and self.last_step_work < budget do
    if job.work >= Vi.maximum_work then self.selection_job, self.status = nil, "selection-limit"; break end
    self.last_step_work, job.work = self.last_step_work + 1, job.work + 1
    local first = job.phase == "first"
    local endpoint = first and job.first or job.last
    local index, column = endpoint.row_index, endpoint.column
    local current = row(index).row
    local entry
    if job.mode == "line" then
      entry = row(index + (first and -1 or 1))
      if entry and (first and entry.row.wrapped or not first and current.wrapped) then
        endpoint.row_index, endpoint.line_id = index + (first and -1 or 1), entry.line_id
      else entry = nil end
    else
      if first then
        if column > 0 then column = anchor(current, column - 1, state.columns); entry = row(index)
        else
          index = index - 1; entry = row(index)
          if entry and entry.row.wrapped then column = anchor(entry.row, state.columns - 1, state.columns)
          else entry = nil end
        end
      elseif column < state.columns then entry = row(index)
      elseif current.wrapped then index, column = index + 1, 0; entry = row(index) end
      if entry and class(entry.row.cells[column]) == (first and job.first_class or job.last_class) then
        endpoint.row_index, endpoint.line_id = index, entry.line_id
        endpoint.column = first and column or math.min(state.columns, column + width(entry.row, column))
      else entry = nil end
    end
    if not entry then
      if first then job.phase = "last"
      else
        self.selection_job, self.status = nil, "normal"
        state.selection:set(self.scope, job.first, job.last, document, state.columns)
        self:selection_completed(state)
      end
    end
  end
  return self.selection_job == nil
end

function Vi:set_position(state, row, column, preserve_column, defer_selection)
  local document = state:document(self.scope)
  row = clamp(row, 1, document:count())
  local entry = document:row(row)
  self.cursor = position(row, anchor(entry.row, column, state.columns), entry.line_id)
  if not preserve_column then self.preferred_column = self.cursor.column end
  self:reveal(state); self:update_selection(state, defer_selection)
end

function Vi:enter(state)
  state:clear_search(); state:clear_selection()
  self.active, self.scope, self.status, self.count = true, state:selection_scope(), "normal", ""
  self.anchor, self.visual, self.job, self.prefix, self.awaiting = nil, nil, nil, nil, nil
  self.selection_job = nil
  self:set_position(state, state:document():top() + state.cursor.row, state.cursor.column)
end

function Vi:toggle_selection(state, mode)
  assert(mode == "character" or mode == "line" or mode == "block" or mode == "word")
  if not self:reconcile(state) then return false end
  self.job, self.selection_job = nil, nil
  if self.visual == mode then self.visual, self.anchor = nil, nil; state:clear_selection()
  else
    self.anchor = self.anchor or copy(self.cursor)
    self.visual = mode; self:update_selection(state)
  end
  return true
end

function Vi:cancel(state)
  self.job, self.awaiting, self.prefix, self.count = nil, nil, nil, ""
  self.selection_job = nil
  self.visual, self.anchor, self.status = nil, nil, "normal"
  state:clear_selection()
end

function Vi:remap(scope, mapper)
  if not self.active or self.scope ~= scope then return end
  self.cursor = mapper(self.cursor)
  self.anchor = self.anchor and mapper(self.anchor) or nil
  if not self.cursor then self.active, self.visual, self.anchor = false, nil, nil end
  if self.visual == "block" or not self.anchor then self.visual, self.anchor = nil, nil end
  self.preferred_column = self.cursor and self.cursor.column or 0
  if self.last_inline and self.last_inline.found then self.last_inline.found = mapper(self.last_inline.found) end
  self.job, self.status = nil, "resized"
  self.selection_job = nil
end

local direct = {
  up = true, down = true, top = true, bottom = true, first = true, center = true,
  high = true, middle = true, low = true, ["page-up"] = true, ["page-down"] = true,
  ["half-up"] = true, ["half-down"] = true, ["scroll-up"] = true, ["scroll-down"] = true,
}

function Vi:motion(state, name, count, argument)
  if not self:reconcile(state) then return false end
  assert(count == nil or (type(count) == "number" and count >= 1 and count <= Vi.maximum_count and count % 1 == 0), "invalid vi count")
  local amount, document = count or 1, state:document(self.scope)
  self.job, self.selection_job, self.status = nil, nil, "normal"
  if direct[name] then
    local row, column, preserve = self.cursor.row_index, self.cursor.column, true
    if name == "up" then row = row - amount
    elseif name == "down" then row = row + amount
    elseif name == "top" then row = count or 1
    elseif name == "bottom" then row = count or document:count()
    elseif name == "first" then column, preserve = 0, false
    elseif name == "center" then self:reveal(state, true); return true
    elseif name == "high" then row = document:top() + math.min(state.rows, amount) - 1
    elseif name == "middle" then row = document:top() + math.floor((state.rows - 1) / 2)
    elseif name == "low" then row = document:top() + state.rows - math.min(state.rows, amount)
    elseif name == "scroll-up" or name == "scroll-down" then
      local delta = name == "scroll-up" and -amount or amount
      viewport(state, document:top() + delta)
      row = clamp(row, document:top(), document:top() + state.rows - 1)
    else
      local delta = name:find("half", 1, true) and math.max(1, math.floor(state.rows / 2)) or math.max(1, state.rows - 1)
      delta = delta * amount * (name:find("up", 1, true) and -1 or 1)
      viewport(state, document:top() + delta); row = row + delta
    end
    self:set_position(state, row, preserve and self.preferred_column or column, preserve)
    return true
  end
  self.job = { name = name, row = self.cursor.row_index, column = self.cursor.column,
    remaining = amount, phase = "start", argument = argument,
    generation = state.search_generation, work = 0 }
  self.status = "moving"
  self:step(state)
  return true
end

local pairs_of_brackets = { [40] = 41, [41] = 40, [91] = 93, [93] = 91, [123] = 125, [125] = 123 }
local opening = { [40] = true, [91] = true, [123] = true }

function Vi:step(state, budget)
  budget = budget or Vi.step_budget
  assert(type(budget) == "number" and budget >= 1 and budget <= Vi.step_budget and budget % 1 == 0)
  self.last_step_work = 0
  if not self:reconcile(state) then return false end
  if not self.job then return self:step_selection(state, budget) end
  local document, job = state:document(self.scope), self.job
  local cached_index, cached_row
  local function row(index)
    if cached_index ~= index then
      local entry = document:row(index)
      cached_index, cached_row = index, entry and entry.row
    end
    return cached_row
  end
  local function cell() return row(job.row).cells[job.column] end
  local function advance(direction, wrap)
    local current, at = row(job.row), job.row
    local column = direction > 0 and job.column + width(current, job.column) or job.column - 1
    if column >= 0 and column < state.columns then job.column = anchor(current, column, state.columns); return true end
    local target = row(at + direction)
    if not target or wrap == "none" or (wrap == "soft" and not (direction > 0 and current.wrapped or direction < 0 and target.wrapped)) then return false end
    job.row, job.column = at + direction, direction > 0 and 0 or anchor(target, state.columns - 1, state.columns)
    return true, not (direction > 0 and current.wrapped or direction < 0 and target.wrapped)
  end
  local function complete()
    job.remaining = job.remaining - 1
    if job.remaining > 0 then job.phase = "start"; return end
    self.job, self.status = nil, "normal"
    self:set_position(state, job.row, job.column, false, true)
  end
  while self.job and self.last_step_work < budget do
    if job.work >= Vi.maximum_work then self.job, self.status = nil, "motion-limit"; break end
    self.last_step_work, job.work = self.last_step_work + 1, job.work + 1
    local name, phase = job.name, job.phase
    if name == "left" or name == "right" then
      if not advance(name == "left" and -1 or 1, "soft") then job.remaining = 1 end
      complete()
    elseif name == "last" or name == "first-occupied" then
      if phase == "start" then job.column = name == "last" and anchor(row(job.row), state.columns - 1, state.columns) or 0; job.phase = "scan"
      elseif (name == "last" and (cell().glyph ~= " " or cell().codepoints ~= nil))
          or (name == "first-occupied" and class(cell()) ~= 0) then job.remaining = 1; complete()
      elseif not advance(name == "last" and -1 or 1, "none") then job.column = 0; job.remaining = 1; complete() end
    elseif name == "word-next" or name == "word-back" or name == "word-end" then
      local big = job.argument == "big"
      if phase == "start" then
        job.category = class(cell(), big)
        if name == "word-next" then job.phase = job.category == 0 and "space" or "leave"
        else
          job.phase = "space"
          if not advance(name == "word-back" and -1 or 1, "all") then job.remaining = 1; complete() end
        end
      elseif phase == "leave" then
        local advanced, hard_break = advance(1, "all")
        if not advanced then job.remaining = 1; complete()
        elseif hard_break or class(cell(), big) ~= job.category then
          if class(cell(), big) == 0 then job.phase = "space" else complete() end
        end
      elseif phase == "space" then
        if class(cell(), big) == 0 then
          if not advance(name == "word-back" and -1 or 1, "all") then job.remaining = 1; complete() end
        elseif name == "word-next" then complete()
        else job.category, job.phase = class(cell(), big), "edge" end
      else
        local previous_row, previous_column = job.row, job.column
        local advanced, hard_break = advance(name == "word-back" and -1 or 1, "all")
        if not advanced or hard_break or class(cell(), big) ~= job.category then
          job.row, job.column = previous_row, previous_column
          if not advanced then job.remaining = 1 end
          complete()
        end
      end
    elseif name == "bracket" then
      if phase == "start" then
        local value = point(cell())
        if pairs_of_brackets[value] then
          job.open, job.close, job.depth = value, pairs_of_brackets[value], 1
          job.direction, job.phase = opening[value] and 1 or -1, "scan"
        elseif not advance(1, "none") then self.job, self.status = nil, "no-bracket" end
      elseif not advance(job.direction, "all") then self.job, self.status = nil, "no-bracket"
      else
        local value = point(cell())
        if value == job.open then job.depth = job.depth + 1
        elseif value == job.close then job.depth = job.depth - 1 end
        if job.depth == 0 then job.remaining = 1; complete() end
      end
    elseif name == "inline" then
      local spec = job.argument
      local before_row, before_column = job.row, job.column
      if not advance(spec.direction, "soft") then self.job, self.status = nil, "not-found"
      elseif point(cell()) == spec.point then
        if not spec.skip or spec.skip.line_id ~= row(job.row).line_id or spec.skip.column ~= job.column then
          if job.remaining == 1 and spec.till then
            spec.found = position(job.row, job.column, row(job.row).line_id)
            job.row, job.column = before_row, before_column
          end
          complete()
          if not self.job and self.last_inline then
            self.last_inline.found = spec.found or position(job.row, job.column, row(job.row).line_id)
          end
        end
      end
    else error("unknown vi motion: " .. tostring(name)) end
  end
  return self.job == nil
end

function Vi:inline(state, text, direction, till, count, repeated)
  local value = Utf8.decode_one(text)
  local spec = { point = value, direction = direction, till = till }
  if repeated and self.last_inline then spec.skip = self.last_inline.found end
  if not repeated then self.last_inline = { text = text, direction = direction, till = till } end
  return self:motion(state, "inline", count, spec)
end

function Vi:view(state)
  if not self:reconcile(state) then return { active = false } end
  local top = state:document(self.scope):top()
  return { active = true, column = self.cursor.column, row = self.cursor.row_index - top,
    row_index = self.cursor.row_index, line_id = self.cursor.line_id, scope = self.scope,
    visual = self.visual, status = self.status, pending = self.job ~= nil or self.selection_job ~= nil,
    count = self.count, prefix = self.prefix, awaiting = self.awaiting ~= nil }
end

function Vi.title(view, fallback)
  if not view.active then return fallback end
  local mode = view.visual and ("Visual " .. view.visual) or "Vi"
  local pending = view.awaiting and "find character" or view.pending and (view.status .. "; Esc cancels")
    or view.status ~= "normal" and view.status or "i exits; v selects; y copies"
  return "Kiwi [" .. mode .. "] " .. (view.count or "") .. (view.prefix or "") .. " — " .. pending
end

return Vi
