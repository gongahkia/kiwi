local Attributes = require("kiwi.terminal.attributes")
local Base64 = require("kiwi.terminal.base64")
local bit = require("bit")
local CommandRegions = require("kiwi.terminal.command_regions")
local Damage = require("kiwi.terminal.damage")
local Grapheme = require("kiwi.unicode.grapheme")
local Hyperlink = require("kiwi.terminal.hyperlink")
local KittyGraphics = require("kiwi.terminal.kitty_graphics")
local KittyPlacements = require("kiwi.terminal.kitty_placements")
local Properties = require("kiwi.unicode.properties")
local Reflow = require("kiwi.terminal.reflow")
local Screen = require("kiwi.terminal.screen")
local Scrollback = require("kiwi.terminal.scrollback")
local Search = require("kiwi.input.search")
local Selection = require("kiwi.input.selection")
local ShellIntegration = require("kiwi.terminal.shell_integration")
local Utf8 = require("kiwi.terminal.utf8")
local Width = require("kiwi.terminal.width")
local Color = require("kiwi.terminal.color")

local State = {}
State.__index = State

State.flags = Attributes.flags
State.keyboard_supported_flags = 0x1b
State.title_stack_limit = 10
State.reflow = Reflow
local GCB = Properties.grapheme_break
local ascii_codepoints = {}
for codepoint = 0x20, 0x7e do ascii_codepoints[codepoint] = { codepoint } end

local dec_special_graphics = {
  ["_"] = " ", ["`"] = "◆", ["a"] = "▒", ["b"] = "␉", ["c"] = "␌", ["d"] = "␍", ["e"] = "␊",
  ["f"] = "°", ["g"] = "±", ["h"] = "␤", ["i"] = "␋", ["j"] = "┘", ["k"] = "┐", ["l"] = "┌",
  ["m"] = "└", ["n"] = "┼", ["o"] = "⎺", ["p"] = "⎻", ["q"] = "─", ["r"] = "⎼", ["s"] = "⎽",
  ["t"] = "├", ["u"] = "┤", ["v"] = "┴", ["w"] = "┬", ["x"] = "│", ["y"] = "≤", ["z"] = "≥",
  ["{"] = "π", ["|"] = "≠", ["}"] = "£", ["~"] = "·",
}

local uk_character_set = { ["#"] = "£" }
local default_cursor_color = Color.pack(0x8c, 0xd9, 0xe0, 0xff)

local function copy_character_sets(character_sets)
  return { g0 = character_sets.g0, g1 = character_sets.g1, gl = character_sets.gl }
end

local function copy_cell(destination, source)
  destination.glyph = source.glyph
  destination.fg = source.fg
  destination.bg = source.bg
  destination.fg_slot = source.fg_slot
  destination.bg_slot = source.bg_slot
  destination.flags = source.flags
  destination.codepoints = source.codepoints
  destination.width = source.width
  destination.continuation = source.continuation
  destination.anchor_column = source.anchor_column
  destination.display_text = source.display_text
  destination.hyperlink_id = source.hyperlink_id
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
    and left.fg_slot == right.fg_slot
    and left.bg_slot == right.bg_slot
    and left.flags == right.flags
    and left.width == right.width
    and left.continuation == right.continuation
    and left.anchor_column == right.anchor_column
    and left.display_text == right.display_text
    and left.hyperlink_id == right.hyperlink_id
    and same_codepoints(left.codepoints, right.codepoints)
end

local function clamp(value, lower, upper)
  return math.max(lower, math.min(value, upper))
end

local function valid_cell_metric(value)
  return type(value) == "number" and value % 1 == 0 and value > 0 and value <= 65535
end

function State.new(columns, rows, options)
  assert(columns > 0 and rows > 0, "terminal dimensions must be positive")
  options = options or {}
  assert(options.effect_sink == nil or type(options.effect_sink) == "function", "terminal effect sink must be a function")
  assert(options.queue_responses == nil or type(options.queue_responses) == "boolean", "terminal response queue selection must be a boolean")
  assert(options.reflow_on_resize == nil or type(options.reflow_on_resize) == "boolean", "terminal reflow policy must be a boolean")
  assert(options.keyboard_supported_flags == nil or (type(options.keyboard_supported_flags) == "number" and options.keyboard_supported_flags % 1 == 0 and options.keyboard_supported_flags >= 0 and options.keyboard_supported_flags <= 31), "terminal keyboard supported flags must be an integer from 0 through 31")
  assert((options.cell_width == nil) == (options.cell_height == nil), "terminal cell metrics must provide both width and height")
  assert(options.cell_width == nil or valid_cell_metric(options.cell_width), "terminal cell width must be a positive integer no greater than 65535")
  assert(options.cell_height == nil or valid_cell_metric(options.cell_height), "terminal cell height must be a positive integer no greater than 65535")
  local colors = Attributes.Palette.new(options.colors)
  local self = setmetatable({
    columns = columns,
    rows = rows,
    cell_width = options.cell_width,
    cell_height = options.cell_height,
    next_line_id = 0,
    colors = colors,
    cursor_color = default_cursor_color,
    cursor_default_color = default_cursor_color,
    default_cell = { glyph = " ", fg = colors.foreground, bg = colors.background, fg_slot = 0, bg_slot = 0, flags = 0, width = 1 },
    damage = Damage.new(columns * rows),
    text_damage = Damage.new(columns * rows),
    modes = {
      autowrap = true,
      origin = false,
      left_right_margin = false,
      insert = false,
      newline = false,
      cursor_visible = true,
      cursor_style = 1,
      cursor_blink = true,
      application_cursor = false,
      application_keypad = false,
      backarrow = false,
      reverse_wrap = false,
      bracketed_paste = false,
      synchronized_output = false,
      mouse_tracking = "none",
      mouse_x10 = false,
      mouse_normal = false,
      mouse_button = false,
      mouse_any = false,
      mouse_utf8 = false,
      mouse_sgr = false,
      mouse_pixels = false,
      mouse_urxvt = false,
      mouse_protocol = "x10",
      alternate_scroll = false,
      focus_reporting = false,
      mouse_generation = 0,
      keyboard_flags = 0,
      modify_other_keys = 0,
    },
    saved_private_modes = {},
    tab_stops = {},
    scrollback = Scrollback.new(options.scrollback_limit or 2000),
    search = Search.new(),
    search_generation = 0,
    selection = Selection.new(),
    shell = ShellIntegration.new(options.shell_integration),
    command_regions = CommandRegions.new(options.command_regions),
    command_region_navigation = nil,
    effect_sink = options.effect_sink,
    keyboard_supported_flags = options.keyboard_supported_flags or State.keyboard_supported_flags,
    osc52_write = options.osc52_write == true,
    osc52_maximum_bytes = options.osc52_maximum_bytes or 64 * 1024,
    history_offset = 0,
    queue_responses = options.queue_responses ~= false,
    reflow_on_resize = options.reflow_on_resize ~= false,
    title = nil,
    icon_title = nil,
    title_stacks = { icon = {}, window = {} },
    responses = {},
    grapheme_context_storage = {},
    text_counters = options.text_counters,
    width_policy = Width.normalize_policy({
      ambiguous_width = options.ambiguous_width == nil and Width.default_policy.ambiguous_width or options.ambiguous_width,
      private_use_width = options.private_use_width == nil and Width.default_policy.private_use_width or options.private_use_width,
    }),
    max_cluster_codepoints = options.max_cluster_codepoints or 64,
    hyperlink_limit = options.hyperlink_limit or 4096,
    hyperlink_uri_maximum_bytes = options.hyperlink_uri_maximum_bytes or Hyperlink.maximum_uri_bytes,
    hyperlinks = {},
    hyperlink_ids = {},
    kitty_graphics = KittyGraphics.new(options.kitty_graphics),
    kitty_placements = KittyPlacements.new(options.kitty_placements),
    next_hyperlink_id = 0,
    last_print = nil,
    max_repeat = options.max_repeat or 4096,
    character_sets = { g0 = "ascii", g1 = "ascii", gl = "g0" },
    stats = {
      mutations = 0,
      bells = 0,
      text = { over_limit_clusters = 0, width_change_clamped = 0 },
      unknown = { csi = 0, esc = 0, osc = 0, string = 0 },
      unknown_samples = {},
      hyperlinks = { opened = 0, closed = 0, rejected = 0 },
    },
  }, State)
  assert(self.max_cluster_codepoints >= 8, "terminal max_cluster_codepoints must be at least 8")
  assert(self.hyperlink_limit >= 1 and self.hyperlink_limit % 1 == 0, "terminal hyperlink limit must be a positive integer")
  assert(self.hyperlink_uri_maximum_bytes >= 1 and self.hyperlink_uri_maximum_bytes % 1 == 0, "terminal hyperlink URI limit must be a positive integer")
  assert(self.max_repeat >= 1 and self.max_repeat % 1 == 0, "terminal repeat limit must be a positive integer")
  assert(type(self.osc52_maximum_bytes) == "number" and self.osc52_maximum_bytes >= 1 and self.osc52_maximum_bytes % 1 == 0, "terminal OSC 52 byte limit must be a positive integer")
  self.kitty_graphics.on_image_release = function(id)
    self:detach_kitty_placement_records(self.kitty_placements:remove_image(id))
  end
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
  return {
    glyph = " ",
    fg = self.default_cell.fg,
    bg = self.default_cell.bg,
    fg_slot = self.default_cell.fg_slot,
    bg_slot = self.default_cell.bg_slot,
    flags = 0,
    width = 1,
  }
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
  local foreground, background, flags, foreground_slot, background_slot = Attributes.resolve(self.active_screen.attributes, self.colors)
  metadata = metadata or {}
  local hyperlink_id = self.active_screen.hyperlink_id
  if hyperlink_id ~= nil then flags = flags + Attributes.flags.hyperlink end
  return {
    glyph = glyph,
    fg = foreground,
    bg = background,
    fg_slot = foreground_slot,
    bg_slot = background_slot,
    flags = flags,
    codepoints = metadata.codepoints,
    width = metadata.width or 1,
    continuation = metadata.continuation,
    anchor_column = metadata.anchor_column,
    display_text = metadata.display_text,
    hyperlink_id = hyperlink_id,
  }
end

function State:ascii_cell(glyph, codepoints)
  local foreground, background, flags, foreground_slot, background_slot = Attributes.resolve(self.active_screen.attributes, self.colors)
  local hyperlink_id = self.active_screen.hyperlink_id
  if hyperlink_id ~= nil then flags = flags + Attributes.flags.hyperlink end
  return {
    glyph = glyph,
    fg = foreground,
    bg = background,
    fg_slot = foreground_slot,
    bg_slot = background_slot,
    flags = flags,
    codepoints = codepoints,
    width = 1,
    display_text = glyph,
    hyperlink_id = hyperlink_id,
  }
end

function State:set_ascii_cell(column, row, glyph, codepoints)
  local foreground, background, flags, foreground_slot, background_slot = Attributes.resolve(self.active_screen.attributes, self.colors)
  local target = self.active_screen:get(column, row)
  local hyperlink_id = self.active_screen.hyperlink_id
  if hyperlink_id ~= nil then flags = flags + Attributes.flags.hyperlink end
  if target.glyph == glyph
    and target.fg == foreground
    and target.bg == background
    and target.fg_slot == foreground_slot
    and target.bg_slot == background_slot
    and target.flags == flags
    and target.codepoints == codepoints
    and target.width == 1
    and not target.continuation
    and target.anchor_column == nil
    and target.display_text == glyph
    and target.hyperlink_id == hyperlink_id then
    return false
  end
  target.glyph = glyph
  target.fg = foreground
  target.bg = background
  target.fg_slot = foreground_slot
  target.bg_slot = background_slot
  target.flags = flags
  target.codepoints = codepoints
  target.width = 1
  target.continuation = nil
  target.anchor_column = nil
  target.display_text = glyph
  target.hyperlink_id = hyperlink_id
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

