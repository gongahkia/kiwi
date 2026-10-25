local Utf8 = require("kiwi.terminal.utf8")
local Regex = require("kiwi.input.regex")
local Search = {}
Search.__index = Search
Search.maximum_query_bytes = 1024
Search.maximum_matches = 256
Search.maximum_line_points = 65536
Search.maximum_work = 32 * 1024 * 1024
Search.step_budget = 4096

local function direction_valid(direction) return direction == "forward" or direction == "backward" end
local function valid_utf8(text)
  if text:find("\0", 1, true) then return false end
  local valid = true
  local decoder = Utf8.Decoder.new(function(_, _, replaced) if replaced then valid = false end end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  return valid
end
local function copy_match(match)
  return { line_id = match.line_id, finish_line_id = match.finish_line_id,
    row_index = match.row_index, finish_row_index = match.finish_row_index,
    start_column = match.start_column, finish_column = match.finish_column, empty = match.empty }
end
local function new_line()
  return { points = {}, line_ids = {}, row_indices = {}, columns = {}, finishes = {}, last_text = 0 }
end

function Search.new(options)
  options = options or {}
  local self = setmetatable({ mode = "literal" }, Search)
  for _, name in ipairs({ "maximum_query_bytes", "maximum_matches", "maximum_line_points", "maximum_work" }) do
    local value = options[name] or Search[name]
    assert(type(value) == "number" and value >= 1 and value % 1 == 0 and value <= Search[name], "invalid search " .. name)
    self[name] = value
  end
  self:clear()
  return self
end

function Search:clear()
  self.current, self.editing, self.generation = 0, false, nil
  self.matches, self.query, self.scope, self.status = {}, "", nil, "inactive"
  self.job, self.error, self.truncated = nil, nil, false
  self.work, self.scanned_rows, self.last_step_work = 0, 0, 0
end
function Search:begin(scope, direction, mode)
  assert(type(scope) == "string" and direction_valid(direction), "search needs a scope and direction")
  mode = mode or self.mode
  assert(mode == "literal" or mode == "regex", "search mode must be literal or regex")
  self:clear()
  self.mode, self.scope, self.editing, self.status = mode, scope, true, "query"
end
local function edited(self)
  self.current, self.generation, self.matches, self.status = 0, nil, {}, "query"
  self.job, self.error, self.truncated = nil, nil, false
  self.work, self.scanned_rows = 0, 0
end
function Search:toggle_mode()
  if self.status == "inactive" then return false end
  self.mode = self.mode == "literal" and "regex" or "literal"
  self.editing = true
  edited(self)
  return true
end
function Search:append(text)
  assert(type(text) == "string" and valid_utf8(text), "search text must be NUL-free UTF-8")
  if not self.editing then return false, "inactive" end
  if #self.query + #text > self.maximum_query_bytes then return false, "over-limit" end
  self.query = self.query .. text
  edited(self)
  return true, "query"
end
function Search:backspace()
  if not self.editing then return false, "inactive" end
  local first = #self.query
  while first > 1 and self.query:byte(first) >= 0x80 and self.query:byte(first) <= 0xbf do first = first - 1 end
  if first == 0 then return false, "query" end
  self.query = self.query:sub(1, first - 1)
  edited(self)
  return true, "query"
end

function Search:start(columns, generation, scope, direction)
  assert(type(columns) == "number" and columns >= 1 and columns % 1 == 0, "search columns must be positive")
  assert(type(generation) == "number" and generation >= 0 and generation % 1 == 0, "search generation must be non-negative")
  assert(type(scope) == "string" and direction_valid(direction), "search needs a scope and direction")
  self.editing, self.scope, self.generation = false, scope, generation
  self.matches, self.current, self.error, self.truncated, self.job = {}, 0, nil, false, nil
  self.work, self.scanned_rows, self.last_step_work = 0, 0, 0
  if #self.query == 0 then self.status = "empty"; return nil, self.status end
  local program, reason = Regex.compile(self.query, self.mode == "literal")
  if not program then
    self.status, self.error, self.editing = "invalid-pattern", reason, true
    return nil, self.status
  end
  self.status = "searching"
  -- Plain resumable data only: configuration transactions can copy a job
  -- without sharing a coroutine or closures that still mutate the old State.
  self.job = { program = program, columns = columns, direction = direction, row_index = 1,
    column = 0, byte = 1, phase = "read", line = new_line() }
  return nil, self.status
end
function Search:finish(status, message)
  local job = self.job
  self.status, self.error, self.job = status, message, nil
  self.truncated = status == "match-limit" or status == "work-limit" or status == "line-limit"
  if #self.matches > 0 then
    self.current = job and job.direction == "backward" and #self.matches or 1
    return copy_match(self.matches[self.current]), status
  end
  return nil, status
end
function Search:invalidate()
  if self.job then self.job, self.status = nil, "stale" end
end

local function record_match(self, line, first, last)
  local empty = last < first
  local index = math.min(first, #line.points)
  local finish = math.max(1, last)
  local start_column = line.columns[index] or 0
  if first > #line.points and #line.points > 0 then start_column = line.finishes[index] end
  local line_id = line.line_ids[index] or line.first_line_id
  local row_index = line.row_indices[index] or line.first_row_index
  self.matches[#self.matches + 1] = {
    line_id = line_id, row_index = row_index, start_column = start_column,
    finish_line_id = empty and line_id or line.line_ids[finish],
    finish_row_index = empty and row_index or line.row_indices[finish],
    finish_column = empty and start_column or line.finishes[finish], empty = empty,
  }
end

function Search:step(provider, generation, scope, budget)
  assert(type(provider) == "function", "search needs a row provider")
  budget = budget or Search.step_budget
  assert(type(budget) == "number" and budget >= 1 and budget % 1 == 0 and budget <= Search.step_budget, "invalid search step budget")
  self.last_step_work = 0
  if not self.job then return nil, self.status end
  if generation ~= self.generation or scope ~= self.scope then self:invalidate(); return nil, "stale" end
  -- Cache only for this event-loop slice. No borrowed terminal rows survive
  -- a yield or get copied into a configuration transaction's search job.
  local provider_index, provider_entry
  local function row_at(index)
    if provider_index ~= index then provider_index, provider_entry = index, provider(index) end
    return provider_entry
  end
  local used = 0
  while self.job and used < budget do
    if self.work >= self.maximum_work then
      self.last_step_work = used
      return self:finish("work-limit", "Search work limit reached; narrow the expression")
    end
    local job, charged = self.job, 1
    local line = job.line
    if job.phase == "read" then
      local entry = row_at(job.row_index)
      if entry == nil then
        self.last_step_work = used
        return self:finish(#self.matches > 0 and "matches" or "no-match")
      end
      line.first_line_id = line.first_line_id or entry.line_id
      line.first_row_index = line.first_row_index or job.row_index
      if job.column >= job.columns then
        self.scanned_rows = self.scanned_rows + 1
        job.row_index, job.column, job.byte = job.row_index + 1, 0, 1
        if entry.row.wrapped and row_at(job.row_index) ~= nil then line.last_text = #line.points
        else job.phase = "trim" end
      else
        local cell = entry.row.cells[job.column]
        if cell == nil or cell.continuation or job.byte > #cell.glyph then
          job.column, job.byte = job.column + 1, 1
        else
          if #line.points >= self.maximum_line_points then
            self.last_step_work = used
            return self:finish("line-limit", "Logical line exceeds the search size limit")
          end
          local byte = cell.glyph:byte(job.byte)
          local length = byte < 0x80 and 1 or byte < 0xe0 and 2 or byte < 0xf0 and 3 or 4
          local point = Utf8.decode_one(cell.glyph:sub(job.byte, job.byte + length - 1))
          local index = #line.points + 1
          line.points[index], line.line_ids[index], line.row_indices[index] = point, entry.line_id, job.row_index
          line.columns[index], line.finishes[index] = job.column, math.min(job.columns, job.column + math.max(1, cell.width or 1))
          if cell.glyph ~= " " or cell.codepoints ~= nil then line.last_text = index end
          job.byte = job.byte + length
        end
      end
    elseif job.phase == "trim" then
      -- Erased trailing cells are padding, while explicitly printed spaces
      -- retain their codepoints and remain searchable, including before $.
      local index = #line.points
      if index > line.last_text then
        line.points[index], line.line_ids[index], line.row_indices[index], line.columns[index], line.finishes[index] = nil, nil, nil, nil, nil
      else
        job.offset, job.runner, job.phase = 1, Regex.runner(job.program, line.points, nil, job.runner), "match"
      end
    elseif job.phase == "clear" then
      local index = #line.points
      if index > 0 then
        line.points[index], line.line_ids[index], line.row_indices[index], line.columns[index], line.finishes[index] = nil, nil, nil, nil, nil
      else
        line.first_line_id, line.first_row_index, line.last_text = nil, nil, 0
        job.phase = "read"
      end
    else
      local done, first, last, operations = job.runner:step(math.min(budget - used, self.maximum_work - self.work))
      charged = operations
      if done then
        if first then
          record_match(self, line, first, last)
          if #self.matches >= self.maximum_matches then
            self.work, self.last_step_work = self.work + charged, used + charged
            return self:finish("match-limit", "Match limit reached; narrow the query")
          end
          job.offset = self.mode == "literal" and first + 1 or math.max(first + 1, last + 1)
        end
        if first and job.offset <= #line.points + 1 then job.runner = Regex.runner(job.program, line.points, job.offset, job.runner)
        else job.phase = "clear" end
      end
    end
    used, self.work = used + charged, self.work + charged
  end
  self.last_step_work = used
  return nil, self.status
end

-- Compatibility entrypoint for model callers; large documents now return
-- "searching" and must be advanced with step instead of blocking the caller.
function Search:submit(document, columns, generation, scope, direction)
  assert(type(document) == "table", "search document must be a table")
  self:start(columns, generation, scope, direction)
  return self:step(function(index) return document[index] end, generation, scope)
end
function Search:navigate(direction, generation, scope)
  assert(direction_valid(direction), "search direction must be forward or backward")
  if self.status == "inactive" then return nil, "inactive" end
  if self.scope ~= scope then return nil, "hidden" end
  if self.generation == nil or self.generation ~= generation then return nil, "stale" end
  if self.job or #self.matches == 0 then return nil, self.status end
  self.current = direction == "forward" and self.current % #self.matches + 1 or (self.current - 2) % #self.matches + 1
  return copy_match(self.matches[self.current]), self.status
end
function Search:view(generation, visible_scope)
  local active = self.status ~= "inactive"
  local stale = active and self.generation ~= nil and self.generation ~= generation
  local matches = {}
  if not stale then for index, match in ipairs(self.matches) do matches[index] = copy_match(match) end end
  return { active = active, visible = active and self.scope == visible_scope,
    current = not stale and self.matches[self.current] and copy_match(self.matches[self.current]) or nil,
    current_index = stale and 0 or self.current, editing = self.editing, generation = self.generation,
    match_count = #matches, matches = matches, query = self.query, scope = self.scope,
    status = stale and "stale" or self.status, mode = self.mode, error = self.error,
    truncated = self.truncated, scanned_rows = self.scanned_rows, work = self.work }
end
function Search.title(view, fallback)
  if not view.active or not view.visible then return fallback end
  local query = view.query:gsub("[%z\1-\31\127]", " ")
  local mode = view.mode == "regex" and "Regex" or "Literal"
  if view.editing then return "Kiwi Find [" .. mode .. "; Alt+R toggles] " .. query .. (view.error and (" — " .. view.error) or "") end
  local status = view.status == "matches" and (view.current_index .. "/" .. view.match_count)
    or view.status == "searching" and ("Searching: " .. view.scanned_rows .. " rows; Esc cancels")
    or view.status == "no-match" and "No matches"
    or view.status == "stale" and "Output changed; restart Find"
    or view.error or view.status
  return "Kiwi Find [" .. mode .. "] " .. query .. " — " .. status
end
return Search
