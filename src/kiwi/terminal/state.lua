local Attributes = require("kiwi.terminal.attributes")
local Damage = require("kiwi.terminal.damage")
local Grapheme = require("kiwi.unicode.grapheme")
local Properties = require("kiwi.unicode.properties")
local Screen = require("kiwi.terminal.screen")
local Scrollback = require("kiwi.terminal.scrollback")
local Utf8 = require("kiwi.terminal.utf8")
local Width = require("kiwi.terminal.width")

local State = {}
State.__index = State

State.flags = Attributes.flags

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
    default_cell = { glyph = " ", fg = Attributes.default_foreground, bg = Attributes.default_background, flags = 0, width = 1 },
    damage = Damage.new(columns * rows),
    modes = {
      autowrap = true,
      origin = false,
      insert = false,
      cursor_visible = true,
      application_cursor = false,
      bracketed_paste = false,
    },
    tab_stops = {},
    scrollback = Scrollback.new(options.scrollback_limit or 2000),
    history_offset = 0,
    title = nil,
    responses = {},
    width_policy = {
      ambiguous_width = options.ambiguous_width or Width.default_policy.ambiguous_width,
      private_use_width = options.private_use_width or Width.default_policy.private_use_width,
    },
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
  self.primary = Screen.new(columns, rows, function()
    return self:blank_cell()
  end)
  self.alternate = Screen.new(columns, rows, function()
    return self:blank_cell()
  end)
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
  return self
end

function State:blank_cell()
  return { glyph = " ", fg = self.default_cell.fg, bg = self.default_cell.bg, flags = 0, width = 1 }
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

function State:cell_at_index(index)
  local column, row = self:position(index)
  local visible = self:visible_row(row)
  return visible and visible.cells[column] or self.default_cell
end

function State:get(column, row)
  return self.active_screen:get(column, row)
end

function State:mark_changed(column, row)
  self.damage:mark(self:index(column, row))
  self.stats.mutations = self.stats.mutations + 1
end

function State:set_cell(column, row, cell)
  local target = self.active_screen:get(column, row)
  if same_cell(target, cell) then
    return false
  end
  copy_cell(target, cell)
  self:mark_changed(column, row)
  return true
end

function State:mark_region(top, bottom)
  self.damage:mark_range(top * self.columns, (bottom - top + 1) * self.columns)
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
  self:set_cell(anchor_column, row, self:blank_cell())
  if anchor.width == 2 and anchor_column + 1 < self.columns then
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
  if width == 2 and cursor.column == self.columns - 1 then
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
  local leading = gcb == Properties.grapheme_break.extend
    or gcb == Properties.grapheme_break.zwj
    or gcb == Properties.grapheme_break.spacing_mark
  local display_text = leading and Utf8.encode(0x25cc) .. glyph or glyph
  local cursor, width = self:prepare_cluster_write(Width.columns(codepoints, self.width_policy))
  local column, row = cursor.column, cursor.row
  self:clear_cluster_at(column, row)
  if width == 2 then self:clear_cluster_at(column + 1, row) end
  local anchor = self:cell_from_attributes(glyph, {
    codepoints = codepoints,
    width = width,
    display_text = display_text,
  })
  self:set_cell(column, row, anchor)
  if width == 2 then
    self:set_cell(column + 1, row, self:continuation_cell(column))
  end
  self.grapheme_context = { screen = self.active_screen, row = row, column = column, codepoints = codepoints }
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
  self.grapheme_context = context
end

function State:write_codepoint(glyph, codepoint)
  codepoint = codepoint or Utf8.decode_one(glyph)
  local cell, context = self:current_grapheme_cluster()
  if cell and not Grapheme.should_break(context.codepoints, codepoint) then
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
  self.damage:mark_range(self:index(cursor.column, cursor.row), self.columns - cursor.column)
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
  self.damage:mark_range(self:index(cursor.column, cursor.row), self.columns - cursor.column)
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
      self.alternate = Screen.new(self.columns, self.rows, function()
        return self:blank_cell()
      end)
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
  self:sync_cursor_visibility()
  self.damage:mark_all()
end

function State:scroll_history(lines)
  if self.active_screen ~= self.primary then
    return
  end
  self.history_offset = clamp(self.history_offset + lines, 0, self.scrollback:size())
  self:sync_cursor_visibility()
  self.damage:mark_all()
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
  self.primary = Screen.new(self.columns, self.rows, function()
    return self:blank_cell()
  end)
  self.alternate = Screen.new(self.columns, self.rows, function()
    return self:blank_cell()
  end)
  self.primary.attributes = Attributes.default()
  self.alternate.attributes = Attributes.default()
  self.active_screen = self.primary
  self.cursor = self.primary.cursor
  self.modes.autowrap = true
  self.modes.origin = false
  self.modes.insert = false
  self.modes.cursor_visible = true
  self.modes.application_cursor = false
  self.modes.bracketed_paste = false
  self:reset_tab_stops()
  self.scrollback:clear()
  self.history_offset = 0
  self:sync_cursor_visibility()
  self.damage:mark_all()
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
  self:normalize_screen(self.primary)
  self:normalize_screen(self.alternate)
  self.damage = Damage.new(columns * rows)
  self.history_offset = clamp(self.history_offset, 0, self.scrollback:size())
  self:reset_tab_stops()
  self:sync_cursor_visibility()
  self.damage:mark_all()
end

function State:mark_all_dirty()
  self.damage:mark_all()
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
    else
      self:record_unknown("csi", { private = "?", parameters = { mode }, intermediates = "", final = enabled and "h" or "l" })
    end
  end
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