function State:shell_position()
  local cursor = self.active_screen.cursor
  return {
    column = cursor.column,
    line_id = self.active_screen.rows[cursor.row].line_id,
    scope = self:selection_scope(),
  }
end

function State:attach_command_region(row, id)
  if id == nil then return end
  local ids = row.command_region_ids
  if ids == nil then
    ids = {}
    row.command_region_ids = ids
  end
  for _, existing in ipairs(ids) do
    if existing == id then return end
  end
  if #ids >= self.command_regions.row_reference_limit then
    row.command_regions_truncated = true
    self.command_regions:mark_row_reference_overflow(id)
    return
  end
  ids[#ids + 1] = id
  self.command_regions:attach_row(id)
end

function State:attach_active_command_region(row)
  self:attach_command_region(row, self.command_regions:active_id())
end

function State:release_command_regions(row)
  self.command_regions:release_row(row.command_region_ids)
end

function State:reconcile_command_regions()
  local rows = {}
  for index = 1, self.scrollback:size() do rows[#rows + 1] = self.scrollback:get(index) end
  for row = 0, self.rows - 1 do rows[#rows + 1] = self.primary.rows[row] end
  for row = 0, self.rows - 1 do rows[#rows + 1] = self.alternate.rows[row] end
  self.command_regions:reconcile_rows(rows)
end

function State:command_regions_at(row)
  local source = self:visible_row(row)
  local ids = {}
  for index, id in ipairs(source.command_region_ids or {}) do ids[index] = id end
  return { ids = ids, truncated = source.command_regions_truncated }
end

function State:command_region_targets(role)
  local field = ({ command = "command_start", output = "output_start", prompt = "prompt_start" })[role]
  assert(field ~= nil, "unknown command-region role")
  local positions = {}
  for index, entry in ipairs(self:selection_rows("primary")) do positions[entry.line_id] = index end
  local targets = {}
  for _, region in ipairs(self.command_regions:view().regions) do
    local position = region[field]
    local row = position and position.scope == "primary" and positions[position.line_id] or nil
    if row then targets[#targets + 1] = { column = position.column, id = region.id, position = position, region = region, row = row } end
  end
  table.sort(targets, function(left, right)
    if left.row ~= right.row then return left.row < right.row end
    if left.column ~= right.column then return left.column < right.column end
    return left.id < right.id
  end)
  return targets
end

function State:reveal_command_region(target)
  local offset = clamp(self.scrollback:size() - (target.row - 1), 0, self.scrollback:size())
  self.history_offset = offset
  self:sync_cursor_visibility()
  self.damage:mark_all()
  self.text_damage:mark_all()
end

function State:navigate_command_region(role, direction)
  if self.active_screen ~= self.primary then return nil, "alternate-screen" end
  if self.modes.keyboard_flags ~= 0 then return nil, "keyboard-mode" end
  if self.search.editing then return nil, "search-active" end
  assert(direction == "forward" or direction == "backward", "unknown command-region direction")
  local targets = self:command_region_targets(role)
  if #targets == 0 then return nil, "no-region" end
  local step = direction == "forward" and 1 or -1
  local navigation = self.command_region_navigation
  local index
  if navigation and navigation.role == role then
    for candidate, target in ipairs(targets) do
      if target.id == navigation.id then
        index = candidate + step
        break
      end
    end
  end
  if index == nil then
    local anchor_row, anchor_column
    if self.history_offset == 0 then
      anchor_row = self.rows + self.scrollback:size()
      anchor_column = self.cursor.column
    else
      anchor_row = self.scrollback:size() - self.history_offset + 1
      anchor_column = 0
    end
    if direction == "forward" then
      for candidate, target in ipairs(targets) do
        if target.row > anchor_row or (target.row == anchor_row and target.column > anchor_column) then
          index = candidate
          break
        end
      end
    else
      for candidate = #targets, 1, -1 do
        local target = targets[candidate]
        if target.row < anchor_row or (target.row == anchor_row and target.column < anchor_column) then
          index = candidate
          break
        end
      end
    end
  end
  if index == nil or targets[index] == nil then return nil, direction == "forward" and "end" or "start" end
  local target = targets[index]
  self:reveal_command_region(target)
  self.command_region_navigation = { id = target.id, role = role }
  return target.region, "navigated"
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

function State:detach_kitty_placement_records(records)
  for _, record in ipairs(records or {}) do
    for _, entry in ipairs(self:selection_rows(record.scope)) do
      local ids = entry.row.kitty_placement_ids
      if ids then
        for index = #ids, 1, -1 do
          if ids[index] == record.id then table.remove(ids, index) end
        end
        if #ids == 0 then entry.row.kitty_placement_ids = nil end
      end
    end
  end
end

function State:attach_kitty_placement(record)
  local rows = {}
  for _, entry in ipairs(self:selection_rows(record.scope)) do rows[entry.line_id] = entry.row end
  for _, reference in ipairs(record.rows) do
    local row = assert(rows[reference.line_id], "kitty placement row is unavailable")
    row.kitty_placement_ids = row.kitty_placement_ids or {}
    row.kitty_placement_ids[#row.kitty_placement_ids + 1] = record.id
  end
end

function State:release_kitty_placement_row(scope, row)
  if row == nil or row.kitty_placement_ids == nil then return end
  self.kitty_placements:release_line(scope, row.line_id)
  row.kitty_placement_ids = nil
end

function State:clear_visible_kitty_placements()
  local scope = self:selection_scope()
  for row = 0, self.rows - 1 do self:release_kitty_placement_row(scope, self:visible_row(row)) end
end

function State:clear_kitty_placement_scope(scope)
  self:detach_kitty_placement_records(self.kitty_placements:clear_scope(scope))
end

function State:kitty_placements_view()
  local rows = {}
  for row = 0, self.rows - 1 do rows[#rows + 1] = self:visible_row(row).line_id end
  return self.kitty_placements:view(self:selection_scope(), rows)
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

function State:hyperlink_at(row, column)
  row = selection_coordinate(row, self.rows - 1)
  column = selection_coordinate(column, self.columns - 1)
  local visible = self:visible_row(row)
  local start = selection_cluster_bounds(visible, column, self.columns)
  local id = visible.cells[start].hyperlink_id
  return id and self.hyperlinks[id] or nil
end

function State:hyperlink_at_cursor()
  if self.history_offset ~= 0 then return nil end
  local cursor = self.active_screen.cursor
  if not cursor.visible then return nil end
  return self:hyperlink_at(cursor.row, cursor.column)
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

function State:selection_text(maximum_bytes)
  assert(type(maximum_bytes) == "number" and maximum_bytes >= 0 and maximum_bytes % 1 == 0, "selection text limit must be a non-negative integer")
  local view = self:selection_view()
  if not view.active or not view.visible or view.empty then return nil, "no-selection" end
  local document = self:selection_rows(view.scope)
  local positions = {}
  for index, entry in ipairs(document) do positions[entry.line_id] = index end
  local first = positions[view.start.line_id]
  local last = positions[view.finish.line_id]
  if first == nil or last == nil then return nil, "no-selection" end
  local bytes = 0
  local text = {}
  local function append(value)
    bytes = bytes + #value
    if bytes > maximum_bytes then return false end
    text[#text + 1] = value
    return true
  end
  for index = first, last do
    local row = document[index].row
    local start = index == first and view.start.column or 0
    local finish = index == last and view.finish.column or self.columns
    for column = start, finish - 1 do
      local cell = row.cells[column]
      if cell and not cell.continuation and not append(cell.glyph) then return nil, "over-limit" end
    end
    if index < last and not row.wrapped and not append("\n") then return nil, "over-limit" end
  end
  return table.concat(text)
end

function State:invalidate_search()
  self.search_generation = self.search_generation + 1
end

function State:search_begin(direction)
  self.search:begin(self:selection_scope(), direction or "forward")
end

function State:search_append(text)
  return self.search:append(text)
end

function State:search_backspace()
  return self.search:backspace()
end

function State:clear_search()
  self.search:clear()
end

function State:reveal_search_match(match)
  if self.active_screen ~= self.primary then return false end
  local position
  for index, entry in ipairs(self:selection_rows("primary")) do
    if entry.line_id == match.line_id then
      position = index - 1
      break
    end
  end
  if position == nil then return false end
  local offset = clamp(self.scrollback:size() - position, 0, self.scrollback:size())
  if offset == self.history_offset then return false end
  self.history_offset = offset
  self:sync_cursor_visibility()
  self.damage:mark_all()
  self.text_damage:mark_all()
  return true
end

function State:search_submit(direction)
  local scope = self:selection_scope()
  local match, status = self.search:submit(self:selection_rows(scope), self.columns, self.search_generation, scope, direction or "forward")
  if match then self:reveal_search_match(match) end
  return match, status
end

function State:search_navigate(direction)
  local match, status = self.search:navigate(direction or "forward", self.search_generation, self:selection_scope())
  if match then self:reveal_search_match(match) end
  return match, status
end

function State:search_view()
  return self.search:view(self.search_generation, self:selection_scope())
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
  self:invalidate_search()
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
  self:invalidate_search()
end

function State:mark_rectangle(top, bottom, left, right)
  for row = top, bottom do
    local first = self:index(left, row)
    local count = right - left + 1
    self.damage:mark_range(first, count)
    self.text_damage:mark_range(first, count)
  end
  self:invalidate_search()
end

function State:horizontal_margins()
  if self.modes.left_right_margin then
    return self.active_screen.left_margin, self.active_screen.right_margin
  end
  return 0, self.columns - 1
end

function State:cursor_within_horizontal_margins(cursor)
  cursor = cursor or self.active_screen.cursor
  local left, right = self:horizontal_margins()
  return cursor.column >= left and cursor.column <= right
end

function State:horizontal_motion_bounds(cursor)
  cursor = cursor or self.active_screen.cursor
  local left, right = self:horizontal_margins()
  if cursor.column < left then left = 0 end
  if cursor.column > right then right = self.columns - 1 end
  return left, right
end

function State:write_right_boundary(cursor)
  cursor = cursor or self.active_screen.cursor
  local left, right = self:horizontal_margins()
  if cursor.column >= left and cursor.column <= right then return right end
  return self.columns - 1
end

function State:carriage_return_column(cursor)
  cursor = cursor or self.active_screen.cursor
  local left = self:horizontal_margins()
  if self.modes.origin or cursor.column >= left then return left end
  return 0
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
  self.active_screen.saved_cursor = {
    column = cursor.column,
    row = cursor.row,
    attributes = Attributes.copy(self.active_screen.attributes),
    hyperlink_id = self.active_screen.hyperlink_id,
    character_sets = copy_character_sets(self.character_sets),
  }
end

function State:restore_cursor()
  local saved = self.active_screen.saved_cursor
  self.active_screen.attributes = Attributes.copy(saved.attributes or Attributes.default())
  self.active_screen.hyperlink_id = saved.hyperlink_id
  if saved.character_sets then self.character_sets = copy_character_sets(saved.character_sets) end
  self:set_cursor(saved.column, saved.row)
end

function State:scroll_up(count)
  self:clear_grapheme_context()
  local screen = self.active_screen
  local top, bottom = screen.top_margin, screen.bottom_margin
  local left, right = self:horizontal_margins()
  count = clamp(count or 1, 1, bottom - top + 1)
  if left ~= 0 or right ~= self.columns - 1 then
    screen:scroll_rect_up(top, bottom, left, right, count, function()
      return self:cell_from_attributes(" ")
    end)
    for row = top, bottom do self:normalize_row(row) end
    self:mark_rectangle(top, bottom, left, right)
    self.stats.mutations = self.stats.mutations + (bottom - top + 1) * (right - left + 1)
    return
  end
  local preserve = screen == self.primary and top == 0 and bottom == self.rows - 1 and function(row)
    local evicted = self.scrollback:push(row)
    if evicted then
      self:release_command_regions(evicted)
      self:release_kitty_placement_row("primary", evicted)
    end
  end or nil
  local discard = preserve == nil and function(row)
    self:release_command_regions(row)
    self:release_kitty_placement_row(screen == self.primary and "primary" or "alternate", row)
  end or nil
  screen:scroll_up(top, bottom, count, preserve, discard)
  self:mark_region(top, bottom)
  self.stats.mutations = self.stats.mutations + (bottom - top + 1) * self.columns
  self:reconcile_selection()
end

function State:scroll_down(count)
  self:clear_grapheme_context()
  local screen = self.active_screen
  local top, bottom = screen.top_margin, screen.bottom_margin
  local left, right = self:horizontal_margins()
  count = clamp(count or 1, 1, bottom - top + 1)
  if left ~= 0 or right ~= self.columns - 1 then
    screen:scroll_rect_down(top, bottom, left, right, count, function()
      return self:cell_from_attributes(" ")
    end)
    for row = top, bottom do self:normalize_row(row) end
    self:mark_rectangle(top, bottom, left, right)
    self.stats.mutations = self.stats.mutations + (bottom - top + 1) * (right - left + 1)
    return
  end
  screen:scroll_down(top, bottom, count, function(row)
    self:release_command_regions(row)
    self:release_kitty_placement_row(screen == self.primary and "primary" or "alternate", row)
  end)
  self:mark_region(top, bottom)
  self.stats.mutations = self.stats.mutations + (bottom - top + 1) * self.columns
end

function State:index_line()
  local cursor = self.active_screen.cursor
  cursor.pending_wrap = false
  if cursor.row == self.active_screen.bottom_margin and self:cursor_within_horizontal_margins(cursor) then
    self:scroll_up(1)
  elseif cursor.row < self.rows - 1 then
    self:set_cursor(cursor.column, cursor.row + 1)
  end
end

function State:reverse_index()
  local cursor = self.active_screen.cursor
  cursor.pending_wrap = false
  if cursor.row == self.active_screen.top_margin and self:cursor_within_horizontal_margins(cursor) then
    self:scroll_down(1)
  elseif cursor.row > 0 then
    self:set_cursor(cursor.column, cursor.row - 1)
  end
end

function State:line_feed()
  if self.modes.newline then
    self:carriage_return()
  end
  self:index_line()
end

function State:carriage_return()
  local cursor = self.active_screen.cursor
  self:set_cursor(self:carriage_return_column(cursor), cursor.row)
end

function State:backspace()
  local cursor = self.active_screen.cursor
  local left, right = self:horizontal_margins()
  if cursor.column < left then left = 0 end
  local reverse_wrap = self.modes.autowrap and self.modes.reverse_wrap
  local count = reverse_wrap and cursor.pending_wrap and 0 or 1
  local column = cursor.column - count
  if column >= left then
    self:set_cursor(column, cursor.row)
    return
  end
  if not reverse_wrap then
    self:set_cursor(left, cursor.row)
    return
  end

  if cursor.column == left
    and self:cursor_within_horizontal_margins(cursor)
    and cursor.row >= self.active_screen.top_margin
    and cursor.row <= self.active_screen.bottom_margin
    and cursor.row == self.active_screen.top_margin then
    self:set_cursor(right, self.active_screen.bottom_margin)
    return
  end

  local width = right - left + 1
  local offset = width * cursor.row + column - left
  if offset < 0 then
    local length = width * self.rows
    offset = offset + (math.floor((-offset) / length) + 1) * length
  end
  self:set_cursor((offset % width) + left, math.floor(offset / width))
end

function State:tab()
  local cursor = self.active_screen.cursor
  local _, maximum = self:horizontal_margins()
  local target = maximum
  for column = cursor.column + 1, maximum do
    if self.tab_stops[column] then
      target = column
      break
    end
  end
  self:set_cursor(target, cursor.row)
end

function State:forward_tab(count)
  for _ = 1, count or 1 do self:tab() end
end

function State:back_tab(count)
  local cursor = self.active_screen.cursor
  local minimum = self.modes.origin and self:horizontal_margins() or 0
  for _ = 1, count or 1 do
    local target = minimum
    for column = cursor.column - 1, minimum, -1 do
      if self.tab_stops[column] then
        target = column
        break
      end
    end
    self:set_cursor(target, cursor.row)
  end
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
  local right = self:write_right_boundary(cursor)
  if width == 2 and right == 0 then
    self.stats.text.width_change_clamped = self.stats.text.width_change_clamped + 1
    width = 1
  elseif width == 2 and cursor.column == right then
    if self.modes.autowrap then
      screen.rows[cursor.row].wrapped = true
      self:carriage_return()
      self:index_line()
      cursor = screen.cursor
      right = self:write_right_boundary(cursor)
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
  self:attach_active_command_region(self.active_screen.rows[row])
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
  local right = self:write_right_boundary(cursor)
  if column + width - 1 == right then
    self:set_cursor(right, row, true)
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
    fg_slot = cell.fg_slot,
    bg_slot = cell.bg_slot,
    flags = cell.flags,
    codepoints = codepoints,
    width = old_width,
    display_text = (cell.display_text or cell.glyph) .. glyph,
    hyperlink_id = cell.hyperlink_id,
  }
  local column, row = context.column, context.row
  local cursor = self.active_screen.cursor
  if old_width == 1 and new_width == 2 then
    local right = self:write_right_boundary({ column = column })
    local next_cell = column + 1 <= right and self.active_screen:get(column + 1, row) or nil
    if next_cell and next_cell.glyph == " " and not next_cell.continuation then
      updated.width = 2
      self:set_cell(column, row, updated)
      self:set_cell(column + 1, row, self:continuation_cell(column))
      if cursor.row == row and cursor.column == column + 1 then
        self:set_cursor(math.min(right, column + 2), row, true)
        cursor.pending_wrap = column + 1 == right
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
  self:attach_active_command_region(self.active_screen.rows[row])
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
  if column == self:write_right_boundary(cursor) then
    cursor.pending_wrap = true
  else
    self:set_cursor(column + 1, row, true)
  end
end

function State:write_codepoint(glyph, codepoint)
  codepoint = codepoint or Utf8.decode_one(glyph)
  local character_set = self.character_sets[self.character_sets.gl]
  local translation
  if character_set == "dec_special_graphics" then
    translation = dec_special_graphics[glyph]
  elseif character_set == "uk" then
    translation = uk_character_set[glyph]
  end
  if translation then
    glyph = translation
    codepoint = Utf8.decode_one(glyph)
  end
  local counters = self.text_counters
  if counters then counters.unicode_scalars = (counters.unicode_scalars or 0) + 1 end
  local context = self.grapheme_context
  if codepoint >= 0x20 and codepoint <= 0x7e and (context == nil or context.last_gcb ~= GCB.prepend) then
    self:write_ascii_cluster(glyph, codepoint)
    self.last_print = { codepoint = codepoint, glyph = glyph }
    return
  end
  local cell, context = self:current_grapheme_cluster()
  if cell and not Grapheme.should_break(context.codepoints, codepoint) then
    if counters then counters.grapheme_boundary_checks = (counters.grapheme_boundary_checks or 0) + 1 end
    if #context.codepoints < self.max_cluster_codepoints then
      self:extend_grapheme_cluster(cell, context, glyph, codepoint)
      self.last_print = { codepoint = codepoint, glyph = glyph }
      return
    end
    self.stats.text.over_limit_clusters = self.stats.text.over_limit_clusters + 1
  end
  self:write_new_cluster(glyph, codepoint)
  self.last_print = { codepoint = codepoint, glyph = glyph }
end

function State:repeat_last_print(count)
  local previous = self.last_print
  if previous == nil then return false end
  count = math.min(count or 1, self.max_repeat)
  for _ = 1, count do self:write_codepoint(previous.glyph, previous.codepoint) end
  return true
end

function State:erase_cell(column, row, selective)
  if selective and bit.band(self:get(column, row).flags, Attributes.flags.protected) ~= 0 then
    return false
  end
  self:clear_grapheme_context()
  self:clear_cluster_at(column, row)
  return self:set_cell(column, row, self:cell_from_attributes(" "))
end

function State:erase_in_line(mode, selective)
  local cursor = self.active_screen.cursor
  local first, last = cursor.column, self.columns - 1
  if mode == 1 then
    first, last = 0, cursor.column
  elseif mode == 2 then
    first, last = 0, self.columns - 1
  end
  for column = first, last do
    self:erase_cell(column, cursor.row, selective)
  end
  cursor.pending_wrap = false
end

function State:erase_in_display(mode, selective)
  local cursor = self.active_screen.cursor
  if mode == 2 or mode == 3 then
    for row = 0, self.rows - 1 do
      for column = 0, self.columns - 1 do
        self:erase_cell(column, row, selective)
      end
    end
    if mode == 3 and self.active_screen == self.primary then
      self.scrollback:clear()
      self.history_offset = 0
      self:reconcile_command_regions()
      self:reconcile_selection()
    end
  elseif mode == 1 then
    for row = 0, cursor.row do
      local last = row == cursor.row and cursor.column or self.columns - 1
      for column = 0, last do
        self:erase_cell(column, row, selective)
      end
    end
  else
    for row = cursor.row, self.rows - 1 do
      local first = row == cursor.row and cursor.column or 0
      for column = first, self.columns - 1 do
        self:erase_cell(column, row, selective)
      end
    end
  end
  if not selective and (mode == 2 or mode == 3) then self:clear_visible_kitty_placements() end
  cursor.pending_wrap = false
end

function State:set_character_protection(action)
  if #action.parameters > 1 then
    self:record_unknown("csi", csi_detail(action))
    return
  end
  local mode = action.parameters[1] or 0
  if mode == 0 or mode == 2 then
    self.active_screen.attributes.protected = false
  elseif mode == 1 then
    self.active_screen.attributes.protected = true
  else
    self:record_unknown("csi", csi_detail(action))
  end
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
          fg_slot = anchor.fg_slot,
          bg_slot = anchor.bg_slot,
          flags = anchor.flags,
          width = 0,
          continuation = true,
          anchor_column = column - 1,
          hyperlink_id = anchor.hyperlink_id,
        })
      end
    elseif cell.width == 2 then
      if column == self.columns - 1 then
        self:set_cell(column, row_index, {
          glyph = cell.glyph,
          fg = cell.fg,
          bg = cell.bg,
          fg_slot = cell.fg_slot,
          bg_slot = cell.bg_slot,
          flags = cell.flags,
          codepoints = cell.codepoints,
          width = 1,
          display_text = cell.display_text,
          hyperlink_id = cell.hyperlink_id,
        })
      else
        local next_cell = row.cells[column + 1]
        if not next_cell.continuation or next_cell.anchor_column ~= column then
          self:set_cell(column + 1, row_index, {
            glyph = "",
            fg = cell.fg,
            bg = cell.bg,
            fg_slot = cell.fg_slot,
            bg_slot = cell.bg_slot,
            flags = cell.flags,
            width = 0,
            continuation = true,
            anchor_column = column,
            hyperlink_id = cell.hyperlink_id,
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
  local left, right = self:horizontal_margins()
  if cursor.column < left or cursor.column > right then
    cursor.pending_wrap = false
    return
  end
  local row = self.active_screen.rows[cursor.row]
  count = math.min(count or 1, right - cursor.column + 1)
  for column = right, cursor.column + count, -1 do
    copy_cell(row.cells[column], row.cells[column - count])
  end
  for column = cursor.column, cursor.column + count - 1 do
    copy_cell(row.cells[column], self:cell_from_attributes(" "))
  end
  self:normalize_row(cursor.row)
  local first = self:index(cursor.column, cursor.row)
  local count = right - cursor.column + 1
  self.damage:mark_range(first, count)
  self.text_damage:mark_range(first, count)
  cursor.pending_wrap = false
end

function State:delete_characters(count)
  self:clear_grapheme_context()
  local cursor = self.active_screen.cursor
  local left, right = self:horizontal_margins()
  if cursor.column < left or cursor.column > right then return end
  local row = self.active_screen.rows[cursor.row]
  count = math.min(count or 1, right - cursor.column + 1)
  for column = cursor.column, right - count do
    copy_cell(row.cells[column], row.cells[column + count])
  end
  for column = right - count + 1, right do
    copy_cell(row.cells[column], self:cell_from_attributes(" "))
  end
  self:normalize_row(cursor.row)
  local first = self:index(cursor.column, cursor.row)
  local count = right - cursor.column + 1
  self.damage:mark_range(first, count)
  self.text_damage:mark_range(first, count)
  cursor.pending_wrap = false
end

function State:insert_lines(count)
  self:clear_grapheme_context()
  local cursor = self.active_screen.cursor
  local left, right = self:horizontal_margins()
  if cursor.row < self.active_screen.top_margin or cursor.row > self.active_screen.bottom_margin
    or cursor.column < left or cursor.column > right then
    return
  end
  local bottom = self.active_screen.bottom_margin
  count = clamp(count or 1, 1, bottom - cursor.row + 1)
  if left == 0 and right == self.columns - 1 then
    self.active_screen:scroll_down(cursor.row, bottom, count, function(row)
      self:release_command_regions(row)
      self:release_kitty_placement_row(self:selection_scope(), row)
    end)
    self:mark_region(cursor.row, bottom)
  else
    self.active_screen:scroll_rect_down(cursor.row, bottom, left, right, count, function()
      return self:cell_from_attributes(" ")
    end)
    for row = cursor.row, bottom do self:normalize_row(row) end
    self:mark_rectangle(cursor.row, bottom, left, right)
  end
  self:set_cursor(left, cursor.row)
end

function State:delete_lines(count)
  self:clear_grapheme_context()
  local cursor = self.active_screen.cursor
  local left, right = self:horizontal_margins()
  if cursor.row < self.active_screen.top_margin or cursor.row > self.active_screen.bottom_margin
    or cursor.column < left or cursor.column > right then
    return
  end
  local bottom = self.active_screen.bottom_margin
  count = clamp(count or 1, 1, bottom - cursor.row + 1)
  if left == 0 and right == self.columns - 1 then
    self.active_screen:scroll_up(cursor.row, bottom, count, nil, function(row)
      self:release_command_regions(row)
      self:release_kitty_placement_row(self:selection_scope(), row)
    end)
    self:mark_region(cursor.row, bottom)
  else
    self.active_screen:scroll_rect_up(cursor.row, bottom, left, right, count, function()
      return self:cell_from_attributes(" ")
    end)
    for row = cursor.row, bottom do self:normalize_row(row) end
    self:mark_rectangle(cursor.row, bottom, left, right)
  end
  self:set_cursor(left, cursor.row)
end

function State:set_margins(top, bottom)
  if top == nil or top == 0 then top = 1 end
  if bottom == nil or bottom == 0 then bottom = self.rows end
  if top < 1 or bottom > self.rows or top >= bottom then
    return false
  end
  self.active_screen.top_margin = top - 1
  self.active_screen.bottom_margin = bottom - 1
  local left = self:horizontal_margins()
  self:set_cursor(self.modes.origin and left or 0, self.modes.origin and self.active_screen.top_margin or 0)
  return true
end

function State:reset_horizontal_margins(screen)
  screen = screen or self.active_screen
  screen.left_margin = 0
  screen.right_margin = self.columns - 1
end

function State:set_left_right_margins(left, right)
  if not self.modes.left_right_margin then return false end
  if left == nil or left == 0 then left = 1 end
  if right == nil or right == 0 then right = self.columns end
  if left < 1 or right > self.columns or left >= right then return false end
  local screen = self.active_screen
  screen.left_margin = left - 1
  screen.right_margin = right - 1
  self:clear_grapheme_context()
  self:set_cursor(self.modes.origin and screen.left_margin or 0, self.modes.origin and screen.top_margin or 0)
  return true
end

function State:move_cursor(row, column)
  row = row or 1
  column = column or 1
  if self.modes.origin then
    row = clamp(self.active_screen.top_margin + row - 1, self.active_screen.top_margin, self.active_screen.bottom_margin)
    column = clamp(self.active_screen.left_margin + column - 1, self.active_screen.left_margin, self.active_screen.right_margin)
    self:set_cursor(column, row)
    return
  end
  self:set_cursor(column - 1, row - 1)
end

function State:move_relative(row_delta, column_delta)
  local cursor = self.active_screen.cursor
  local minimum_row = self.modes.origin and self.active_screen.top_margin or 0
  local maximum_row = self.modes.origin and self.active_screen.bottom_margin or self.rows - 1
  local minimum_column, maximum_column = self:horizontal_motion_bounds(cursor)
  self:set_cursor(clamp(cursor.column + column_delta, minimum_column, maximum_column), clamp(cursor.row + row_delta, minimum_row, maximum_row))
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
        hyperlink_id = self.primary.hyperlink_id,
        character_sets = copy_character_sets(self.character_sets),
      }
    end
    self.active_screen = self.alternate
    self.cursor = self.active_screen.cursor
    self.history_offset = 0
    if save_cursor then
      self:clear_kitty_placement_scope("alternate")
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
  self.command_region_navigation = nil
  self:sync_cursor_visibility()
  self.damage:mark_all()
  self.text_damage:mark_all()
end

function State:pop_responses()
  local responses = self.responses
  self.responses = {}
  return responses
end

function State:emit_effect(kind, value)
  if self.effect_sink then self.effect_sink(kind, value) end
end

function State:respond(value)
  assert(type(value) == "string", "terminal response must be a byte string")
  if self.queue_responses then self.responses[#self.responses + 1] = value end
  self:emit_effect("write_pty", { bytes = value })
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
  self:emit_effect("unknown_sequence", { family = family, detail = detail })
end

function State:reset()
  self:clear_grapheme_context()
  self.kitty_placements:clear()
  self.kitty_graphics:clear()
  self.primary = self:new_screen()
  self.alternate = self:new_screen()
  self.primary.attributes = Attributes.default()
  self.alternate.attributes = Attributes.default()
  self.active_screen = self.primary
  self.cursor = self.primary.cursor
  self.character_sets = { g0 = "ascii", g1 = "ascii", gl = "g0" }
  self.modes.autowrap = true
  self.modes.origin = false
  self.modes.left_right_margin = false
  self.modes.insert = false
  self.modes.newline = false
  self.modes.cursor_visible = true
  self.modes.cursor_style = 1
  self.modes.cursor_blink = true
  self.modes.application_cursor = false
  self.modes.application_keypad = false
  self.modes.backarrow = false
  self.modes.reverse_wrap = false
  self.modes.bracketed_paste = false
  self.modes.synchronized_output = false
  self.modes.mouse_tracking = "none"
  self.modes.mouse_x10 = false
  self.modes.mouse_normal = false
  self.modes.mouse_button = false
  self.modes.mouse_any = false
  self.modes.mouse_utf8 = false
  self.modes.mouse_sgr = false
  self.modes.mouse_pixels = false
  self.modes.mouse_urxvt = false
  self.modes.mouse_protocol = "x10"
  self.modes.alternate_scroll = false
  self.modes.focus_reporting = false
  self.modes.mouse_generation = self.modes.mouse_generation + 1
  self.modes.keyboard_flags = 0
  self.modes.modify_other_keys = 0
  self.saved_private_modes = {}
  self:reset_tab_stops()
  self.scrollback:clear()
  self.shell:clear()
  self.command_regions:clear()
  self.command_region_navigation = nil
  self.hyperlinks = {}
  self.hyperlink_ids = {}
  self.next_hyperlink_id = 0
  self.title = nil
  self.icon_title = nil
  self.title_stacks = { icon = {}, window = {} }
  self.last_print = nil
  self:clear_selection()
  self:clear_search()
  self.history_offset = 0
  self:sync_cursor_visibility()
  self.damage:mark_all()
  self.text_damage:mark_all()
end

function State:soft_reset()
  self:clear_grapheme_context()
  self.active_screen.attributes = Attributes.default()
  self.active_screen.hyperlink_id = nil
  self.active_screen.keyboard_flags = 0
  self.active_screen.keyboard_stack = {}
  self.modes.application_cursor = false
  self.modes.application_keypad = false
  self.modes.backarrow = false
  self.modes.reverse_wrap = false
  self.modes.autowrap = true
  self.modes.origin = false
  self.modes.left_right_margin = false
  self.modes.insert = false
  self.modes.newline = false
  self.modes.cursor_visible = true
  self.modes.cursor_style = 1
  self.modes.cursor_blink = true
  self.modes.bracketed_paste = false
  self.modes.synchronized_output = false
  self.modes.mouse_tracking = "none"
  self.modes.mouse_x10 = false
  self.modes.mouse_normal = false
  self.modes.mouse_button = false
  self.modes.mouse_any = false
  self.modes.mouse_utf8 = false
  self.modes.mouse_sgr = false
  self.modes.mouse_pixels = false
  self.modes.mouse_urxvt = false
  self.modes.mouse_protocol = "x10"
  self.modes.alternate_scroll = false
  self.modes.focus_reporting = false
  self.modes.modify_other_keys = 0
  self.modes.mouse_generation = self.modes.mouse_generation + 1
  self.saved_private_modes = {}
  self.active_screen.top_margin = 0
  self.active_screen.bottom_margin = self.rows - 1
  self:reset_horizontal_margins(self.primary)
  self:reset_horizontal_margins(self.alternate)
  self:set_cursor(0, 0)
  self:sync_keyboard_flags()
  self:sync_cursor_visibility()
  self.last_print = nil
  self.damage:mark_all()
  self.text_damage:mark_all()
end

function State:screen_alignment_test()
  self:clear_grapheme_context()
  self.modes.origin = false
  self.active_screen.top_margin = 0
  self.active_screen.bottom_margin = self.rows - 1
  self:reset_horizontal_margins()
  for row = 0, self.rows - 1 do
    for column = 0, self.columns - 1 do
      self:set_cell(column, row, self:cell_from_attributes("E", { codepoints = ascii_codepoints[string.byte("E")], width = 1 }))
    end
    self.active_screen.rows[row].wrapped = false
  end
  self:set_cursor(0, 0)
  self.last_print = { codepoint = string.byte("E"), glyph = "E" }
end

function State:is_reflow_blank(cell)
  return cell.glyph == " "
    and not cell.continuation
    and (cell.width == nil or cell.width == 1)
    and cell.codepoints == nil
    and cell.display_text == nil
    and cell.hyperlink_id == nil
    and cell.flags == 0
    and cell.fg == self.default_cell.fg
    and cell.bg == self.default_cell.bg
    and cell.fg_slot == self.default_cell.fg_slot
    and cell.bg_slot == self.default_cell.bg_slot
end

function State:merge_reflow_row_metadata(target, source)
  if source.command_regions_truncated then target.command_regions_truncated = true end
  for _, id in ipairs(source.command_region_ids or {}) do
    local ids = target.command_region_ids
    if ids == nil then
      ids = {}
      target.command_region_ids = ids
    end
    local present = false
    for _, existing in ipairs(ids) do
      if existing == id then
        present = true
        break
      end
    end
    if not present then
      if #ids < self.command_regions.row_reference_limit then
        ids[#ids + 1] = id
      else
        target.command_regions_truncated = true
        self.command_regions:mark_row_reference_overflow(id)
      end
    end
  end
end

function State:can_keep_primary_rows_on_resize(columns, rows)
  if rows ~= self.rows then return false end
  local primary = self.primary
  if primary.cursor.pending_wrap or primary.cursor.column >= columns or primary.saved_cursor.column >= columns then return false end
  if self.selection.scope == "primary" or #self.command_regions.regions > 0 or #self.shell.events > 0 or #self.kitty_placements.placements > 0 then return false end
  local function fits(row)
    if row.wrapped then return false end
    if columns < self.columns then
      for column = columns, self.columns - 1 do
        if not self:is_reflow_blank(row.cells[column]) then return false end
      end
    end
    return true
  end
  for index = 1, self.scrollback:size() do
    if not fits(self.scrollback:get(index)) then return false end
  end
  for row = 0, self.rows - 1 do
    if not fits(primary.rows[row]) then return false end
  end
  return true
end

function State:resize_primary_without_reflow(columns, rows, blank)
  local previous_columns = self.columns
  self.primary = self.primary:resize(columns, rows, blank)
  if columns <= previous_columns then return end
  for index = 1, self.scrollback:size() do
    local row = self.scrollback:get(index)
    for column = previous_columns, columns - 1 do
      if row.cells[column] == nil then row.cells[column] = blank() end
    end
  end
end

function State:reflow_primary(columns, rows)
  local old_columns = self.columns
  local old_primary = self.primary
  local document = self:selection_rows("primary")
  local source_rows = {}
  local source_document = {}
  for _, entry in ipairs(document) do
    source_rows[entry.line_id] = entry.row
    source_document[#source_document + 1] = entry.row
  end

  local old_cursor = old_primary.cursor
  local cursor_position = {
    column = old_cursor.column + (old_cursor.pending_wrap and 1 or 0),
    line_id = old_primary.rows[old_cursor.row].line_id,
    scope = "primary",
  }
  local old_saved = old_primary.saved_cursor
  local saved_position = {
    column = old_saved.column,
    line_id = old_primary.rows[old_saved.row].line_id,
    scope = "primary",
  }
  local viewport_position
  if self.active_screen == old_primary and self.history_offset > 0 then
    local visible = self:visible_row(0)
    viewport_position = { column = 0, line_id = visible.line_id, scope = "primary" }
  end

  -- Kitty placements own fixed cell rectangles. Reflow changes both axes, so
  -- keeping their old anchors would draw corrupted geometry; keep the decoded
  -- image cache but release the primary-screen placement records.
  self:clear_kitty_placement_scope("primary")

  local blank = function()
    return self:blank_cell()
  end
  local primary = Screen.new(columns, rows, blank, function()
    self.next_line_id = self.next_line_id + 1
    return self.next_line_id
  end)
  primary.attributes = Attributes.copy(old_primary.attributes)
  primary.hyperlink_id = old_primary.hyperlink_id
  primary.keyboard_flags = old_primary.keyboard_flags
  for index, flags in ipairs(old_primary.keyboard_stack) do primary.keyboard_stack[index] = flags end

  local reflowed, map, membership = Reflow.transform(source_document, old_columns, columns, function()
    return primary:new_row()
  end, function(cell)
    return self:is_reflow_blank(cell)
  end)
  local rows_by_line_id = {}
  for _, row in ipairs(reflowed) do rows_by_line_id[row.line_id] = row end
  for _, entry in ipairs(document) do
    local target = rows_by_line_id[membership[entry.line_id]]
    if target then self:merge_reflow_row_metadata(target, source_rows[entry.line_id]) end
  end
  for _, row in ipairs(reflowed) do row._reflow_sources = nil end

  local remap = function(position)
    local remapped = Reflow.remap_position(map, position.line_id, position.column)
    if remapped then remapped.scope = position.scope end
    return remapped
  end
  self.selection:remap("primary", remap)
  self.command_regions:remap_positions("primary", remap)
  self.shell:remap_positions("primary", remap)
  local mapped_cursor = remap(cursor_position)
  local mapped_saved = remap(saved_position)
  local mapped_viewport = viewport_position and remap(viewport_position) or nil

  local scrollback = Scrollback.new(self.scrollback.limit)
  local first_visible = math.max(1, #reflowed - rows + 1)
  for index = 1, first_visible - 1 do scrollback:push(reflowed[index]) end
  local target_row = 0
  for index = first_visible, #reflowed do
    primary.rows[target_row] = reflowed[index]
    target_row = target_row + 1
  end

  local function screen_location(position)
    if position == nil then return nil end
    for row = 0, rows - 1 do
      if primary.rows[row].line_id == position.line_id then
        return { column = clamp(position.column, 0, columns - 1), row = row }
      end
    end
    return nil
  end
  local cursor = screen_location(mapped_cursor)
  primary.cursor.column = cursor and cursor.column or 0
  primary.cursor.row = cursor and cursor.row or 0
  primary.cursor.pending_wrap = cursor ~= nil and mapped_cursor.column >= columns
  primary.cursor.visible = old_cursor.visible
  local saved = screen_location(mapped_saved)
  primary.saved_cursor = {
    attributes = Attributes.copy(old_saved.attributes or Attributes.default()),
    column = saved and saved.column or 0,
    hyperlink_id = old_saved.hyperlink_id,
    row = saved and saved.row or 0,
  }
  if old_saved.character_sets then primary.saved_cursor.character_sets = copy_character_sets(old_saved.character_sets) end

  local history_offset = 0
  if mapped_viewport then
    local position = nil
    for index = 1, scrollback:size() do
      if scrollback:get(index).line_id == mapped_viewport.line_id then
        position = index
        break
      end
    end
    if position then history_offset = scrollback:size() - (position - 1) end
  end
  self.primary = primary
  self.scrollback = scrollback
  self.history_offset = history_offset
end

function State:resize(columns, rows, options)
  self:clear_grapheme_context()
  assert(columns > 0 and rows > 0, "terminal dimensions must be positive")
  options = options or {}
  assert(type(options) == "table", "terminal resize options must be a table")
  assert(options.reflow == nil or type(options.reflow) == "boolean", "terminal resize reflow option must be a boolean")
  local reflow_primary = columns ~= self.columns and self.reflow_on_resize and options.reflow ~= false
  if rows < self.rows then
    for row = rows, self.rows - 1 do
      if not reflow_primary then self:release_kitty_placement_row("primary", self.primary.rows[row]) end
      self:release_kitty_placement_row("alternate", self.alternate.rows[row])
    end
  end
  local was_primary = self.active_screen == self.primary
  local blank = function()
    return self:blank_cell()
  end
  if reflow_primary then
    if self:can_keep_primary_rows_on_resize(columns, rows) then
      self:resize_primary_without_reflow(columns, rows, blank)
    else
      self:reflow_primary(columns, rows)
    end
  else
    self.primary = self.primary:resize(columns, rows, blank)
  end
  self.alternate = self.alternate:resize(columns, rows, blank)
  self.columns = columns
  self.rows = rows
  self.primary.top_margin = 0
  self.primary.bottom_margin = rows - 1
  self.alternate.top_margin = 0
  self.alternate.bottom_margin = rows - 1
  self.primary.left_margin = 0
  self.primary.right_margin = columns - 1
  self.alternate.left_margin = 0
  self.alternate.right_margin = columns - 1
  self.active_screen = was_primary and self.primary or self.alternate
  self.cursor = self.active_screen.cursor
  self:sync_keyboard_flags()
  self:normalize_screen(self.primary)
  self:normalize_screen(self.alternate)
  self.damage = Damage.new(columns * rows)
  self.text_damage = Damage.new(columns * rows)
  self.history_offset = clamp(self.history_offset, 0, self.scrollback:size())
  self:reconcile_selection()
  self:reconcile_command_regions()
  self:detach_kitty_placement_records(self.kitty_placements:resize_scope("primary", columns))
  self:detach_kitty_placement_records(self.kitty_placements:resize_scope("alternate", columns))
  self:reset_tab_stops()
  self:sync_cursor_visibility()
  self.damage:mark_all()
  self.text_damage:mark_all()
  self:invalidate_search()
end

function State:mark_all_dirty()
  self.damage:mark_all()
  self.text_damage:mark_all()
end

function State:set_cell_metrics(width, height)
  assert(valid_cell_metric(width), "terminal cell width must be a positive integer no greater than 65535")
  assert(valid_cell_metric(height), "terminal cell height must be a positive integer no greater than 65535")
  self.cell_width = width
  self.cell_height = height
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

local function apply_colon_sgr(state, action)
  if action.private ~= "" or action.intermediates ~= "" or action.final ~= "m" then return false end
  local groups = action.parameter_groups
  if groups == nil then groups = { action.parameters } end
  local operations = {}
  for _, group in ipairs(groups) do
    local first = group[1]
    if #group == 1 and first ~= 38 and first ~= 48 then
      operations[#operations + 1] = { kind = "sgr", value = first }
    elseif first == 4 and #group == 2 and group[2] >= 0 and group[2] <= 5 then
      operations[#operations + 1] = { kind = "underline", value = group[2] ~= 0 }
    elseif (first == 38 or first == 48) and group[2] == 5 and #group == 3 and group[3] >= 0 and group[3] <= 255 then
      operations[#operations + 1] = { channel = first == 38 and "fg" or "bg", kind = "indexed", value = group[3] }
    elseif (first == 38 or first == 48) and group[2] == 2 then
      local offset = #group == 6 and group[3] == 0 and 4 or 3
      if #group ~= offset + 2 or group[offset] < 0 or group[offset] > 255 or group[offset + 1] < 0 or group[offset + 1] > 255 or group[offset + 2] < 0 or group[offset + 2] > 255 then
        return false
      end
      operations[#operations + 1] = {
        blue = group[offset + 2],
        channel = first == 38 and "fg" or "bg",
        green = group[offset + 1],
        kind = "rgb",
        red = group[offset],
      }
    else
      return false
    end
  end
  local attributes = state.active_screen.attributes
  for _, operation in ipairs(operations) do
    if operation.kind == "sgr" then
      attributes = Attributes.apply_sgr(attributes, { operation.value })
    elseif operation.kind == "underline" then
      -- Kiwi has one underline rendering mode. Retain the semantic underline
      -- without pretending to draw curl, dots, or dashes differently.
      attributes.underline = operation.value
    elseif operation.kind == "indexed" then
      attributes[operation.channel] = { kind = "indexed", index = operation.value }
    else
      attributes[operation.channel] = { kind = "rgb", red = operation.red, green = operation.green, blue = operation.blue }
    end
  end
  state.active_screen.attributes = attributes
  return true
end

local function sgr_status(attributes)
  local parameters = {}
  if attributes.bold then parameters[#parameters + 1] = 1 end
  if attributes.faint then parameters[#parameters + 1] = 2 end
  if attributes.italic then parameters[#parameters + 1] = 3 end
  if attributes.underline then parameters[#parameters + 1] = 4 end
  if attributes.inverse then parameters[#parameters + 1] = 7 end
  if attributes.concealed then parameters[#parameters + 1] = 8 end
  if attributes.strike then parameters[#parameters + 1] = 9 end
  local function append_colour(value, foreground)
    if value == nil then return end
    local base = foreground and 30 or 40
    local bright = foreground and 90 or 100
    if value.kind == "indexed" then
      if value.index < 8 then
        parameters[#parameters + 1] = base + value.index
      elseif value.index < 16 then
        parameters[#parameters + 1] = bright + value.index - 8
      else
        parameters[#parameters + 1] = foreground and 38 or 48
        parameters[#parameters + 1] = 5
        parameters[#parameters + 1] = value.index
      end
    elseif value.kind == "rgb" then
      parameters[#parameters + 1] = foreground and 38 or 48
      parameters[#parameters + 1] = 2
      parameters[#parameters + 1] = value.red
      parameters[#parameters + 1] = value.green
      parameters[#parameters + 1] = value.blue
    end
  end
  append_colour(attributes.fg, true)
  append_colour(attributes.bg, false)
  return #parameters == 0 and "0m" or table.concat(parameters, ";") .. "m"
end

function State:apply_execute(code)
  if code == 0 or code == 0x7f then
    return
  end
  if code == 0x07 then
    self.stats.bells = self.stats.bells + 1
    self:emit_effect("bell", {})
  elseif code == 0x08 then
    self:backspace()
  elseif code == 0x09 then
    self:tab()
  elseif code == 0x0a or code == 0x0b or code == 0x0c then
    self:line_feed()
  elseif code == 0x0d then
    self:carriage_return()
  elseif code == 0x0e then
    self:clear_grapheme_context()
    self.character_sets.gl = "g1"
  elseif code == 0x0f then
    self:clear_grapheme_context()
    self.character_sets.gl = "g0"
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
  elseif action.intermediates == "" and action.final == "=" then
    self.modes.application_keypad = true
  elseif action.intermediates == "" and action.final == ">" then
    self.modes.application_keypad = false
  elseif (action.intermediates == "(" or action.intermediates == ")") and (action.final == "0" or action.final == "A" or action.final == "B") then
    local bank = action.intermediates == "(" and "g0" or "g1"
    self.character_sets[bank] = ({ ["0"] = "dec_special_graphics", A = "uk", B = "ascii" })[action.final]
  elseif action.intermediates == "#" and action.final == "8" then
    self:screen_alignment_test()
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
      local left = self:horizontal_margins()
      self:set_cursor(enabled and left or 0, enabled and self.active_screen.top_margin or 0)
    elseif mode == 7 then
      self.modes.autowrap = enabled
      self.active_screen.cursor.pending_wrap = false
    elseif mode == 12 then
      self.modes.cursor_blink = enabled
    elseif mode == 45 then
      self.modes.reverse_wrap = enabled
    elseif mode == 67 then
      self.modes.backarrow = enabled
    elseif mode == 69 then
      self.modes.left_right_margin = enabled
      if not enabled then
        self:reset_horizontal_margins(self.primary)
        self:reset_horizontal_margins(self.alternate)
        self:clear_grapheme_context()
      end
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
    elseif mode == 9 then
      self:set_mouse_tracking("x10", enabled)
    elseif mode == 1002 then
      self:set_mouse_tracking("button", enabled)
    elseif mode == 1003 then
      self:set_mouse_tracking("any", enabled)
    elseif mode == 1004 then
      self:set_focus_reporting(enabled)
    elseif mode == 1007 then
      self.modes.alternate_scroll = enabled
    elseif mode == 1006 then
      self:set_mouse_encoding("sgr", enabled)
    elseif mode == 1005 then
      self:set_mouse_encoding("utf8", enabled)
    elseif mode == 1015 then
      self:set_mouse_encoding("urxvt", enabled)
    elseif mode == 1016 then
      self:set_mouse_encoding("pixels", enabled)
    else
      self:record_unknown("csi", { private = "?", parameters = { mode }, intermediates = "", final = enabled and "h" or "l" })
    end
  end
end

function State:restorable_private_mode_value(mode)
  local modes = self.modes
  if mode == 1 then return modes.application_cursor
  elseif mode == 6 then return modes.origin
  elseif mode == 7 then return modes.autowrap
  elseif mode == 12 then return modes.cursor_blink
  elseif mode == 25 then return modes.cursor_visible
  elseif mode == 45 then return modes.reverse_wrap
  elseif mode == 67 then return modes.backarrow
  elseif mode == 69 then return modes.left_right_margin
  elseif mode == 1004 then return modes.focus_reporting
  elseif mode == 1007 then return modes.alternate_scroll
  elseif mode == 2004 then return modes.bracketed_paste
  elseif mode == 2026 then return modes.synchronized_output
  end
end

function State:save_private_modes(parameters, action)
  for _, mode in ipairs(parameters) do
    local value = self:restorable_private_mode_value(mode)
    if value == nil then
      self:record_unknown("csi", csi_detail(action))
      return
    end
    self.saved_private_modes[mode] = value
  end
end

function State:restore_private_modes(parameters, action)
  for _, mode in ipairs(parameters) do
    if self:restorable_private_mode_value(mode) == nil then
      self:record_unknown("csi", csi_detail(action))
      return
    end
    local saved = self.saved_private_modes[mode]
    if saved ~= nil then self:apply_private_mode({ mode }, saved) end
  end
end

function State:set_mouse_tracking(mode, enabled)
  local field = "mouse_" .. mode
  if self.modes[field] == enabled then return end
  if enabled then
    self.modes.mouse_x10 = false
    self.modes.mouse_normal = false
    self.modes.mouse_button = false
    self.modes.mouse_any = false
  end
  self.modes[field] = enabled
  local next_mode = self.modes.mouse_any and "any"
    or self.modes.mouse_button and "button"
    or self.modes.mouse_normal and "normal"
    or self.modes.mouse_x10 and "x10"
    or "none"
  if self.modes.mouse_tracking ~= next_mode then
    self.modes.mouse_tracking = next_mode
  end
  self.modes.mouse_generation = self.modes.mouse_generation + 1
end

function State:set_mouse_encoding(encoding, enabled)
  local field = "mouse_" .. encoding
  if self.modes[field] == enabled then return end
  if enabled then
    self.modes.mouse_utf8 = false
    self.modes.mouse_sgr = false
    self.modes.mouse_pixels = false
    self.modes.mouse_urxvt = false
  end
  self.modes[field] = enabled
  self.modes.mouse_protocol = self.modes.mouse_pixels and "sgr-pixels"
    or self.modes.mouse_sgr and "sgr"
    or self.modes.mouse_urxvt and "urxvt"
    or self.modes.mouse_utf8 and "utf8"
    or "x10"
  self.modes.mouse_generation = self.modes.mouse_generation + 1
end

function State:set_focus_reporting(enabled)
  self.modes.focus_reporting = enabled
end

function State:input_modes()
  local modes = self.modes
  return {
    alternate_screen = self.active_screen == self.alternate,
    alternate_scroll = modes.alternate_scroll == true,
    application_cursor = modes.application_cursor == true,
    application_keypad = modes.application_keypad == true,
    backarrow = modes.backarrow == true,
    bracketed_paste = modes.bracketed_paste == true,
    focus_reporting = modes.focus_reporting == true,
    keyboard_flags = modes.keyboard_flags,
    modify_other_keys = modes.modify_other_keys,
    mouse_protocol = modes.mouse_protocol,
    mouse_tracking = modes.mouse_tracking,
  }
end

function State:sync_keyboard_flags()
  self.modes.keyboard_flags = self.active_screen.keyboard_flags
end

function State:set_keyboard_flags(flags)
  self.active_screen.keyboard_flags = flags
  self.modes.keyboard_flags = flags
end

function State:apply_keyboard_flags(flags, mode)
  if flags < 0 or flags > 31 or flags % 1 ~= 0 then
    self:record_unknown("csi", { private = "=", parameters = { flags, mode }, intermediates = "", final = "u" })
    return
  end
  flags = bit.band(flags, self.keyboard_supported_flags)
  local next_flags
  if mode == 1 then
    next_flags = flags
  elseif mode == 2 then
    next_flags = bit.bor(self.active_screen.keyboard_flags, flags)
  elseif mode == 3 then
    next_flags = bit.band(self.active_screen.keyboard_flags, bit.bnot(flags))
  elseif mode ~= 2 and mode ~= 3 then
    self:record_unknown("csi", { private = "=", parameters = { flags, mode }, intermediates = "", final = "u" })
    return
  end
  if bit.band(next_flags, 16) ~= 0 and bit.band(next_flags, 8) == 0 then next_flags = bit.band(next_flags, bit.bnot(16)) end
  self:set_keyboard_flags(next_flags)
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

function State:set_modify_other_keys(action)
  local parameters = action.parameters
  if #parameters ~= 2 or parameters[1] ~= 4 or parameters[2] < 0 or parameters[2] > 3 then
    self:record_unknown("csi", csi_detail(action))
    return
  end
  self.modes.modify_other_keys = parameters[2]
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
    elseif mode == 20 then
      self.modes.newline = enabled
    else
      self:record_unknown("csi", { private = "", parameters = { mode }, intermediates = "", final = enabled and "h" or "l" })
    end
  end
end

function State:mode_status(private, mode)
  local enabled
  if private == "" then
    if mode == 4 then
      enabled = self.modes.insert
    elseif mode == 20 then
      enabled = self.modes.newline
    else
      return 0
    end
  elseif private == "?" then
    local modes = self.modes
    if mode == 1 then
      enabled = modes.application_cursor
    elseif mode == 6 then
      enabled = modes.origin
    elseif mode == 7 then
      enabled = modes.autowrap
    elseif mode == 12 then
      enabled = modes.cursor_blink
    elseif mode == 45 then
      enabled = modes.reverse_wrap
    elseif mode == 67 then
      enabled = modes.backarrow
    elseif mode == 69 then
      enabled = modes.left_right_margin
    elseif mode == 25 then
      enabled = modes.cursor_visible
    elseif mode == 47 or mode == 1047 or mode == 1049 then
      enabled = self.active_screen == self.alternate
    elseif mode == 1000 then
      enabled = modes.mouse_normal
    elseif mode == 9 then
      enabled = modes.mouse_x10
    elseif mode == 1002 then
      enabled = modes.mouse_button
    elseif mode == 1003 then
      enabled = modes.mouse_any
    elseif mode == 1004 then
      enabled = modes.focus_reporting
    elseif mode == 1007 then
      enabled = modes.alternate_scroll
    elseif mode == 1006 then
      enabled = modes.mouse_sgr
    elseif mode == 1005 then
      enabled = modes.mouse_utf8
    elseif mode == 1015 then
      enabled = modes.mouse_urxvt
    elseif mode == 1016 then
      enabled = modes.mouse_pixels
    elseif mode == 2004 then
      enabled = modes.bracketed_paste
    elseif mode == 2026 then
      enabled = modes.synchronized_output
    else
      return 0
    end
  else
    return 0
  end
  return enabled and 1 or 2
end

function State:report_mode(private, parameters, action)
  if #parameters > 1 then
    self:record_unknown("csi", csi_detail(action))
    return
  end
  local mode = parameters[1] or 0
  local status = self:mode_status(private, mode)
  self:respond(string.format("\27[%s%d;%d$y", private, mode, status))
end

function State:set_title(kind, value)
  if kind == "icon" then
    self.icon_title = value
    return
  end
  if self.title == value then return end
  self.title = value
  self:emit_effect("title_changed", { title = value })
end

function State:push_title(kind)
  local stack = self.title_stacks[kind]
  if #stack == State.title_stack_limit then table.remove(stack, 1) end
  stack[#stack + 1] = { value = kind == "icon" and self.icon_title or self.title }
end

function State:pop_title(kind)
  local stack = self.title_stacks[kind]
  local saved = table.remove(stack)
  if saved ~= nil then self:set_title(kind, saved.value) end
end

function State:apply_title_stack_operation(parameters, action)
  if parameters[1] ~= 22 and parameters[1] ~= 23 then return false end
  if #parameters ~= 2 or parameters[2] < 0 or parameters[2] > 2 then
    self:record_unknown("csi", csi_detail(action))
    return true
  end
  local kinds = parameters[2] == 0 and { "icon", "window" }
    or parameters[2] == 1 and { "icon" }
    or { "window" }
  for _, kind in ipairs(kinds) do
    if parameters[1] == 22 then self:push_title(kind) else self:pop_title(kind) end
  end
  return true
end

function State:report_window_operation(parameters, action)
  if self:apply_title_stack_operation(parameters, action) then return end
  if #parameters ~= 1 then
    self:record_unknown("csi", csi_detail(action))
    return
  end
  local operation = parameters[1]
  if operation == 18 then
    self:respond(string.format("\27[8;%d;%dt", self.rows, self.columns))
  elseif operation == 14 and self.cell_width ~= nil then
    self:respond(string.format("\27[4;%d;%dt", self.rows * self.cell_height, self.columns * self.cell_width))
  elseif operation == 16 and self.cell_width ~= nil then
    self:respond(string.format("\27[6;%d;%dt", self.cell_height, self.cell_width))
  else
    self:record_unknown("csi", csi_detail(action))
  end
end

function State:report_device_attributes(action)
  if action.intermediates ~= "" then
    self:record_unknown("csi", csi_detail(action))
    return
  end
  if action.private == "" then
    if #action.parameters == 0 or (#action.parameters == 1 and action.parameters[1] == 0) then
      self:respond("\27[?1;0c")
    else
      self:record_unknown("csi", csi_detail(action))
    end
  elseif action.private == ">" then
    if #action.parameters == 0 or (#action.parameters == 1 and action.parameters[1] == 0) then
      -- Identify a minimal VT100-compatible device without claiming xterm,
      -- graphics, or any feature that Kiwi does not implement.
      self:respond("\27[>0;1;0c")
    else
      self:record_unknown("csi", csi_detail(action))
    end
  else
    self:record_unknown("csi", csi_detail(action))
  end
end

function State:report_device_status(action)
  local parameters = action.parameters
  if #parameters ~= 1 then
    self:record_unknown("csi", csi_detail(action))
    return
  end

  local request = parameters[1]
  if action.private == "" and request == 5 then
    self:respond("\27[0n")
    return
  end
  if request ~= 6 or (action.private ~= "" and action.private ~= "?") then
    self:record_unknown("csi", csi_detail(action))
    return
  end

  local row = self.cursor.row + 1
  local column = self.cursor.column + 1
  if self.modes.origin then
    row = row - self.active_screen.top_margin
    column = column - self.active_screen.left_margin
  end
  self:respond(string.format("\27[%s%d;%dR", action.private, row, column))
end

function State:apply_csi(action)
  if action.colon then
    if apply_colon_sgr(self, action) then return end
    self:record_unknown("csi", csi_detail(action))
    return
  end
  local parameters = action.parameters
  local final = action.final
  if action.intermediates == "$" and final == "p" and (action.private == "" or action.private == "?") then
    self:report_mode(action.private, parameters, action)
    return
  end
  if action.private == "?" and (final == "h" or final == "l") then
    self:apply_private_mode(parameters, final == "h")
    return
  end
  if action.private == ">" and action.intermediates == "" and final == "m" then
    self:set_modify_other_keys(action)
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
  if action.private == "" and action.intermediates == "\"" and final == "q" then
    self:set_character_protection(action)
    return
  end
  if action.private == "!" and action.intermediates == "" and final == "p" then
    if #parameters == 0 then
      self:soft_reset()
    else
      self:record_unknown("csi", csi_detail(action))
    end
    return
  end
  if final == "c" then
    self:report_device_attributes(action)
    return
  end
  if final == "n" and action.intermediates == "" and (action.private == "" or action.private == "?") then
    self:report_device_status(action)
    return
  end
  if action.private == "?" and action.intermediates == "" and (final == "J" or final == "K") then
    if final == "J" and parameters[1] == 3 then
      self:record_unknown("csi", csi_detail(action))
      return
    end
    if final == "J" then
      self:erase_in_display(parameters[1] or 0, true)
    else
      self:erase_in_line(parameters[1] or 0, true)
    end
    return
  end
  if action.private == "?" and action.intermediates == "" and (final == "s" or final == "r") then
    if final == "s" then
      self:save_private_modes(parameters, action)
    else
      self:restore_private_modes(parameters, action)
    end
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
    self:carriage_return()
  elseif final == "F" then
    self:move_relative(-parameter(parameters, 1, 1), 0)
    self:carriage_return()
  elseif final == "G" then
    if self.modes.origin then
      self:move_cursor(self.cursor.row - self.active_screen.top_margin + 1, parameter(parameters, 1, 1))
    else
      self:set_cursor(parameter(parameters, 1, 1) - 1, self.cursor.row)
    end
  elseif final == "`" then
    if self.modes.origin then
      self:move_cursor(self.cursor.row - self.active_screen.top_margin + 1, parameter(parameters, 1, 1))
    else
      self:set_cursor(parameter(parameters, 1, 1) - 1, self.cursor.row)
    end
  elseif final == "d" then
    local column = self.modes.origin and self.cursor.column - self.active_screen.left_margin + 1 or self.cursor.column + 1
    self:move_cursor(parameter(parameters, 1, 1), column)
  elseif final == "e" then
    self:move_relative(parameter(parameters, 1, 1), 0)
  elseif final == "a" then
    self:move_relative(0, parameter(parameters, 1, 1))
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
  elseif final == "I" then
    self:forward_tab(parameter(parameters, 1, 1))
  elseif final == "Z" then
    self:back_tab(parameter(parameters, 1, 1))
  elseif final == "b" then
    if not self:repeat_last_print(parameter(parameters, 1, 1)) then self:record_unknown("csi", csi_detail(action)) end
  elseif final == "r" then
    self:set_margins(parameters[1], parameters[2])
  elseif final == "m" then
    self.active_screen.attributes = Attributes.apply_sgr(self.active_screen.attributes, parameters)
  elseif final == "h" or final == "l" then
    self:apply_standard_mode(parameters, final == "h")
  elseif final == "g" then
    self:clear_tab_stops(parameters[1] or 0)
  elseif final == "s" then
    if self.modes.left_right_margin then
      if #parameters > 2 then
        self:record_unknown("csi", csi_detail(action))
      else
        self:set_left_right_margins(parameters[1], parameters[2])
      end
    else
      self:save_cursor()
    end
  elseif final == "u" then
    self:restore_cursor()
  elseif final == "t" then
    self:report_window_operation(parameters, action)
  else
    self:record_unknown("csi", csi_detail(action))
  end
end

function State:apply_dcs(action)
  local payload = action.payload
  local response
  if payload == "m" then
    response = sgr_status(self.active_screen.attributes)
  elseif payload == "r" then
    response = string.format("%d;%dr", self.active_screen.top_margin + 1, self.active_screen.bottom_margin + 1)
  elseif payload == "s" then
    response = string.format("%d;%ds", self.active_screen.left_margin + 1, self.active_screen.right_margin + 1)
  elseif payload == " q" then
    response = string.format("%d q", self.modes.cursor_style)
  elseif payload == "\"q" then
    response = string.format("%d\"q", self.active_screen.attributes.protected and 1 or 0)
  elseif payload == "t" then
    response = string.format("%dt", self.rows)
  end
  if response then
    self:respond("\27P1$r" .. response .. "\27\\")
  else
    self:respond("\27P0$r\27\\")
  end
end

local function decode_xtgettcap_name(value)
  if #value == 0 or #value % 2 ~= 0 or not value:match("^[%x]+$") then return nil end
  local bytes = {}
  for index = 1, #value, 2 do
    local byte = tonumber(value:sub(index, index + 1), 16)
    if byte < 0x20 or byte > 0x7e then return nil end
    bytes[#bytes + 1] = string.char(byte)
  end
  return table.concat(bytes)
end

local function hex_encode(value)
  return (value:gsub(".", function(character) return string.format("%02x", string.byte(character)) end))
end

function State:apply_xtgettcap(action)
  local names = {}
  for name in (action.payload .. ";"):gmatch("(.-);") do
    if #names >= 32 then
      self:respond("\27P0+r\27\\")
      return
    end
    names[#names + 1] = name
  end
  if #names == 0 then
    self:respond("\27P0+r\27\\")
    return
  end
  -- RGB reports the number of significant bits in each direct-colour channel,
  -- matching xterm and Ghostty's XTGETTCAP convention.
  local capabilities = { Co = "256", TN = "xterm-kiwi", RGB = "8" }
  local response = {}
  for _, encoded_name in ipairs(names) do
    local name = decode_xtgettcap_name(encoded_name)
    local value = name and capabilities[name]
    if value == nil then
      self:respond("\27P0+r\27\\")
      return
    end
    response[#response + 1] = encoded_name:lower() .. "=" .. hex_encode(value)
  end
  self:respond("\27P1+r" .. table.concat(response, ";") .. "\27\\")
end

local function parse_osc_colour(value)
  if type(value) ~= "string" then return nil end
  local red, green, blue = value:match("^#([%x][%x])([%x][%x])([%x][%x])$")
  if red then return Color.pack(tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16), 0xff) end
  local components = { value:match("^rgb:([%x]+)/([%x]+)/([%x]+)$") }
  if #components ~= 3 then return nil end
  local channels = {}
  for index, component in ipairs(components) do
    if #component < 1 or #component > 4 then return nil end
    local maximum = 16 ^ #component - 1
    channels[index] = math.floor(tonumber(component, 16) * 255 / maximum + 0.5)
  end
  return Color.pack(channels[1], channels[2], channels[3], 0xff)
end

local function encode_osc_colour(value)
  local colour = Color.unpack(value)
  return string.format("rgb:%04x/%04x/%04x", colour.red * 0x101, colour.green * 0x101, colour.blue * 0x101)
end

local function osc_fields(payload)
  local fields = {}
  for field in (payload .. ";"):gmatch("(.-);") do fields[#fields + 1] = field end
  return fields
end

function State:refresh_palette_slots(change)
  local function refresh(cell)
    local changed = false
    if change.index ~= nil then
      local slot = change.index + 1
      if cell.fg_slot == slot then
        cell.fg = self.colors:indexed(change.index)
        changed = true
      end
      if cell.bg_slot == slot then
        cell.bg = self.colors:indexed(change.index)
        changed = true
      end
    elseif change.channel == "foreground" and cell.fg_slot == 0 then
      cell.fg = self.colors.foreground
      changed = true
    elseif change.channel == "background" and cell.bg_slot == 0 then
      cell.bg = self.colors.background
      changed = true
    elseif change.all_indexed then
      if cell.fg_slot and cell.fg_slot > 0 then
        cell.fg = self.colors:indexed(cell.fg_slot - 1)
        changed = true
      end
      if cell.bg_slot and cell.bg_slot > 0 then
        cell.bg = self.colors:indexed(cell.bg_slot - 1)
        changed = true
      end
    end
    return changed
  end
  local function refresh_rows(rows, count)
    for row = 0, count - 1 do
      for column = 0, self.columns - 1 do refresh(rows[row].cells[column]) end
    end
  end
  refresh_rows(self.primary.rows, self.rows)
  refresh_rows(self.alternate.rows, self.rows)
  for index = 1, self.scrollback:size() do
    local row = self.scrollback:get(index)
    for column = 0, self.columns - 1 do refresh(row.cells[column]) end
  end
  if change.channel == "foreground" then self.default_cell.fg = self.colors.foreground end
  if change.channel == "background" then self.default_cell.bg = self.colors.background end
  if change.all_indexed or change.index ~= nil or change.channel ~= nil then
    self.damage:mark_all()
    self.text_damage:mark_all()
    self:invalidate_search()
  end
end

function State:configure_palette(configuration)
  assert(type(configuration) == "table", "terminal palette configuration must be a table")
  self.colors:set_default("foreground", assert(configuration.foreground, "terminal palette configuration needs a foreground colour"))
  self.colors:set_default("background", assert(configuration.background, "terminal palette configuration needs a background colour"))
  self.colors:reset_indexed()
  for index, colour in pairs(configuration.palette or {}) do self.colors:set_indexed(index, colour) end
  self:refresh_palette_slots({ all_indexed = true })
  self:refresh_palette_slots({ channel = "foreground" })
  self:refresh_palette_slots({ channel = "background" })
  self:emit_effect("palette_changed", { configuration = true })
end

function State:configure_osc52_write(enabled)
  assert(type(enabled) == "boolean", "terminal OSC 52 enablement must be a boolean")
  self.osc52_write = enabled
end

function State:apply_osc_palette(payload)
  local fields = osc_fields(payload)
  if #fields == 0 or #fields % 2 ~= 0 then return false end
  local changes = {}
  for index = 1, #fields, 2 do
    local palette_index = tonumber(fields[index])
    if palette_index == nil or palette_index < 0 or palette_index > 255 or palette_index % 1 ~= 0 then return false end
    local value = fields[index + 1]
    if value == "?" then
      self:respond(string.format("\27]4;%d;%s\27\\", palette_index, encode_osc_colour(self.colors:indexed(palette_index))))
    else
      local colour = parse_osc_colour(value)
      if colour == nil then return false end
      changes[#changes + 1] = { index = palette_index, colour = colour }
    end
  end
  for _, change in ipairs(changes) do
    self.colors:set_indexed(change.index, change.colour)
    self:refresh_palette_slots({ index = change.index })
  end
  if #changes > 0 then self:emit_effect("palette_changed", { count = #changes }) end
  return true
end

function State:apply_osc_default_colour(channel, command, payload)
  if payload == "?" then
    local value = channel == "foreground" and self.colors.foreground or self.colors.background
    self:respond(string.format("\27]%d;%s\27\\", command, encode_osc_colour(value)))
    return true
  end
  local colour = parse_osc_colour(payload)
  if colour == nil then return false end
  self.colors:set_default(channel, colour)
  self:refresh_palette_slots({ channel = channel })
  self:emit_effect("palette_changed", { default = channel })
  return true
end

function State:apply_osc_cursor_colour(command, payload)
  if command == 112 then
    if payload ~= "" then return false end
    self.cursor_color = self.cursor_default_color
    self.damage:mark(self:index(self.cursor.column, self.cursor.row))
    self:emit_effect("cursor_color_changed", { reset = true })
    return true
  end
  if payload == "?" then
    self:respond(string.format("\27]12;%s\27\\", encode_osc_colour(self.cursor_color)))
    return true
  end
  local colour = parse_osc_colour(payload)
  if colour == nil then return false end
  self.cursor_color = colour
  self.damage:mark(self:index(self.cursor.column, self.cursor.row))
  self:emit_effect("cursor_color_changed", { reset = false })
  return true
end

function State:apply_osc52(payload)
  local selection, encoded = payload:match("^([^;]*);(.*)$")
  if selection == nil or selection == "" or selection:find("[^cps]", 1) then return false end
  if #encoded > math.floor((self.osc52_maximum_bytes + 2) / 3) * 4 then
    self:emit_effect("clipboard_write_denied", { reason = "over-limit", selection = selection })
    return true
  end
  local decoded_ok, text = pcall(Base64.decode, encoded)
  if not decoded_ok or #text > self.osc52_maximum_bytes or text:find("\0", 1, true) then
    self:emit_effect("clipboard_write_denied", { reason = "invalid", selection = selection })
    return true
  end
  if not self.osc52_write then
    self:emit_effect("clipboard_write_denied", { reason = "disabled", selection = selection })
    return true
  end
  self:emit_effect("clipboard_write_requested", { selection = selection, text = text })
  return true
end

function State:apply_osc9(payload)
  if #payload > 1024 then return false end
  local state, progress = payload:match("^4;([0-4]);(%d%d?%d?)$")
  if state then
    progress = tonumber(progress)
    if progress > 100 then return false end
    self:emit_effect("progress_changed", { progress = progress, state = tonumber(state) })
    return true
  end
  state = payload:match("^4;([0-4])$")
  if state then
    state = tonumber(state)
    if state == 1 then return false end
    self:emit_effect("progress_changed", { progress = nil, state = state })
    return true
  end
  if payload:find("\0", 1, true) or payload:find("\r", 1, true) or payload:find("\n", 1, true) then return false end
  self:emit_effect("notification_requested", { body = payload })
  return true
end

function State:apply_osc(action)
  if action.command == 0 then
    self:set_title("icon", action.payload)
    self:set_title("window", action.payload)
  elseif action.command == 1 then
    self:set_title("icon", action.payload)
  elseif action.command == 2 then
    self:set_title("window", action.payload)
  elseif action.command == 7 then
    local event = self.shell:apply_cwd(action.payload, self:shell_position())
    if event then
      self.command_regions:apply(event)
      local directory = self.shell.current_directory
      self:emit_effect("pwd_changed", {
        host = directory.host,
        path = directory.path,
        uri = directory.uri,
      })
    end
  elseif action.command == 8 then
    local parsed = Hyperlink.parse_osc8(action.payload, self.hyperlink_uri_maximum_bytes)
    if parsed == nil then
      self.active_screen.hyperlink_id = nil
      self.stats.hyperlinks.rejected = self.stats.hyperlinks.rejected + 1
    elseif parsed.kind == "close" then
      self.active_screen.hyperlink_id = nil
      self.stats.hyperlinks.closed = self.stats.hyperlinks.closed + 1
    else
      local existing = parsed.id and self.hyperlink_ids[parsed.id] or nil
      if existing and existing.uri ~= parsed.uri then
        self.active_screen.hyperlink_id = nil
        self.stats.hyperlinks.rejected = self.stats.hyperlinks.rejected + 1
      elseif existing then
        self.active_screen.hyperlink_id = existing.id
        self.stats.hyperlinks.opened = self.stats.hyperlinks.opened + 1
      elseif #self.hyperlinks >= self.hyperlink_limit then
        self.active_screen.hyperlink_id = nil
        self.stats.hyperlinks.rejected = self.stats.hyperlinks.rejected + 1
      else
        self.next_hyperlink_id = self.next_hyperlink_id + 1
        local link = { id = self.next_hyperlink_id, uri = parsed.uri }
        self.hyperlinks[link.id] = link
        if parsed.id then self.hyperlink_ids[parsed.id] = link end
        self.active_screen.hyperlink_id = link.id
        self.stats.hyperlinks.opened = self.stats.hyperlinks.opened + 1
      end
    end
  elseif action.command == 4 then
    if not self:apply_osc_palette(action.payload) then self:record_unknown("osc", { command = action.command }) end
  elseif action.command == 10 then
    if not self:apply_osc_default_colour("foreground", 10, action.payload) then self:record_unknown("osc", { command = action.command }) end
  elseif action.command == 11 then
    if not self:apply_osc_default_colour("background", 11, action.payload) then self:record_unknown("osc", { command = action.command }) end
  elseif action.command == 12 or action.command == 112 then
    if not self:apply_osc_cursor_colour(action.command, action.payload) then self:record_unknown("osc", { command = action.command }) end
  elseif action.command == 52 then
    if not self:apply_osc52(action.payload) then self:record_unknown("osc", { command = action.command }) end
  elseif action.command == 9 then
    if not self:apply_osc9(action.payload) then self:record_unknown("osc", { command = action.command }) end
  elseif action.command == 104 then
    if action.payload == "" then
      self.colors:reset_indexed()
      self:refresh_palette_slots({ all_indexed = true })
      self:emit_effect("palette_changed", { reset = "indexed" })
    else
      local palette_index = tonumber(action.payload)
      if palette_index == nil or palette_index < 0 or palette_index > 255 or palette_index % 1 ~= 0 then
        self:record_unknown("osc", { command = action.command })
      else
        self.colors:reset_indexed(palette_index)
        self:refresh_palette_slots({ index = palette_index })
        self:emit_effect("palette_changed", { reset = palette_index })
      end
    end
  elseif action.command == 110 or action.command == 111 then
    if action.payload ~= "" then
      self:record_unknown("osc", { command = action.command })
    else
      local channel = action.command == 110 and "foreground" or "background"
      self.colors:reset_default(channel)
      self:refresh_palette_slots({ channel = channel })
      self:emit_effect("palette_changed", { reset = channel })
    end
  elseif action.command == 133 then
    local event = self.shell:apply_marker(action.payload, self:shell_position())
    if event then
      local region = self.command_regions:apply(event)
      if region then self:attach_command_region(self.active_screen.rows[self.active_screen.cursor.row], region.id) end
      self:emit_effect("shell_marker", {
        exit_status = event.exit_status,
        kind = event.kind,
        line_id = event.line_id,
        scope = event.scope,
      })
    end
  else
    self:record_unknown("osc", { command = action.command })
  end
end

local function kitty_graphics_response(image_id, placement_id, status)
  local placement = placement_id and ",p=" .. placement_id or ""
  return string.format("\27_Gi=%d%s;%s\27\\", image_id or 0, placement, status)
end

function State:apply_kitty_placement_action(controls)
  local command, reason = self.kitty_placements:parse(controls)
  local image_id = tonumber(controls.i) or 0
  if command == nil then
    if controls.a == "p" or controls.a == "d" then
      self:respond(kitty_graphics_response(image_id, tonumber(controls.p), "EINVAL:" .. reason))
    end
    return
  end

  if command.kind == "place" then
    local placement, previous = self.kitty_placements:place(command, {
      column = self.cursor.column,
      columns = self.columns,
      has_image = function(id) return self.kitty_graphics:has_image(id) end,
      row = self.cursor.row,
      rows = self.rows,
      scope = self:selection_scope(),
      screen = self.active_screen,
    })
    if placement == nil then
      local status = previous == "unknown-image" and "ENOENT:" or "EINVAL:"
      self:respond(kitty_graphics_response(command.image_id, command.placement_id, status .. previous))
      return
    end
    if previous then self:detach_kitty_placement_records({ previous }) end
    self:attach_kitty_placement(placement)
    self:respond(kitty_graphics_response(placement.image_id, placement.placement_id, "OK"))
    return
  end

  if command.mode == "a" then
    self:clear_visible_kitty_placements()
    return
  end
  self:detach_kitty_placement_records(self.kitty_placements:delete(command, self:selection_scope()))
  if command.mode == "I" then self.kitty_graphics:delete_image(command.image_id) end
end

function State:apply_apc(action)
  local result = self.kitty_graphics:apply(action.payload)
  if result.placement_action then self:apply_kitty_placement_action(result.controls) end
  if result.response then self:respond(result.response) end
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
  elseif action.kind == "apc" then
    self:apply_apc(action)
  elseif action.kind == "dcs" then
    self:apply_dcs(action)
  elseif action.kind == "xtgettcap" then
    self:apply_xtgettcap(action)
  elseif action.kind == "ignore" then
    self:record_unknown(action.family, action.reason)
  else
    error("unknown terminal action: " .. tostring(action.kind))
  end
end

return State
