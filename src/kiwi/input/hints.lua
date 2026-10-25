-- Bounded visible-link discovery. Jobs retain positions/strings, never rows or
-- providers, so configuration transactions cannot mutate another State's job.
local Hyperlink = require("kiwi.terminal.hyperlink")
local Hints = {}
Hints.__index = Hints
Hints.alphabet = "asdfghjklqwertyuiopzxcvbnm"
Hints.maximum_matches = 256
Hints.maximum_cells = 262144
Hints.step_budget = 4096
local prefixes = { ["https://"] = true, ["http://"] = true, ["mailto:"] = true }
local punctuation = { ["."] = true, [","] = true, [";"] = true, [":"] = true, ["!"] = true, ["?"] = true }
local function allowed(text)
  return #text == 1 and text:byte() > 32 and text:byte() < 127 and not text:find('[<>"\'`\\{}]')
end
local function word(text) return text and text:match("^[%w_+.-]$") ~= nil end

function Hints.new() return setmetatable({ active = false, revision = 0, matches = {}, status = "inactive" }, Hints) end
function Hints:changed() self.revision = self.revision + 1 end
function Hints:clear(status)
  self.active, self.job, self.selected = false, nil, nil
  self.matches, self.prefix, self.page, self.status = {}, "", 1, status or "inactive"
  self.truncated, self.paged = false, false
  self:changed()
end
function Hints:reconcile(state)
  if not self.active then return false end
  local document = state:document()
  local reason
  if self.scope ~= state:selection_scope() then reason = "screen-changed"
  elseif self.columns ~= state.columns or self.rows ~= state.rows then reason = "resized"
  elseif self.generation ~= state.search_generation then reason = "output-changed"
  elseif self.top ~= document:top() then reason = "viewport-changed" end
  if reason and self.status ~= reason then
    self.matches, self.job, self.selected, self.prefix, self.status = {}, nil, nil, "", reason
    self.page, self.paged = 1, false
    self:changed()
  end
  return reason == nil
end
function Hints:begin(state, action)
  assert(action == "open" or action == "copy", "invalid hint action")
  self:clear()
  local document = state:document()
  self.active, self.action, self.scope = true, action, state:selection_scope()
  self.columns, self.rows, self.top, self.generation = state.columns, state.rows, document:top(), state.search_generation
  self.first, self.finish = (self.top - 1) * state.columns, (self.top - 1 + state.rows) * state.columns
  -- A little context finds complete URLs crossing either viewport boundary.
  local context = Hyperlink.maximum_uri_bytes + 8
  self.job = { at = math.max(0, self.first - context), finish = math.min(document:count() * state.columns, self.finish + context),
    probe = "", previous = nil, work = 0, phase = "scan" }
  self.status, self.last_step_work = "scanning", 0
  self:changed()
  self:step(state)
