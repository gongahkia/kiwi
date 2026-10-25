local Utf8 = require("kiwi.terminal.utf8")
local Grapheme = require("kiwi.unicode.grapheme")
local Width = require("kiwi.terminal.width")
local bit = require("bit")
local Decoration = require("kiwi.text.decoration")

local Layout = {}
Layout.__index = Layout

local function rgba(value)
  return value
end

local function add_cluster_offsets(offsets, text, byte_offset, column)
  local index = 1
  while index <= #text do
    offsets[byte_offset + index - 1] = column
    local first = text:byte(index)
    local length = first <= 0x7f and 1 or first <= 0xdf and 2 or first <= 0xef and 3 or 4
    index = index + length
  end
end

local function cluster_codepoints(cell)
  if cell.codepoints then return cell.codepoints end
  return { Utf8.decode_one(cell.glyph) }
end

local function cell_at(state, column, row)
  if state.cell_at_index then return state:cell_at_index(state:index(column, row)) end
  return state.cells[state:index(column, row)]
end

function Layout.new(font_system)
  return setmetatable({
    font_system = assert(font_system, "text layout needs a font system"),
    rows = {},
    generation = 0,
    stats = {},
  }, Layout)
end

function Layout:invalidate_all()
  self.generation = self.generation + 1
end

function Layout:set_font_system(font_system)
  self.font_system.glyph_cache:retain(self, {})
  self.font_system = assert(font_system, "text layout needs a font system")
  self:invalidate_all()
end

function Layout:destroy()
  if self.font_system.glyph_cache then self.font_system.glyph_cache:retain(self, {}) end
  self.rows = {}
end

function Layout:begin_frame()
  self.stats = {
    rows_invalidated = 0,
    rows_reshaped = 0,
    runs_reshaped = 0,
    runs_built = 0,
    clusters_examined = 0,
    codepoints_shaped = 0,
    glyphs_produced = 0,
    run_build_cpu_ms = 0,
    shaping_cpu_ms = 0,
    visible_runs = 0,
    visible_glyphs = 0,
    cache_hits = 0,
    cache_misses = 0,
    missing_clusters = 0,
  }
end

function Layout:row_is_dirty(state, row)
  if self.rows[row] == nil or self.rows[row].generation ~= self.generation or self.rows[row].text_generation ~= self.font_system.text_generation then return true end
  if self.rows[row].capacity_limited and self.rows[row].availability_generation ~= self.font_system.glyph_cache.availability_generation then return true end
  local damage = state.text_damage or state.damage
  if damage.full then return true end
  for _, range in ipairs(damage:ranges()) do
    local first_row = math.floor(range.first / state.columns)
    local last_row = math.floor((range.first + range.count - 1) / state.columns)
    if row >= first_row and row <= last_row then return true end
  end
  return false
end

function Layout:append_glyph(state, output, face, shaped, column, row, cell, pen_x)
  local cached, reason = self.font_system.glyph_cache:get_or_insert(face, shaped.glyph_id, self)
  if cached == nil then
    local fallback_face = self.font_system:face_for_cluster({ string.byte("?") }, cell.flags) or self.font_system.primary
    local fallback_id = fallback_face:glyph_index(string.byte("?"))
    cached = self.font_system.glyph_cache:get_or_insert(fallback_face, fallback_id, self)
    if cached == nil then
      self.stats.missing_clusters = self.stats.missing_clusters + 1
      return
    end
    reason = reason or "missing-glyph"
  end
  local bitmap = cached.bitmap
  local metrics = self.font_system.metrics
  output[#output + 1] = {
    x = (pen_x + shaped.x_offset / 64 + bitmap.left) / metrics.cell_width,
    y = row + (metrics.baseline - bitmap.top - shaped.y_offset / 64) / metrics.cell_height,
    width = bitmap.width / metrics.cell_width,
    height = bitmap.height / metrics.cell_height,
    u0 = cached.u0,
    v0 = cached.v0,
    u1 = cached.u1,
    v1 = cached.v1,
    fg = rgba(state.presentation_colors and select(1, state:presentation_colors(cell)) or cell.fg),
    flags = cell.flags,
    glyph_id = cached.glyph_id,
    face_id = cached.face_id,
    cluster_column = column,
    atlas_page = 0,
    cache_entry = cached,
    missing_reason = reason,
    row = row,
    shape_cluster = shaped.cluster,
    x_advance = shaped.x_advance,
    y_advance = shaped.y_advance,
    x_offset = shaped.x_offset,
    y_offset = shaped.y_offset,
  }
