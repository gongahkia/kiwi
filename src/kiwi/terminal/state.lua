local Attributes = require("kiwi.terminal.attributes")
local Damage = require("kiwi.terminal.damage")
local Grapheme = require("kiwi.unicode.grapheme")
local Properties = require("kiwi.unicode.properties")
local Screen = require("kiwi.terminal.screen")
local Scrollback = require("kiwi.terminal.scrollback")
local Selection = require("kiwi.input.selection")
local Utf8 = require("kiwi.terminal.utf8")
local Width = require("kiwi.terminal.width")

local State = {}
State.__index = State

State.flags = Attributes.flags
local GCB = Properties.grapheme_break
local ascii_codepoints = {}
for codepoint = 0x20, 0x7e do ascii_codepoints[codepoint] = { codepoint } end

local function copy_cell(destination, source)
  destination.glyph = source.glyph
  destination.fg = source.fg
  destination.bg = source.bg
  destination.flags = source.flags
  destination.codepoints = source.codepoints
  destination.width = source.width
  destination.continuation = source.continuation
  destination.anchor_column = source.anchor_column
  destination.display_text = source.display_text
end

local function same_codepoints(left, right)
  if left == right then return true end
  if left == nil or right == nil or #left ~= #right then return false end
  for index = 1, #left do
    if left[index] ~= right[index] then return false end
  end
  return true
end

local function same_cell(left, right)
  return left.glyph == right.glyph
    and left.fg == right.fg
    and left.bg == right.bg
    and left.flags == right.flags
    and left.width == right.width
    and left.continuation == right.continuation
    and left.anchor_column == right.anchor_column
    and left.display_text == right.display_text
    and same_codepoints(left.codepoints, right.codepoints)
end

local function clamp(value, lower, upper)
  return math.max(lower, math.min(value, upper))
end

function State.new(columns, rows, options)
  assert(columns > 0 and rows > 0, "terminal dimensions must be positive")
  options = options or {}
  local self = setmetatable({
    columns = columns,
    rows = rows,
    next_line_id = 0,
    default_cell = { glyph = " ", fg = Attributes.default_foreground, bg = Attributes.default_background, flags = 0, width = 1 },
    damage = Damage.new(columns * rows),
    text_damage = Damage.new(columns * rows),
    modes = {
      autowrap = true,
      origin = false,
      insert = false,
      cursor_visible = true,
      cursor_style = 1,
      application_cursor = false,
      bracketed_paste = false,
      synchronized_output = false,
      mouse_tracking = "none",
      mouse_normal = false,
      mouse_button = false,
      mouse_any = false,
      mouse_sgr = false,
      focus_reporting = false,
      mouse_generation = 0,
      keyboard_flags = 0,
    },
    tab_stops = {},
    scrollback = Scrollback.new(options.scrollback_limit or 2000),
    selection = Selection.new(),
    history_offset = 0,
    title = nil,
    responses = {},
    grapheme_context_storage = {},
    text_counters = options.text_counters,
    width_policy = Width.normalize_policy({
      ambiguous_width = options.ambiguous_width == nil and Width.default_policy.ambiguous_width or options.ambiguous_width,
      private_use_width = options.private_use_width == nil and Width.default_policy.private_use_width or options.private_use_width,
    }),
    max_cluster_codepoints = options.max_cluster_codepoints or 64,
    stats = {
      mutations = 0,
      bells = 0,
      text = { over_limit_clusters = 0, width_change_clamped = 0 },
      unknown = { csi = 0, esc = 0, osc = 0, string = 0 },
      unknown_samples = {},
    },
  }, State)
  assert(self.max_cluster_codepoints >= 8, "terminal max_cluster_codepoints must be at least 8")
  self.primary = self:new_screen()
  self.alternate = self:new_screen()
  self.primary.attributes = Attributes.default()
  self.alternate.attributes = Attributes.default()
  self.active_screen = self.primary
  self.cursor = self.active_screen.cursor
  self.cells = setmetatable({}, {
    __index = function(_, index)
      return self:cell_at_index(index)
    end,
  })
  self:reset_tab_stops()
  self.damage:mark_all()
  self.text_damage:mark_all()
  return self
end

function State:blank_cell()
  return { glyph = " ", fg = self.default_cell.fg, bg = self.default_cell.bg, flags = 0, width = 1 }
end

function State:new_screen()
  return Screen.new(self.columns, self.rows, function()
    return self:blank_cell()
  end, function()
    self.next_line_id = self.next_line_id + 1
    return self.next_line_id
  end)
end

function State:cell_from_attributes(glyph, metadata)
  local foreground, background, flags = Attributes.resolve(self.active_screen.attributes)
  metadata = metadata or {}
  return {
    glyph = glyph,
    fg = foreground,
    bg = background,
    flags = flags,
    codepoints = metadata.codepoints,
    width = metadata.width or 1,
    continuation = metadata.continuation,
    anchor_column = metadata.anchor_column,
    display_text = metadata.display_text,
  }
end

function State:ascii_cell(glyph, codepoints)
  local foreground, background, flags = Attributes.resolve(self.active_screen.attributes)
  return {
    glyph = glyph,
    fg = foreground,
    bg = background,
    flags = flags,
    codepoints = codepoints,
    width = 1,
    display_text = glyph,
  }
end

function State:set_ascii_cell(column, row, glyph, codepoints)
  local foreground, background, flags = Attributes.resolve(self.active_screen.attributes)
  local target = self.active_screen:get(column, row)
  if target.glyph == glyph
    and target.fg == foreground
    and target.bg == background
    and target.flags == flags
    and target.codepoints == codepoints
    and target.width == 1
    and not target.continuation
    and target.anchor_column == nil
    and target.display_text == glyph then
    return false
  end
  target.glyph = glyph
  target.fg = foreground
  target.bg = background
  target.flags = flags
  target.codepoints = codepoints
  target.width = 1
  target.continuation = nil
  target.anchor_column = nil
  target.display_text = glyph
  self:mark_changed(column, row)
  local counters = self.text_counters
  if counters then counters.cells_changed = (counters.cells_changed or 0) + 1 end
  return true