end
function Hints:record(uri, first, finish, kind)
  local start, stop = math.max(first, self.first), math.min(finish, self.finish)
  if stop <= start then return end
  self.matches[#self.matches + 1] = { uri = uri, first = start - self.first, finish = stop - self.first, kind = kind }
end
function Hints:finish_scan(status)
  self.job = nil
  table.sort(self.matches, function(a, b) return a.first < b.first end)
  self.status = status or (#self.matches > 0 and "ready" or "no-links")
  self.truncated = status ~= nil
  self.paged = false
  if #self.matches > #Hints.alphabet then
    -- Dense one-cell OSC 8 links cannot fit two-cell badges. Page single-letter
    -- labels in that case; every retained match remains keyboard reachable.
    for _, match in ipairs(self.matches) do
      if match.finish - match.first < 2 then self.paged = true; break end
    end
  end
  self:changed()
end
local function plain_valid(text)
  local lower = text:lower()
  if lower:sub(1, 7) == "mailto:" then return #text > 7 end
  local body = lower:sub(lower:sub(1, 8) == "https://" and 9 or 8)
  return body:match("^[^/?#]+") ~= nil
end
function Hints:step(state, budget)
  budget = budget or Hints.step_budget
  assert(type(budget) == "number" and budget >= 1 and budget <= Hints.step_budget and budget % 1 == 0)
  self.last_step_work = 0
  if not self:reconcile(state) or not self.job then return false end
  local job, document = self.job, state:document(self.scope)
  local cached_index, cached_row
  local function row(index)
    if index ~= cached_index then
      local entry = document:row(index)
      cached_index, cached_row = index, entry and entry.row
    end
    return cached_row
  end
  local function explicit_finish()
    if job.explicit then
      self:record(job.explicit.uri, job.explicit.first, job.at, "osc8")
      job.explicit = nil
    end
  end
  while self.job and self.last_step_work < budget do
    if #self.matches >= Hints.maximum_matches then self:finish_scan("match-limit"); break end
    if job.work >= Hints.maximum_cells then self:finish_scan("scan-limit"); break end
    job.work, self.last_step_work = job.work + 1, self.last_step_work + 1
    if job.phase == "trim" then
      local token, last = job.token, job.token.chars[#job.token.chars]
      if punctuation[last] or (last == ")" and token.round < 0) or (last == "]" and token.square < 0) then
        if last == ")" then token.round = token.round + 1 elseif last == "]" then token.square = token.square + 1 end
        token.chars[#token.chars] = nil
      else
        local uri = table.concat(token.chars)
        if plain_valid(uri) then self:record(uri, token.first, token.first + #uri, "text") end
        job.token, job.phase = nil, "scan"
      end
    elseif job.at >= job.finish then
      explicit_finish()
      -- At an artificial scan boundary a plain token may be incomplete.
      if job.token and not job.token.overlong and job.finish == document:count() * state.columns then job.phase = "trim"
      else self:finish_scan() end
    else
      local index, column = math.floor(job.at / state.columns) + 1, job.at % state.columns
      local current = row(index)
      if column == 0 and job.at ~= 0 and job.boundary ~= job.at and not row(index - 1).wrapped then
        job.boundary = job.at
        explicit_finish(); job.probe, job.previous = "", nil
        if job.token and not job.token.overlong then job.phase = "trim" else job.token = nil end
      else
        local cell = current.cells[column]
        local id, text = cell.hyperlink_id, cell.glyph
        if job.explicit and job.explicit.id ~= id then explicit_finish() end
        if id then
          job.token, job.probe, job.previous = nil, "", nil
          if not job.explicit then
            local link = state.hyperlinks[id]
            if link and Hyperlink.validate_uri(link.uri) then job.explicit = { id = id, uri = link.uri, first = job.at } end
          end
        elseif not cell.continuation then
          if job.token then
            if allowed(text) then
              if #job.token.chars < Hyperlink.maximum_uri_bytes then
                job.token.chars[#job.token.chars + 1] = text
                if text == "(" then job.token.round = job.token.round + 1 elseif text == ")" then job.token.round = job.token.round - 1 end
                if text == "[" then job.token.square = job.token.square + 1 elseif text == "]" then job.token.square = job.token.square - 1 end
              else job.token.overlong = true end
            elseif not job.token.overlong then job.phase = "trim"
            else job.token = nil end
          else
            local probe = job.probe .. (allowed(text) and text:lower() or " ")
            if #probe > 9 then probe = probe:sub(-9) end
            job.probe = probe
            for prefix in pairs(prefixes) do
              if probe:sub(-#prefix) == prefix and not word(probe:sub(-#prefix - 1, -#prefix - 1)) then
                job.token = { first = job.at - #prefix + 1, chars = {}, round = 0, square = 0 }
                -- Preserve source spelling, including an uppercase scheme.
                local original = job.original or ""
                original = (original .. text):sub(-#prefix)
                for offset = 1, #original do job.token.chars[offset] = original:sub(offset, offset) end
                job.probe = ""
                break
              end
            end
          end
          job.original = ((job.original or "") .. text):sub(-8)
        else job.token, job.probe = nil, "" end
        job.at = job.at + 1
      end
    end
  end
  return self.job == nil
end
function Hints:labels(state)
  if not self:reconcile(state) or self.job then return {} end
  local labels, base = {}, #Hints.alphabet
  local first, last = 1, #self.matches
  if self.paged then first, last = (self.page - 1) * base + 1, math.min(self.page * base, last) end
  for index = first, last do
    local code
    if self.paged or #self.matches <= base then code = Hints.alphabet:sub((index - 1) % base + 1, (index - 1) % base + 1)
    else
      local high, low = math.floor((index - 1) / base) + 1, (index - 1) % base + 1
      code = Hints.alphabet:sub(high, high) .. Hints.alphabet:sub(low, low)
    end
    if code:sub(1, #self.prefix) == self.prefix then
      local match = self.matches[index]
      labels[#labels + 1] = { code = code, first = match.first, finish = match.finish, index = index, selected = self.selected == index }
    end
  end
  return labels
end
function Hints:append(state, text)
  if not self:reconcile(state) or self.job then return false end
  text = text:lower()
  if not text:match("^[a-z]+$") or #self.prefix + #text > 2 then return false end
  local before = self.prefix
  self.prefix, self.selected = before .. text, nil
  local labels = self:labels(state)
  if #labels == 0 then self.prefix = before; return false end
  if #labels == 1 and labels[1].code == self.prefix then self.selected = labels[1].index end
  self:changed(); return true
end
function Hints:backspace()
  self.prefix, self.selected = self.prefix:sub(1, -2), nil
  self:changed()
end
function Hints:next_page(direction)
  if not self.paged then return false end
  local pages = math.ceil(#self.matches / #Hints.alphabet)
  self.page, self.prefix, self.selected = (self.page - 1 + direction) % pages + 1, "", nil
  self:changed(); return true
end
function Hints:target(state)
  if not self:reconcile(state) or self.job then return nil, self.status end
  local index = self.selected or (#self.matches == 1 and 1)
  if not index then return nil, "choose-label" end
  return { uri = self.matches[index].uri }, self.action
end
function Hints.title(view)
  local verb = view.action == "copy" and "copies" or "opens"
  local title = "Kiwi URLs [" .. (view.action or "open") .. "] "
  if view.selected_uri then
    local status = view.status ~= "ready" and ("; " .. (view.truncated and "Partial: " or "") .. view.status:gsub("[-_]", " ")) or ""
    return title .. view.selected_uri .. status .. " — Enter " .. verb .. "; Esc cancels"
  end
  if view.pending then return title .. "scanning; Esc cancels" end
  title = title .. view.count .. " links"
  if view.pages > 1 then title = title .. "; page " .. view.page .. "/" .. view.pages .. " (PgUp/PgDn)" end
  if view.status ~= "ready" then title = title .. " — " .. (view.truncated and "Partial: " or "") .. view.status:gsub("-", " ") end
  return title .. " — type label; Enter " .. verb .. "; Esc cancels"
end
function Hints:view(state)
  self:reconcile(state)
  return { active = self.active, status = self.status, pending = self.job ~= nil, action = self.action,
    count = #self.matches, prefix = self.prefix, revision = self.revision, truncated = self.truncated,
    page = self.page, pages = self.paged and math.ceil(#self.matches / #Hints.alphabet) or 1,
    selected_uri = self.selected and self.matches[self.selected] and self.matches[self.selected].uri }
end
return Hints