end

function Layout:shape_run(state, run, row, output)
  local started = os.clock()
  local shaped = run.face:shape(run.text, self.font_system.shape_options)
  self.stats.shaping_cpu_ms = self.stats.shaping_cpu_ms + (os.clock() - started) * 1000
  self.stats.runs_reshaped = self.stats.runs_reshaped + 1
  self.stats.codepoints_shaped = self.stats.codepoints_shaped + #run.codepoints
  self.stats.glyphs_produced = self.stats.glyphs_produced + #shaped
  local pen_x = run.column * self.font_system.metrics.cell_width
  for _, glyph in ipairs(shaped) do
    local column = run.offset_columns[glyph.cluster] or run.column
    local cell = run.cells[column]
    if cell then self:append_glyph(state, output, run.face, glyph, column, row, cell, pen_x) end
    pen_x = pen_x + glyph.x_advance / 64
  end
end

function Layout:build_runs(state, row)
  local started = os.clock()
  local runs, run = {}, nil
  local function flush()
    if run then
      run.text = table.concat(run.text_parts)
      runs[#runs + 1] = run
    end
    run = nil
  end
  for column = 0, state.columns - 1 do
    local cell = cell_at(state, column, row)
    if not cell.continuation and cell.glyph ~= " " and cell.glyph ~= "" then
      self.stats.clusters_examined = self.stats.clusters_examined + 1
      local codepoints = cluster_codepoints(cell)
      local face = self.font_system:face_for_cluster(codepoints, cell.flags)
      local width = cell.width or 1
      if face == nil then
        flush()
        self.stats.missing_clusters = self.stats.missing_clusters + 1
      elseif run and (run.face ~= face or run.next_column ~= column) then
        flush()
      end
      if face then
        if run == nil then
          run = { face = face, text_parts = {}, byte_length = 0, offset_columns = {}, cells = {}, column = column, next_column = column, codepoints = {} }
        end
        local display_text = cell.display_text or cell.glyph
        local byte_offset = run.byte_length
        run.text_parts[#run.text_parts + 1] = display_text
        run.byte_length = run.byte_length + #display_text
        add_cluster_offsets(run.offset_columns, display_text, byte_offset, column)
        run.cells[column] = cell
        for _, codepoint in ipairs(codepoints) do run.codepoints[#run.codepoints + 1] = codepoint end
        run.next_column = column + width
      end
    else
      flush()
    end
  end
  flush()
  self.stats.runs_built = self.stats.runs_built + #runs
  self.stats.run_build_cpu_ms = self.stats.run_build_cpu_ms + (os.clock() - started) * 1000
  return runs
end

function Layout:shape_runs(state, runs, row)
  local output = {}
  for _, run in ipairs(runs) do self:shape_run(state, run, row, output) end
  return output
end

function Layout:shape_row(state, row)
  local output = self:shape_runs(state, self:build_runs(state, row), row)
  for column = 0, state.columns - 1 do self:append_decorations(state, output, column, row, cell_at(state, column, row)) end
  return output
end

function Layout:append_decorations(state, output, column, row, cell)
  local flags = cell.flags or 0
  if bit.band(flags, 0x80) ~= 0 or bit.band(flags, 0x320) == 0 then return end
  local system = self.font_system
  if not system.decoration_face then system.decoration_face = Decoration.new(system.metrics) end
  local foreground = state.presentation_colors and select(1, state:presentation_colors(cell)) or cell.fg
  local function append(style, color, hyperlink)
    local cached = system.glyph_cache:get_or_insert(system.decoration_face, style, self)
    if not cached then return end
    output[#output + 1] = {
      x = column, y = row, width = 1, height = 1,
      u0 = cached.u0, v0 = cached.v0, u1 = cached.u1, v1 = cached.v1,
      fg = color, flags = bit.bor(bit.band(flags, 0x08), hyperlink and Decoration.hyperlink_flag or 0),
      glyph_id = cached.glyph_id, face_id = 0, cluster_column = column,
      atlas_page = 0, cache_entry = cached, row = row, decoration = style,
    }
  end
  if bit.band(flags, 0x20) ~= 0 then append(cell.underline_style or 1, cell.underline_color or foreground) end
  if bit.band(flags, 0x100) ~= 0 then append(Decoration.strike, foreground) end
  if bit.band(flags, 0x200) ~= 0 then append(1, foreground, true) end
end

function Layout:append_preedit(state, output)
  local preedit = state.ime_preedit
  if type(preedit) ~= "table" or type(preedit.text) ~= "string" or #preedit.text == 0 then return end
  if type(preedit.column) ~= "number" or type(preedit.row) ~= "number" then return end
  local codepoints = {}
  local valid = true
  local decoder = Utf8.Decoder.new(function(codepoint, _, replaced)
    if replaced then valid = false else codepoints[#codepoints + 1] = codepoint end
  end)
  for index = 1, #preedit.text do decoder:feed_byte(preedit.text:byte(index)) end
  decoder:finish()
  if not valid or #codepoints == 0 then return end

  local column = math.max(0, math.floor(preedit.column))
  local row = math.max(0, math.floor(preedit.row))
  local metrics = self.font_system.metrics
  local cell = { bg = state.default_cell.bg, fg = state.default_cell.fg, flags = 0x20 }
  for _, cluster in ipairs(Grapheme.segment(codepoints)) do
    if column >= state.columns then
      column = 0
      row = row + 1
    end
    if row >= state.rows then break end
    local face = self.font_system:face_for_cluster(cluster)
    local cluster_width = Width.columns(cluster, state.width_policy)
    if face ~= nil then
      local text_parts = {}
      for _, codepoint in ipairs(cluster) do text_parts[#text_parts + 1] = Utf8.encode(codepoint) end
      local shaped = face:shape(table.concat(text_parts), self.font_system.shape_options)
      local pen_x = column * metrics.cell_width
      for _, glyph in ipairs(shaped) do
        self:append_glyph(state, output, face, glyph, column, row, cell, pen_x)
        pen_x = pen_x + glyph.x_advance / 64
      end
      self.stats.glyphs_produced = self.stats.glyphs_produced + #shaped
    end
    for offset = 0, math.min(cluster_width, state.columns - column) - 1 do
      self:append_decorations(state, output, column + offset, row, cell)
    end
    column = column + cluster_width
  end
end

function Layout:update(state)
  self:begin_frame()
  local cache = self.font_system.glyph_cache
  local dirty, retained = {}, {}
  for row = 0, state.rows - 1 do
    dirty[row] = self:row_is_dirty(state, row)
    if not dirty[row] then
      for _, glyph in ipairs(self.rows[row].glyphs) do retained[#retained + 1] = glyph end
    end
  end
  cache:retain(self, retained)
  for row in pairs(self.rows) do if row >= state.rows then self.rows[row] = nil end end
  local glyphs = {}
  for row = 0, state.rows - 1 do
    if dirty[row] then
      self.stats.rows_invalidated = self.stats.rows_invalidated + 1
      self.stats.cache_misses = self.stats.cache_misses + 1
      local runs_before = self.stats.runs_reshaped
      local failures_before = cache.stats.capacity_failures
      local glyphs = self:shape_row(state, row)
      self.rows[row] = {
        generation = self.generation,
        text_generation = self.font_system.text_generation,
        glyphs = glyphs,
        runs = self.stats.runs_reshaped - runs_before,
        capacity_limited = cache.stats.capacity_failures > failures_before,
        availability_generation = cache.availability_generation,
      }
      self.stats.rows_reshaped = self.stats.rows_reshaped + 1
    else
      self.stats.cache_hits = self.stats.cache_hits + 1
    end
    self.stats.visible_runs = self.stats.visible_runs + self.rows[row].runs
    for _, glyph in ipairs(self.rows[row].glyphs) do glyphs[#glyphs + 1] = glyph end
  end
  self:append_preedit(state, glyphs)
  self.stats.visible_glyphs = #glyphs
  if state.text_damage then state.text_damage:clear() end
  return glyphs
end

return Layout
