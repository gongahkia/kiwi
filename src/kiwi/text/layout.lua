local Utf8 = require("kiwi.terminal.utf8")

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

function Layout:begin_frame()
  self.stats = {
    rows_invalidated = 0,
    rows_reshaped = 0,
    runs_reshaped = 0,
    codepoints_shaped = 0,
    glyphs_produced = 0,
    shaping_cpu_ms = 0,
    cache_hits = 0,
    cache_misses = 0,
    missing_clusters = 0,
  }
end

function Layout:row_is_dirty(state, row)
  if self.rows[row] == nil or self.rows[row].generation ~= self.generation or self.rows[row].text_generation ~= self.font_system.text_generation then return true end
  if state.damage.full then return true end
  for _, range in ipairs(state.damage:ranges()) do
    local first_row = math.floor(range.first / state.columns)
    local last_row = math.floor((range.first + range.count - 1) / state.columns)
    if row >= first_row and row <= last_row then return true end
  end
  return false
end

function Layout:append_glyph(output, face, shaped, column, row, cell, pen_x)
  local cached, reason = self.font_system.glyph_cache:get_or_insert(face, shaped.glyph_id)
  if cached == nil then
    local fallback_id = self.font_system.primary:glyph_index(string.byte("?"))
    cached = self.font_system.glyph_cache:get_or_insert(self.font_system.primary, fallback_id)
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
    fg = rgba(cell.fg),
    flags = cell.flags,
    glyph_id = cached.glyph_id,
    face_id = cached.face_id,
    cluster_column = column,
    atlas_page = 0,
    missing_reason = reason,
    row = row,
    shape_cluster = shaped.cluster,
    x_advance = shaped.x_advance,
    y_advance = shaped.y_advance,
    x_offset = shaped.x_offset,
    y_offset = shaped.y_offset,
  }
end

function Layout:shape_run(run, row, output)
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
    if cell then self:append_glyph(output, run.face, glyph, column, row, cell, pen_x) end
    pen_x = pen_x + glyph.x_advance / 64
  end
end

function Layout:shape_row(state, row)
  local output, run = {}, nil
  local function flush()
    if run then
      run.text = table.concat(run.text_parts)
      self:shape_run(run, row, output)
    end
    run = nil
  end
  for column = 0, state.columns - 1 do
    local cell = cell_at(state, column, row)
    if not cell.continuation and cell.glyph ~= " " and cell.glyph ~= "" then
      local codepoints = cluster_codepoints(cell)
      local face = self.font_system:face_for_cluster(codepoints)
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
  return output
end

function Layout:update(state)
  self:begin_frame()
  local glyphs = {}
  for row = 0, state.rows - 1 do
    if self:row_is_dirty(state, row) then
      self.stats.rows_invalidated = self.stats.rows_invalidated + 1
      self.stats.cache_misses = self.stats.cache_misses + 1
      self.rows[row] = { generation = self.generation, text_generation = self.font_system.text_generation, glyphs = self:shape_row(state, row) }
      self.stats.rows_reshaped = self.stats.rows_reshaped + 1
    else
      self.stats.cache_hits = self.stats.cache_hits + 1
    end
    for _, glyph in ipairs(self.rows[row].glyphs) do glyphs[#glyphs + 1] = glyph end
  end
  return glyphs
end

return Layout