end

function State:reset_tab_stops()
  self.tab_stops = {}
  for column = 8, self.columns - 1, 8 do
    self.tab_stops[column] = true
  end
end

function State:index(column, row)
  assert(column >= 0 and column < self.columns, "column out of bounds")
  assert(row >= 0 and row < self.rows, "row out of bounds")
  return row * self.columns + column
end

function State:position(index)
  assert(index >= 0 and index < self.columns * self.rows, "cell index out of bounds")
  return index % self.columns, math.floor(index / self.columns)
end

function State:visible_row(row)
  if self.active_screen ~= self.primary or self.history_offset == 0 then
    return self.active_screen.rows[row]
  end
  local first = self.scrollback:size() + self.rows - self.history_offset - self.rows
  local source = first + row
  if source < self.scrollback:size() then
    return self.scrollback:get(source + 1)
  end
  return self.primary.rows[source - self.scrollback:size()]
end

function State:selection_scope()
  return self.active_screen == self.primary and "primary" or "alternate"
end

function State:selection_rows(scope)
  local rows = {}
  if scope == "primary" then
    for index = 1, self.scrollback:size() do
      local row = self.scrollback:get(index)
      rows[#rows + 1] = { line_id = row.line_id, row = row }
    end
    for index = 0, self.rows - 1 do
      local row = self.primary.rows[index]
      rows[#rows + 1] = { line_id = row.line_id, row = row }
    end
  elseif scope == "alternate" then
    for index = 0, self.rows - 1 do
      local row = self.alternate.rows[index]
      rows[#rows + 1] = { line_id = row.line_id, row = row }
    end
  end
  return rows
end

function State:reconcile_selection()
  local scope = self.selection.scope
  if scope then self.selection:reconcile(self:selection_rows(scope), self.columns) end
end

local function selection_coordinate(value, upper)
  if type(value) ~= "number" or value ~= value then return 0 end
  return clamp(math.floor(value), 0, upper)
end

function State:selection_endpoint(row, column)
  row = selection_coordinate(row, self.rows - 1)
  local visible = self:visible_row(row)
  return {
    column = selection_coordinate(column, self.columns),
    line_id = visible.line_id,
  }
end

local function selection_cluster_bounds(row, column, columns)
  local cell = row.cells[column]
  local start = cell and cell.continuation and cell.anchor_column or column
  local anchor = row.cells[start]
  local width = anchor and anchor.width or 1
  return start, math.min(columns, start + math.max(1, width))
end

function State:selection_cell_bounds(row, column)
  row = selection_coordinate(row, self.rows - 1)
  column = selection_coordinate(column, self.columns - 1)
  local start, finish = selection_cluster_bounds(self:visible_row(row), column, self.columns)
  return { finish = finish, row = row, start = start }
end

local function selection_word_cell(cell)
  local codepoint = cell and cell.codepoints and cell.codepoints[1]
  return codepoint and ((codepoint >= 0x30 and codepoint <= 0x39) or (codepoint >= 0x41 and codepoint <= 0x5a) or (codepoint >= 0x61 and codepoint <= 0x7a) or codepoint == 0x5f or codepoint >= 0x80)
end

function State:selection_word_bounds(row, column)
  local bounds = self:selection_cell_bounds(row, column)
  local visible = self:visible_row(bounds.row)
  if not selection_word_cell(visible.cells[bounds.start]) then return bounds end
  while bounds.start > 0 do
    local previous_start, previous_finish = selection_cluster_bounds(visible, bounds.start - 1, self.columns)
    if previous_finish ~= bounds.start or not selection_word_cell(visible.cells[previous_start]) then break end
    bounds.start = previous_start
  end
  while bounds.finish < self.columns do
    local next_start, next_finish = selection_cluster_bounds(visible, bounds.finish, self.columns)
    if next_start ~= bounds.finish or not selection_word_cell(visible.cells[next_start]) then break end
    bounds.finish = next_finish
  end
  return bounds
end

function State:selection_precedes(left_row, left_column, right_row, right_column)
  local scope = self:selection_scope()
  local positions = {}
  for index, entry in ipairs(self:selection_rows(scope)) do positions[entry.line_id] = index end
  local left = self:selection_endpoint(left_row, left_column)
  local right = self:selection_endpoint(right_row, right_column)
  local left_index = positions[left.line_id]
  local right_index = positions[right.line_id]
  return left_index < right_index or (left_index == right_index and left.column <= right.column)
end

function State:set_selection(anchor_row, anchor_column, focus_row, focus_column)
  local scope = self:selection_scope()
  return self.selection:set(scope, self:selection_endpoint(anchor_row, anchor_column), self:selection_endpoint(focus_row, focus_column), self:selection_rows(scope), self.columns)
end

function State:clear_selection()
  self.selection:clear()
end

function State:selection_view()
  local scope = self.selection.scope
  if scope == nil then return { active = false, empty = true, visible = false } end
  return self.selection:view(self:selection_rows(scope), self.columns, self:selection_scope())
end

function State:cell_at_index(index)
  local column, row = self:position(index)
  local visible = self:visible_row(row)
  return visible and visible.cells[column] or self.default_cell
end

function State:get(column, row)
  return self.active_screen:get(column, row)
end

function State:mark_changed(column, row)
  local index = self:index(column, row)
  self.damage:mark(index)
  self.text_damage:mark(index)
  self.stats.mutations = self.stats.mutations + 1
end

function State:set_cell(column, row, cell)
  local target = self.active_screen:get(column, row)
  if same_cell(target, cell) then
    return false
  end
  copy_cell(target, cell)
  self:mark_changed(column, row)
  local counters = self.text_counters
  if counters then counters.cells_changed = (counters.cells_changed or 0) + 1 end
  return true
end

function State:mark_region(top, bottom)
  local first = top * self.columns
  local count = (bottom - top + 1) * self.columns
  self.damage:mark_range(first, count)
  self.text_damage:mark_range(first, count)
end

function State:sync_cursor_visibility()
  self.cursor.visible = self.modes.cursor_visible and self.history_offset == 0
end

function State:clear_grapheme_context()
  self.grapheme_context = nil
end

function State:set_cursor(column, row, preserve_grapheme_context)
  local cursor = self.active_screen.cursor
  local old_column, old_row = cursor.column, cursor.row
  cursor.column = clamp(column, 0, self.columns - 1)
  cursor.row = clamp(row, 0, self.rows - 1)
  cursor.pending_wrap = false
  if not preserve_grapheme_context then
    self:clear_grapheme_context()
  end
  self:sync_cursor_visibility()
  self.damage:mark(self:index(old_column, old_row))
  self.damage:mark(self:index(cursor.column, cursor.row))
end

function State:save_cursor()
  local cursor = self.active_screen.cursor
  self.active_screen.saved_cursor = { column = cursor.column, row = cursor.row, attributes = Attributes.copy(self.active_screen.attributes) }
end

function State:restore_cursor()
  local saved = self.active_screen.saved_cursor
  self.active_screen.attributes = Attributes.copy(saved.attributes or Attributes.default())
  self:set_cursor(saved.column, saved.row)
end

function State:scroll_up(count)
  self:clear_grapheme_context()
  local screen = self.active_screen
  local top, bottom = screen.top_margin, screen.bottom_margin
  count = clamp(count or 1, 1, bottom - top + 1)
  local preserve = screen == self.primary and top == 0 and bottom == self.rows - 1 and function(row)
    self.scrollback:push(row)
  end or nil
  screen:scroll_up(top, bottom, count, preserve)
  self:mark_region(top, bottom)
  self.stats.mutations = self.stats.mutations + (bottom - top + 1) * self.columns
  self:reconcile_selection()
end

function State:scroll_down(count)
  self:clear_grapheme_context()
  local screen = self.active_screen
  local top, bottom = screen.top_margin, screen.bottom_margin
  count = clamp(count or 1, 1, bottom - top + 1)
  screen:scroll_down(top, bottom, count)
  self:mark_region(top, bottom)
  self.stats.mutations = self.stats.mutations + (bottom - top + 1) * self.columns
end

function State:index_line()
  local cursor = self.active_screen.cursor
  cursor.pending_wrap = false
  if cursor.row == self.active_screen.bottom_margin then
    self:scroll_up(1)
  elseif cursor.row < self.rows - 1 then
    self:set_cursor(cursor.column, cursor.row + 1)
  end
end

function State:reverse_index()
  local cursor = self.active_screen.cursor
  cursor.pending_wrap = false
  if cursor.row == self.active_screen.top_margin then
    self:scroll_down(1)
  elseif cursor.row > 0 then
    self:set_cursor(cursor.column, cursor.row - 1)
  end
end

function State:line_feed()
  self:index_line()
end

function State:carriage_return()
  self:set_cursor(0, self.active_screen.cursor.row)
end

function State:backspace()
  local cursor = self.active_screen.cursor
  self:set_cursor(math.max(0, cursor.column - 1), cursor.row)
end

function State:tab()
  local cursor = self.active_screen.cursor
  local target = self.columns - 1
  for column = cursor.column + 1, self.columns - 1 do
    if self.tab_stops[column] then
      target = column
      break
    end
  end
  self:set_cursor(target, cursor.row)
end

local function copied_codepoints(codepoints, extra)
  local result = {}
  for index, codepoint in ipairs(codepoints or {}) do
    result[index] = codepoint
  end
  if extra then result[#result + 1] = extra end
  return result
end

function State:current_grapheme_cluster()
  local context = self.grapheme_context
  if context == nil or context.screen ~= self.active_screen then return nil end
  local row = context.screen.rows[context.row]
  local cell = row and row.cells[context.column]
  if cell == nil or cell.continuation or cell.codepoints ~= context.codepoints then
    self:clear_grapheme_context()
    return nil
  end
  return cell, context
end

function State:continuation_cell(anchor_column)
  return self:cell_from_attributes("", { width = 0, continuation = true, anchor_column = anchor_column })
end

function State:clear_cluster_at(column, row)
  local screen = self.active_screen
  local cell = screen:get(column, row)
  local anchor_column = cell.continuation and cell.anchor_column or column
  local anchor = screen:get(anchor_column, row)
  if anchor.continuation then
    self:set_cell(column, row, self:blank_cell())
    return
  end
  local width = anchor.width
  self:set_cell(anchor_column, row, self:blank_cell())
  if width == 2 and anchor_column + 1 < self.columns then
    self:set_cell(anchor_column + 1, row, self:blank_cell())
  end
end

function State:prepare_cluster_write(width)
  local screen = self.active_screen
  local cursor = screen.cursor
  if cursor.pending_wrap then
    if self.modes.autowrap then
      screen.rows[cursor.row].wrapped = true
      self:carriage_return()
      self:index_line()
      cursor = screen.cursor
    end
    cursor.pending_wrap = false
  end
  if width == 2 and self.columns < 2 then
    self.stats.text.width_change_clamped = self.stats.text.width_change_clamped + 1
    width = 1
  elseif width == 2 and cursor.column == self.columns - 1 then
    if self.modes.autowrap then
      screen.rows[cursor.row].wrapped = true
      self:carriage_return()
      self:index_line()
      cursor = screen.cursor
    else
      self.stats.text.width_change_clamped = self.stats.text.width_change_clamped + 1
      width = 1
    end
  end
  if self.modes.insert then
    self:insert_characters(1)
  end
  return cursor, width
end

function State:write_new_cluster(glyph, codepoint)
  self:clear_grapheme_context()
  local codepoints = { codepoint }
  local gcb = Properties.gcb(codepoint)
  local counters = self.text_counters
  if counters then
    counters.unicode_property_lookups = (counters.unicode_property_lookups or 0) + 1
    counters.width_policy_calls = (counters.width_policy_calls or 0) + 1
    counters.clusters_created = (counters.clusters_created or 0) + 1
  end
  local leading = gcb == Properties.grapheme_break.extend
    or gcb == Properties.grapheme_break.zwj
    or gcb == Properties.grapheme_break.spacing_mark
  local display_text = leading and Utf8.encode(0x25cc) .. glyph or glyph
  local cursor, width = self:prepare_cluster_write(Width.columns(codepoints, self.width_policy))
  local column, row = cursor.column, cursor.row
  local occupied = self.active_screen:get(column, row)
  if occupied.continuation or occupied.width == 2 then self:clear_cluster_at(column, row) end
  if width == 2 and column + 1 < self.columns then
    local next_cell = self.active_screen:get(column + 1, row)
    if next_cell.continuation or next_cell.width == 2 then self:clear_cluster_at(column + 1, row) end
  end
  local anchor = self:cell_from_attributes(glyph, {
    codepoints = codepoints,
    width = width,
    display_text = display_text,
  })
  self:set_cell(column, row, anchor)
  if width == 2 and column + 1 < self.columns then
    self:set_cell(column + 1, row, self:continuation_cell(column))
  end
  local context = self.grapheme_context_storage
  context.screen = self.active_screen
  context.row = row
  context.column = column
  context.codepoints = codepoints
  context.last_gcb = gcb
  self.grapheme_context = context
  if column + width - 1 == self.columns - 1 then
    self:set_cursor(self.columns - 1, row, true)
    cursor.pending_wrap = true
  else
    self:set_cursor(column + width, row, true)
  end
end

function State:extend_grapheme_cluster(cell, context, glyph, codepoint)
  local codepoints = copied_codepoints(context.codepoints, codepoint)
  local old_width = cell.width
  local new_width = Width.columns(codepoints, self.width_policy)
  local counters = self.text_counters
  if counters then
    counters.unicode_property_lookups = (counters.unicode_property_lookups or 0) + 1
    counters.width_policy_calls = (counters.width_policy_calls or 0) + 1
    counters.clusters_extended = (counters.clusters_extended or 0) + 1
  end
  local updated = {
    glyph = cell.glyph .. glyph,
    fg = cell.fg,
    bg = cell.bg,
    flags = cell.flags,
    codepoints = codepoints,
    width = old_width,
    display_text = (cell.display_text or cell.glyph) .. glyph,
  }
  local column, row = context.column, context.row
  local cursor = self.active_screen.cursor
  if old_width == 1 and new_width == 2 then
    local next_cell = column + 1 < self.columns and self.active_screen:get(column + 1, row) or nil
    if next_cell and next_cell.glyph == " " and not next_cell.continuation then
      updated.width = 2
      self:set_cell(column, row, updated)
      self:set_cell(column + 1, row, self:continuation_cell(column))
      if cursor.row == row and cursor.column == column + 1 then
        self:set_cursor(math.min(self.columns - 1, column + 2), row, true)
        cursor.pending_wrap = column + 1 == self.columns - 1
      end
    else
      self.stats.text.width_change_clamped = self.stats.text.width_change_clamped + 1
      self:set_cell(column, row, updated)
    end
  elseif old_width == 2 and new_width == 1 then
    updated.width = 1
    self:set_cell(column, row, updated)
    self:set_cell(column + 1, row, self:blank_cell())
    if cursor.row == row and (cursor.column == column + 2 or cursor.pending_wrap) then
      self:set_cursor(column + 1, row, true)
    end
  else
    self:set_cell(column, row, updated)
  end
  context.codepoints = codepoints
  context.last_gcb = Properties.gcb(codepoint)
  self.grapheme_context = context
end

function State:write_ascii_cluster(glyph, codepoint)
  self:clear_grapheme_context()
  local counters = self.text_counters
  if counters then
    counters.ascii_fast_path = (counters.ascii_fast_path or 0) + 1
    counters.clusters_created = (counters.clusters_created or 0) + 1
  end
  local cursor = self:prepare_cluster_write(1)
  local column, row = cursor.column, cursor.row
  local occupied = self.active_screen:get(column, row)
  if occupied.continuation or occupied.width == 2 then self:clear_cluster_at(column, row) end
  local codepoints = ascii_codepoints[codepoint]
  self:set_ascii_cell(column, row, glyph, codepoints)
  local context = self.grapheme_context_storage
  context.screen = self.active_screen
  context.row = row
  context.column = column
  context.codepoints = codepoints
  context.last_gcb = GCB.other
  self.grapheme_context = context
  if column == self.columns - 1 then
    cursor.pending_wrap = true
  else
    self:set_cursor(column + 1, row, true)
  end
end

function State:write_codepoint(glyph, codepoint)
  codepoint = codepoint or Utf8.decode_one(glyph)
  local counters = self.text_counters
  if counters then counters.unicode_scalars = (counters.unicode_scalars or 0) + 1 end
  local context = self.grapheme_context
  if codepoint >= 0x20 and codepoint <= 0x7e and (context == nil or context.last_gcb ~= GCB.prepend) then
    self:write_ascii_cluster(glyph, codepoint)
    return
  end
  local cell, context = self:current_grapheme_cluster()
  if cell and not Grapheme.should_break(context.codepoints, codepoint) then
    if counters then counters.grapheme_boundary_checks = (counters.grapheme_boundary_checks or 0) + 1 end
    if #context.codepoints < self.max_cluster_codepoints then
      self:extend_grapheme_cluster(cell, context, glyph, codepoint)
      return
    end
    self.stats.text.over_limit_clusters = self.stats.text.over_limit_clusters + 1
  end
  self:write_new_cluster(glyph, codepoint)
end

function State:erase_cell(column, row)
  self:clear_grapheme_context()
  self:clear_cluster_at(column, row)
  return self:set_cell(column, row, self:cell_from_attributes(" "))
end

function State:erase_in_line(mode)
  local cursor = self.active_screen.cursor
  local first, last = cursor.column, self.columns - 1
  if mode == 1 then
    first, last = 0, cursor.column
  elseif mode == 2 then
    first, last = 0, self.columns - 1
  end
  for column = first, last do
    self:erase_cell(column, cursor.row)
  end
  cursor.pending_wrap = false
end

function State:erase_in_display(mode)
  local cursor = self.active_screen.cursor
  if mode == 2 or mode == 3 then
    for row = 0, self.rows - 1 do
      for column = 0, self.columns - 1 do
        self:erase_cell(column, row)
      end
    end
    if mode == 3 and self.active_screen == self.primary then
      self.scrollback:clear()
      self.history_offset = 0
      self:reconcile_selection()
    end
  elseif mode == 1 then
    for row = 0, cursor.row do
      local last = row == cursor.row and cursor.column or self.columns - 1
      for column = 0, last do
        self:erase_cell(column, row)
      end
    end
  else
    for row = cursor.row, self.rows - 1 do
      local first = row == cursor.row and cursor.column or 0
      for column = first, self.columns - 1 do
        self:erase_cell(column, row)
      end
    end
  end
  cursor.pending_wrap = false
end

function State:erase_characters(count)
  local cursor = self.active_screen.cursor
  local last = math.min(self.columns - 1, cursor.column + (count or 1) - 1)
  for column = cursor.column, last do
    self:erase_cell(column, cursor.row)
  end
  cursor.pending_wrap = false
end

function State:normalize_row(row_index)
  local row = self.active_screen.rows[row_index]
  for column = 0, self.columns - 1 do
    local cell = row.cells[column]
    if cell.continuation then
      local anchor = column > 0 and row.cells[column - 1] or nil
      if anchor == nil or anchor.continuation or anchor.width ~= 2 then
        self:set_cell(column, row_index, self:blank_cell())
      elseif cell.anchor_column ~= column - 1 then
        self:set_cell(column, row_index, {
          glyph = "",
          fg = anchor.fg,
          bg = anchor.bg,
          flags = anchor.flags,
          width = 0,
          continuation = true,
          anchor_column = column - 1,
        })
      end
    elseif cell.width == 2 then
      if column == self.columns - 1 then
        self:set_cell(column, row_index, {
          glyph = cell.glyph,
          fg = cell.fg,
          bg = cell.bg,
          flags = cell.flags,
          codepoints = cell.codepoints,
          width = 1,
          display_text = cell.display_text,
        })
      else
        local next_cell = row.cells[column + 1]
        if not next_cell.continuation or next_cell.anchor_column ~= column then
          self:set_cell(column + 1, row_index, {
            glyph = "",
            fg = cell.fg,
            bg = cell.bg,
            flags = cell.flags,
            width = 0,
            continuation = true,
            anchor_column = column,
          })
        end
      end
    end
  end
end

function State:normalize_screen(screen)
  local previous = self.active_screen
  self.active_screen = screen
  for row = 0, self.rows - 1 do
    self:normalize_row(row)
  end
  self.active_screen = previous
end

function State:insert_characters(count)
  self:clear_grapheme_context()
  local cursor = self.active_screen.cursor
  local row = self.active_screen.rows[cursor.row]
  count = math.min(count or 1, self.columns - cursor.column)
  for column = self.columns - 1, cursor.column + count, -1 do
    copy_cell(row.cells[column], row.cells[column - count])
  end
  for column = cursor.column, cursor.column + count - 1 do
    copy_cell(row.cells[column], self:cell_from_attributes(" "))
  end
  self:normalize_row(cursor.row)
  local first = self:index(cursor.column, cursor.row)
  local count = self.columns - cursor.column
  self.damage:mark_range(first, count)
  self.text_damage:mark_range(first, count)
  cursor.pending_wrap = false
end

function State:delete_characters(count)
  self:clear_grapheme_context()
  local cursor = self.active_screen.cursor
  local row = self.active_screen.rows[cursor.row]
  count = math.min(count or 1, self.columns - cursor.column)
  for column = cursor.column, self.columns - count - 1 do
    copy_cell(row.cells[column], row.cells[column + count])
  end
  for column = self.columns - count, self.columns - 1 do
    copy_cell(row.cells[column], self:cell_from_attributes(" "))
  end
  self:normalize_row(cursor.row)
  local first = self:index(cursor.column, cursor.row)
  local count = self.columns - cursor.column
  self.damage:mark_range(first, count)
  self.text_damage:mark_range(first, count)
  cursor.pending_wrap = false
end

function State:insert_lines(count)
  self:clear_grapheme_context()
  local cursor = self.active_screen.cursor
  if cursor.row < self.active_screen.top_margin or cursor.row > self.active_screen.bottom_margin then
    return
  end
  local bottom = self.active_screen.bottom_margin
  self.active_screen:scroll_down(cursor.row, bottom, clamp(count or 1, 1, bottom - cursor.row + 1))
  self:mark_region(cursor.row, bottom)
end

function State:delete_lines(count)
  self:clear_grapheme_context()
  local cursor = self.active_screen.cursor
  if cursor.row < self.active_screen.top_margin or cursor.row > self.active_screen.bottom_margin then
    return
  end
  local bottom = self.active_screen.bottom_margin
  self.active_screen:scroll_up(cursor.row, bottom, clamp(count or 1, 1, bottom - cursor.row + 1))
  self:mark_region(cursor.row, bottom)
end

function State:set_margins(top, bottom)
  top = top or 1
  bottom = bottom or self.rows
  if top < 1 or bottom > self.rows or top >= bottom then
    return false
  end
  self.active_screen.top_margin = top - 1
  self.active_screen.bottom_margin = bottom - 1
  self:set_cursor(0, self.modes.origin and self.active_screen.top_margin or 0)
  return true
end

function State:move_cursor(row, column)
  row = row or 1
  column = column or 1
  if self.modes.origin then
    row = self.active_screen.top_margin + row
  end
  self:set_cursor(column - 1, row - 1)
end

function State:move_relative(row_delta, column_delta)
  local cursor = self.active_screen.cursor
  local minimum_row = self.modes.origin and self.active_screen.top_margin or 0
  local maximum_row = self.modes.origin and self.active_screen.bottom_margin or self.rows - 1
  self:set_cursor(clamp(cursor.column + column_delta, 0, self.columns - 1), clamp(cursor.row + row_delta, minimum_row, maximum_row))
end

function State:set_tab_stop()
  self.tab_stops[self.active_screen.cursor.column] = true
end

function State:clear_tab_stops(mode)
  if mode == 3 then
    self.tab_stops = {}
  else
    self.tab_stops[self.active_screen.cursor.column] = nil
  end
end

function State:switch_alternate(enable, save_cursor)
  self:clear_grapheme_context()
  if enable then
    if save_cursor then
      self.primary.saved_cursor = {
        column = self.primary.cursor.column,
        row = self.primary.cursor.row,
        attributes = Attributes.copy(self.primary.attributes),
      }
    end
    self.active_screen = self.alternate
    self.cursor = self.active_screen.cursor
    self.history_offset = 0
    if save_cursor then
      self.alternate = self:new_screen()
      self.alternate.attributes = Attributes.default()
      self.active_screen = self.alternate
      self.cursor = self.active_screen.cursor
    end
  else
    self.active_screen = self.primary
    self.cursor = self.primary.cursor
    if save_cursor then
      self:restore_cursor()
    end
  end
  self:sync_keyboard_flags()
  self:reconcile_selection()
  self:sync_cursor_visibility()
  self.damage:mark_all()
  self.text_damage:mark_all()
end

function State:scroll_history(lines)
  if self.active_screen ~= self.primary then
    return
  end
  self.history_offset = clamp(self.history_offset + lines, 0, self.scrollback:size())
  self:sync_cursor_visibility()
  self.damage:mark_all()
  self.text_damage:mark_all()
end

function State:pop_responses()
  local responses = self.responses
  self.responses = {}
  return responses
end

function State:respond(value)
  self.responses[#self.responses + 1] = value
end

function State:record_unknown(family, detail)
  self.stats.unknown[family] = (self.stats.unknown[family] or 0) + 1
  if #self.stats.unknown_samples < 16 then
    self.stats.unknown_samples[#self.stats.unknown_samples + 1] = {
      family = family,
      count = self.stats.unknown[family],
      detail = detail,
    }
  end
end

function State:reset()
  self:clear_grapheme_context()
  self.primary = self:new_screen()
  self.alternate = self:new_screen()
  self.primary.attributes = Attributes.default()
  self.alternate.attributes = Attributes.default()
  self.active_screen = self.primary
  self.cursor = self.primary.cursor
  self.modes.autowrap = true
  self.modes.origin = false
  self.modes.insert = false
  self.modes.cursor_visible = true
  self.modes.cursor_style = 1
  self.modes.application_cursor = false
  self.modes.bracketed_paste = false
  self.modes.synchronized_output = false
  self.modes.mouse_tracking = "none"
  self.modes.mouse_normal = false
  self.modes.mouse_button = false
  self.modes.mouse_any = false
  self.modes.mouse_sgr = false
  self.modes.focus_reporting = false
  self.modes.mouse_generation = self.modes.mouse_generation + 1
  self.modes.keyboard_flags = 0
  self:reset_tab_stops()
  self.scrollback:clear()
  self:clear_selection()
  self.history_offset = 0
  self:sync_cursor_visibility()
  self.damage:mark_all()
  self.text_damage:mark_all()
end

function State:resize(columns, rows)
  self:clear_grapheme_context()
  assert(columns > 0 and rows > 0, "terminal dimensions must be positive")
  local was_primary = self.active_screen == self.primary
  local blank = function()
    return self:blank_cell()
  end
  self.primary = self.primary:resize(columns, rows, blank)
  self.alternate = self.alternate:resize(columns, rows, blank)
  self.columns = columns
  self.rows = rows
  self.primary.top_margin = 0
  self.primary.bottom_margin = rows - 1
  self.alternate.top_margin = 0
  self.alternate.bottom_margin = rows - 1
  self.active_screen = was_primary and self.primary or self.alternate
  self.cursor = self.active_screen.cursor
  self:sync_keyboard_flags()
  self:normalize_screen(self.primary)
  self:normalize_screen(self.alternate)
  self.damage = Damage.new(columns * rows)
  self.text_damage = Damage.new(columns * rows)
  self.history_offset = clamp(self.history_offset, 0, self.scrollback:size())
  self:reconcile_selection()
  self:reset_tab_stops()
  self:sync_cursor_visibility()
  self.damage:mark_all()
  self.text_damage:mark_all()
end

function State:mark_all_dirty()
  self.damage:mark_all()
  self.text_damage:mark_all()
end

local function parameter(parameters, index, fallback)
  local value = parameters[index]
  if value == nil or value == 0 then
    return fallback
  end
  return value
end

local function csi_detail(action)
  local parameters = {}
  for index, value in ipairs(action.parameters or {}) do
    parameters[index] = value
  end
  return {
    private = action.private or "",
    parameters = parameters,
    intermediates = action.intermediates or "",
    final = action.final or "",
    colon = action.colon or false,
  }
end

function State:apply_execute(code)
  if code == 0 or code == 0x7f then
    return
  end
  if code == 0x07 then
    self.stats.bells = self.stats.bells + 1
  elseif code == 0x08 then
    self:backspace()
  elseif code == 0x09 then
    self:tab()
  elseif code == 0x0a or code == 0x0b or code == 0x0c then
    self:line_feed()
  elseif code == 0x0d then
    self:carriage_return()
  else
    self:record_unknown("control", string.format("0x%02x", code))
  end
end

function State:apply_esc(action)
  if action.intermediates == "" and action.final == "D" then
    self:index_line()
  elseif action.intermediates == "" and action.final == "E" then
    self:carriage_return()
    self:index_line()
  elseif action.intermediates == "" and action.final == "M" then
    self:reverse_index()
  elseif action.intermediates == "" and action.final == "7" then
    self:save_cursor()
  elseif action.intermediates == "" and action.final == "8" then
    self:restore_cursor()
  elseif action.intermediates == "" and action.final == "H" then
    self:set_tab_stop()
  elseif action.intermediates == "" and action.final == "c" then
    self:reset()
  else
    self:record_unknown("esc", action.intermediates .. action.final)
  end
end

function State:apply_private_mode(parameters, enabled)
  for _, mode in ipairs(parameters) do
    if mode == 1 then
      self.modes.application_cursor = enabled
    elseif mode == 6 then
      self.modes.origin = enabled
      self:set_cursor(0, enabled and self.active_screen.top_margin or 0)
    elseif mode == 7 then
      self.modes.autowrap = enabled
      self.active_screen.cursor.pending_wrap = false
    elseif mode == 25 then
      self.modes.cursor_visible = enabled
      self:sync_cursor_visibility()
      self.damage:mark(self:index(self.cursor.column, self.cursor.row))
    elseif mode == 47 or mode == 1047 then
      self:switch_alternate(enabled, false)
    elseif mode == 1048 then
      if enabled then
        self:save_cursor()
      else
        self:restore_cursor()
      end
    elseif mode == 1049 then
      self:switch_alternate(enabled, true)
    elseif mode == 2004 then
      self.modes.bracketed_paste = enabled
    elseif mode == 2026 then
      self.modes.synchronized_output = enabled
    elseif mode == 1000 then
      self:set_mouse_tracking("normal", enabled)
    elseif mode == 1002 then
      self:set_mouse_tracking("button", enabled)
    elseif mode == 1003 then
      self:set_mouse_tracking("any", enabled)
    elseif mode == 1004 then
      self:set_focus_reporting(enabled)
    elseif mode == 1006 then
      self:set_mouse_sgr(enabled)
    else
      self:record_unknown("csi", { private = "?", parameters = { mode }, intermediates = "", final = enabled and "h" or "l" })
    end
  end
end

function State:set_mouse_tracking(mode, enabled)
  local field = "mouse_" .. mode
  if self.modes[field] == enabled then return end
  self.modes[field] = enabled
  local next_mode = self.modes.mouse_any and "any"
    or self.modes.mouse_button and "button"
    or self.modes.mouse_normal and "normal"
    or "none"
  if self.modes.mouse_tracking ~= next_mode then
    self.modes.mouse_tracking = next_mode
  end
  self.modes.mouse_generation = self.modes.mouse_generation + 1
end

function State:set_mouse_sgr(enabled)
  if self.modes.mouse_sgr ~= enabled then
    self.modes.mouse_sgr = enabled
    self.modes.mouse_generation = self.modes.mouse_generation + 1
  end
end

function State:set_focus_reporting(enabled)
  self.modes.focus_reporting = enabled
end

function State:sync_keyboard_flags()
  self.modes.keyboard_flags = self.active_screen.keyboard_flags
end

function State:set_keyboard_flags(flags)
  self.active_screen.keyboard_flags = flags
  self.modes.keyboard_flags = flags
end

function State:apply_keyboard_flags(flags, mode)
  local requested = flags % 2
  if mode == 1 then
    self:set_keyboard_flags(requested)
  elseif mode == 2 and requested == 1 then
    self:set_keyboard_flags(1)
  elseif mode == 3 and requested == 1 then
    self:set_keyboard_flags(0)
  elseif mode ~= 2 and mode ~= 3 then
    self:record_unknown("csi", { private = "=", parameters = { flags, mode }, intermediates = "", final = "u" })
  end
end

function State:apply_keyboard_protocol(action)
  local parameters = action.parameters
  if action.private == "?" then
    if #parameters ~= 0 then
      self:record_unknown("csi", csi_detail(action))
      return
    end
    self:respond(string.format("\27[?%du", self.active_screen.keyboard_flags))
  elseif action.private == "=" then
    if #parameters > 2 then
      self:record_unknown("csi", csi_detail(action))
      return
    end
    local flags = parameters[1] or 0
    local mode = parameters[2] or 1
    if mode < 1 or mode > 3 then
      self:record_unknown("csi", csi_detail(action))
      return
    end
    self:apply_keyboard_flags(flags, mode)
  elseif action.private == ">" then
    if #parameters > 1 then
      self:record_unknown("csi", csi_detail(action))
      return
    end
    local stack = self.active_screen.keyboard_stack
    if #stack == 8 then table.remove(stack, 1) end
    stack[#stack + 1] = self.active_screen.keyboard_flags
    self:apply_keyboard_flags(parameters[1] or 0, 1)
  elseif action.private == "<" then
    if #parameters > 1 then
      self:record_unknown("csi", csi_detail(action))
      return
    end
    local count = parameters[1] or 1
    local stack = self.active_screen.keyboard_stack
    local target = #stack - math.max(0, count) + 1
    if target >= 1 then
      self:set_keyboard_flags(stack[target])
      for index = #stack, target, -1 do stack[index] = nil end
    elseif count > 0 then
      self:set_keyboard_flags(0)
      self.active_screen.keyboard_stack = {}
    end
  end
end

function State:set_cursor_style(action)
  if #action.parameters > 1 then
    self:record_unknown("csi", csi_detail(action))
    return
  end
  local style = action.parameters[1] or 1
  if style == 0 then style = 1 end
  if style < 1 or style > 6 then
    self:record_unknown("csi", csi_detail(action))
    return
  end
  self.modes.cursor_style = style
end

function State:apply_standard_mode(parameters, enabled)
  for _, mode in ipairs(parameters) do
    if mode == 4 then
      self.modes.insert = enabled
    else
      self:record_unknown("csi", { private = "", parameters = { mode }, intermediates = "", final = enabled and "h" or "l" })
    end
  end
end

function State:apply_csi(action)
  if action.colon then
    self:record_unknown("csi", csi_detail(action))
    return
  end
  local parameters = action.parameters
  local final = action.final
  if action.private == "?" and (final == "h" or final == "l") then
    self:apply_private_mode(parameters, final == "h")
    return
  end
  if final == "u" and action.intermediates == "" and (action.private == "?" or action.private == "=" or action.private == ">" or action.private == "<") then
    self:apply_keyboard_protocol(action)
    return
  end
  if action.private == "" and action.intermediates == " " and final == "q" then
    self:set_cursor_style(action)
    return
  end
  if action.private ~= "" then
    self:record_unknown("csi", csi_detail(action))
    return
  end
  if final == "A" then
    self:move_relative(-parameter(parameters, 1, 1), 0)
  elseif final == "B" then
    self:move_relative(parameter(parameters, 1, 1), 0)
  elseif final == "C" then
    self:move_relative(0, parameter(parameters, 1, 1))
  elseif final == "D" then
    self:move_relative(0, -parameter(parameters, 1, 1))
  elseif final == "E" then
    self:move_relative(parameter(parameters, 1, 1), 0)
    self:set_cursor(0, self.cursor.row)
  elseif final == "F" then
    self:move_relative(-parameter(parameters, 1, 1), 0)
    self:set_cursor(0, self.cursor.row)
  elseif final == "G" then
    self:set_cursor(parameter(parameters, 1, 1) - 1, self.cursor.row)
  elseif final == "d" then
    self:move_cursor(parameter(parameters, 1, 1), self.cursor.column + 1)
  elseif final == "H" or final == "f" then
    self:move_cursor(parameter(parameters, 1, 1), parameter(parameters, 2, 1))
  elseif final == "J" then
    self:erase_in_display(parameters[1] or 0)
  elseif final == "K" then
    self:erase_in_line(parameters[1] or 0)
  elseif final == "X" then
    self:erase_characters(parameter(parameters, 1, 1))
  elseif final == "@" then
    self:insert_characters(parameter(parameters, 1, 1))
  elseif final == "P" then
    self:delete_characters(parameter(parameters, 1, 1))
  elseif final == "L" then
    self:insert_lines(parameter(parameters, 1, 1))
  elseif final == "M" then
    self:delete_lines(parameter(parameters, 1, 1))
  elseif final == "S" then
    self:scroll_up(parameter(parameters, 1, 1))
  elseif final == "T" then
    self:scroll_down(parameter(parameters, 1, 1))
  elseif final == "r" then
    self:set_margins(parameters[1], parameters[2])
  elseif final == "m" then
    self.active_screen.attributes = Attributes.apply_sgr(self.active_screen.attributes, parameters)
  elseif final == "h" or final == "l" then
    self:apply_standard_mode(parameters, final == "h")
  elseif final == "g" then
    self:clear_tab_stops(parameters[1] or 0)
  elseif final == "s" then
    self:save_cursor()
  elseif final == "u" then
    self:restore_cursor()
  elseif final == "n" then
    local request = parameters[1] or 0
    if request == 5 then
      self:respond("\27[0n")
    elseif request == 6 then
      self:respond(string.format("\27[%d;%dR", self.cursor.row + 1, self.cursor.column + 1))
    else
      self:record_unknown("csi", csi_detail(action))
    end
  elseif final == "c" then
    self:respond("\27[?1;0c")
  else
    self:record_unknown("csi", csi_detail(action))
  end
end

function State:apply_osc(action)
  if action.command == 0 or action.command == 2 then
    self.title = action.payload
  elseif action.command ~= 7 and action.command ~= 8 and action.command ~= 133 then
    self:record_unknown("osc", { command = action.command })
  end
end

function State:apply(action)
  if action.kind == "print" then
    self:write_codepoint(action.text, action.codepoint)
  elseif action.kind == "execute" then
    self:apply_execute(action.code)
  elseif action.kind == "esc" then
    self:apply_esc(action)
  elseif action.kind == "csi" then
    self:apply_csi(action)
  elseif action.kind == "osc" then
    self:apply_osc(action)
  elseif action.kind == "ignore" then
    self:record_unknown(action.family, action.reason)
  else
    error("unknown terminal action: " .. tostring(action.kind))
  end
end

return State
