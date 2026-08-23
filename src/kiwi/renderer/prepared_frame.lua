-- Renderer-neutral terminal data prepared for one presentation backend.
--
-- This module deliberately owns no GPU, window, or host handles. Backends may
-- upload its LuaJIT buffers directly, but must acknowledge a model update only
-- after their uploads succeed.
local ffi = require("ffi")
local CommandRegions = require("kiwi.renderer.command_regions")
local Color = require("kiwi.renderer.color")
local Hyperlink = require("kiwi.renderer.hyperlink")
local Packing = require("kiwi.renderer.packing")
local Search = require("kiwi.renderer.search")
local Selection = require("kiwi.renderer.selection")
local TextBackend = require("kiwi.text.backend")

local PreparedFrame = {}
PreparedFrame.__index = PreparedFrame

local cursor_styles = {
  [1] = { shape = "block", blink = true },
  [2] = { shape = "block", blink = false },
  [3] = { shape = "underline", blink = true },
  [4] = { shape = "underline", blink = false },
  [5] = { shape = "bar", blink = true },
  [6] = { shape = "bar", blink = false },
}

local cursor_shape_values = { block = 0, underline = 1, bar = 2 }

local function color_to_u32(color)
  return ffi.cast("uint32_t", color)
end

local function preedit_signature(model)
  local preedit = model.ime_preedit
  if type(preedit) ~= "table" or type(preedit.text) ~= "string" or #preedit.text == 0 then return "" end
  return table.concat({ preedit.text, preedit.column or -1, preedit.row or -1 }, "\0")
end

function PreparedFrame.select_glyph(atlas, glyph_text)
  local glyph = atlas:get(glyph_text)
  if glyph == nil and glyph_text ~= " " then
    return atlas:get("?"), "?"
  end
  return glyph, glyph_text
end

-- This is intentionally static so CPU-only benchmarks can use a lightweight
-- packer table instead of constructing a text backend.
function PreparedFrame.pack_cell(packer, model, index)
  local column, row = model:position(index)
  local cell = model.cells[index]
  local instance = packer.cells[index]
  local foreground, background = cell.fg, cell.bg
  if model.presentation_colors then foreground, background = model:presentation_colors(cell) end
  instance.x = column
  instance.y = row
  instance.fg = color_to_u32(foreground)
  instance.bg = color_to_u32(background)
  instance.flags = cell.flags
  if packer.font.glyph_cache then
    instance.u0 = 0
    instance.v0 = 0
    instance.u1 = 0
    instance.v1 = 0
    instance.glyph = 0
    return
  end
  local glyph, glyph_key = PreparedFrame.select_glyph(packer.font.atlas, cell.glyph)
  if glyph and cell.glyph ~= " " then
    instance.u0 = glyph.u0
    instance.v0 = glyph.v0
    instance.u1 = glyph.u1
    instance.v1 = glyph.v1
    instance.glyph = string.byte(glyph_key)
  else
    instance.u0 = 0
    instance.v0 = 0
    instance.u1 = 0
    instance.v1 = 0
    instance.glyph = 0
  end
end

function PreparedFrame.pack_shaped_glyph(packer, glyph, index)
  local instance = packer.glyphs[index]
  instance.x = glyph.x
  instance.y = glyph.y
  instance.width = glyph.width
  instance.height = glyph.height
  instance.u0 = glyph.u0
  instance.v0 = glyph.v0
  instance.u1 = glyph.u1
  instance.v1 = glyph.v1
  instance.fg = color_to_u32(glyph.fg)
  instance.flags = glyph.flags
  instance.glyph = glyph.glyph_id
  instance.cluster = glyph.cluster_column
end

function PreparedFrame.cursor_descriptor(model)
  local modes = model.modes or {}
  local style = modes.cursor_style or 1
  local details = cursor_styles[style] or cursor_styles[1]
  local packed_color = model.cursor_color or Color.pack(0x8c, 0xd9, 0xe0, 0xff)
  local color = Color.unpack(packed_color)
  return {
    column = model.cursor.column,
    row = model.cursor.row,
    visible = model.cursor.visible ~= false,
    style = style,
    shape = details.shape,
    blink = details.blink and modes.cursor_blink ~= false,
    color = color,
  }
end

function PreparedFrame.new(font, model, options)
  options = options or {}
  assert(type(font) == "table" and font.glyph_cache ~= nil, "prepared frame needs a font glyph cache")
  assert(type(model) == "table" and type(model.columns) == "number" and type(model.rows) == "number", "prepared frame needs a terminal model")
  Packing.assert_layout()
  local text_backend = TextBackend.create(font, { requested = options.text_backend })
  return setmetatable({
    atlas_generation = 0,
    capacity = model.columns * model.rows,
    cells = ffi.new("KiwiGlyphInstance[?]", model.columns * model.rows),
    command_region_color = CommandRegions.parse_color(options.command_region_color),
    command_region_visual_enabled = options.command_region_visual_enabled == true,
    font = font,
    frame = ffi.new("KiwiFrameUniform[1]"),
    frame_time = 0,
    force_full_upload = false,
    glyph_capacity = model.columns * model.rows * 8,
    glyph_count = 0,
    glyphs = ffi.new("KiwiTextGlyphInstance[?]", model.columns * model.rows * 8),
    hyperlink_color = Hyperlink.parse_color(options.hyperlink_color),
    layout = text_backend:layout(),
    pending_model = nil,
    preedit_signature = "",
    revision = 0,
    search_color = Search.parse_color(options.search_color),
    selection_color = Selection.parse_color(options.selection_color),
    text_backend = text_backend,
  }, PreparedFrame)
end

function PreparedFrame:selection_descriptor(model)
  return Selection.descriptor(model, self.selection_color)
end

function PreparedFrame:search_descriptor(model)
  return Search.descriptor(model, self.search_color)
end

function PreparedFrame:hyperlink_descriptor(model)
  return Hyperlink.descriptor(model, self.hyperlink_color)
end

function PreparedFrame:command_regions_descriptor(model)
  return CommandRegions.descriptor(model)
end

function PreparedFrame:descriptors(model)
  return {
    command_regions = self:command_regions_descriptor(model),
    cursor = PreparedFrame.cursor_descriptor(model),
    hyperlinks = self:hyperlink_descriptor(model),
    search = self:search_descriptor(model),
    selection = self:selection_descriptor(model),
  }
end

function PreparedFrame:prepare_model(model)
  if self.pending_model ~= nil then return self.pending_model end
  local damage = model.damage
  local preedit = preedit_signature(model)
  local preedit_changed = self.preedit_signature ~= preedit
  self.preedit_signature = preedit
  local shaped_glyphs = self.text_backend:update(model)
  local ranges = self.force_full_upload and {
    { first = 0, count = self.capacity },
  } or damage:ranges()
  local cell_updates = {}
  for _, range in ipairs(ranges) do
    for index = range.first, range.first + range.count - 1 do
      PreparedFrame.pack_cell(self, model, index)
    end
    cell_updates[#cell_updates + 1] = {
      byte_count = range.count * Packing.glyph_instance_size,
      cell_count = range.count,
      data = self.cells + range.first,
      first = range.first,
    }
  end
  local glyph_update
  if self.layout.stats.rows_reshaped > 0 or preedit_changed or self.force_full_upload then
    local glyph_count = math.min(#shaped_glyphs, self.glyph_capacity)
    for index = 1, glyph_count do PreparedFrame.pack_shaped_glyph(self, shaped_glyphs[index], index - 1) end
    glyph_update = {
      byte_count = glyph_count * Packing.text_glyph_instance_size,
      count = glyph_count,
      data = self.glyphs,
      dropped = #shaped_glyphs - glyph_count,
    }
  end
  local atlas = self.font.glyph_cache.atlas
  local atlas_update
  if self.force_full_upload or self.atlas_generation ~= self.font.glyph_cache.generation then
    atlas_update = {
      byte_count = self.font.glyph_cache.pixel_bytes,
      data = self.font.glyph_cache.pixels,
      generation = self.font.glyph_cache.generation,
      height = atlas.height,
      width = atlas.width,
    }
  end
  local plan = {
    atlas_update = atlas_update,
    cell_updates = cell_updates,
    descriptors = self:descriptors(model),
    diagnostics = {
      bytes_uploaded = 0,
      cells_uploaded = 0,
      dirty_cells = damage.dirty_count,
      dirty_ranges = #ranges,
      full_update = damage.full or self.force_full_upload,
      glyph_bytes_uploaded = 0,
      glyph_instances_dropped = glyph_update and glyph_update.dropped or 0,
      glyph_instances_uploaded = glyph_update and glyph_update.count or 0,
      glyphs_produced = self.layout.stats.glyphs_produced,
      rows_reshaped = self.layout.stats.rows_reshaped,
      runs_reshaped = self.layout.stats.runs_reshaped,
      shape_cache_hits = self.layout.stats.cache_hits,
      shape_cache_misses = self.layout.stats.cache_misses,
      shaping_cpu_ms = self.layout.stats.shaping_cpu_ms,
      shaping_rows_invalidated = self.layout.stats.rows_invalidated,
      visible_shaped_glyphs = self.layout.stats.visible_glyphs,
      visible_shaped_runs = self.layout.stats.visible_runs,
    },
    glyph_count = glyph_update and glyph_update.count or self.glyph_count,
    glyph_update = glyph_update,
    model = model,
    revision = self.revision + 1,
  }
  self.pending_model = plan
  return plan
end

function PreparedFrame:commit_model(plan)
  assert(plan == self.pending_model, "prepared frame commit does not match the pending model plan")
  if plan.atlas_update then self.atlas_generation = plan.atlas_update.generation end
  self.glyph_count = plan.glyph_count
  self.revision = plan.revision
  self.force_full_upload = false
  plan.model.damage:clear()
  self.pending_model = nil
end

function PreparedFrame:discard_model(plan)
  assert(plan == self.pending_model, "prepared frame discard does not match the pending model plan")
  -- Text shaping and atlas insertion are stateful. A retry after a backend
  -- rejection must therefore restore every backend resource, not rely on a
  -- second layout pass to report the same incremental work.
  self.force_full_upload = true
  self.pending_model = nil
end

function PreparedFrame:prepare_frame(model, time, debug_dirty, debug_boundaries, options)
  options = options or {}
  assert(type(time) == "number", "prepared frame time must be numeric")
  assert(options.surface_is_srgb == nil or type(options.surface_is_srgb) == "boolean", "prepared frame sRGB status must be a boolean")
  local delta = math.max(0, time - self.frame_time)
  local descriptors = self:descriptors(model)
  local cursor = descriptors.cursor
  local selection = descriptors.selection
  local search = descriptors.search
  local hyperlinks = descriptors.hyperlinks
  local command_regions = descriptors.command_regions
  self.frame_time = time
  self.frame[0].columns = model.columns
  self.frame[0].rows = model.rows
  self.frame[0].cursor_column = cursor.column
  self.frame[0].cursor_row = cursor.row
  self.frame[0].time = time
  self.frame[0].show_dirty = debug_dirty and 1 or 0
  self.frame[0].show_boundaries = debug_boundaries and 1 or 0
  self.frame[0].cursor_visible = cursor.visible and 1 or 0
  self.frame[0].cursor_shape = cursor_shape_values[cursor.shape]
  self.frame[0].cursor_blink = cursor.blink and 1 or 0
  self.frame[0].cursor_red = cursor.color.red / 255
  self.frame[0].cursor_green = cursor.color.green / 255
  self.frame[0].cursor_blue = cursor.color.blue / 255
  self.frame[0].cursor_alpha = cursor.color.alpha / 255
  self.frame[0].selection_start_column = selection.start_column
  self.frame[0].selection_start_row = selection.start_row
  self.frame[0].selection_finish_column = selection.finish_column
  self.frame[0].selection_finish_row = selection.finish_row
  self.frame[0].selection_red = selection.color.red
  self.frame[0].selection_green = selection.color.green
  self.frame[0].selection_blue = selection.color.blue
  self.frame[0].selection_alpha = selection.color.alpha
  self.frame[0].search_start_column = search.start_column
  self.frame[0].search_start_row = search.start_row
  self.frame[0].search_finish_column = search.finish_column
  self.frame[0].search_finish_row = search.finish_row
  self.frame[0].search_red = search.color.red
  self.frame[0].search_green = search.color.green
  self.frame[0].search_blue = search.color.blue
  self.frame[0].search_alpha = search.color.alpha
  self.frame[0].hyperlink_red = hyperlinks.color.red
  self.frame[0].hyperlink_green = hyperlinks.color.green
  self.frame[0].hyperlink_blue = hyperlinks.color.blue
  self.frame[0].hyperlink_alpha = hyperlinks.color.alpha
  local command_region_color = CommandRegions.color_descriptor(self.command_region_color)
  local command_region_count = self.command_region_visual_enabled and command_regions.boundary_count or 0
  self.frame[0].command_region_count = command_region_count
  self.frame[0].command_region_red = command_region_color.red
  self.frame[0].command_region_green = command_region_color.green
  self.frame[0].command_region_blue = command_region_color.blue
  self.frame[0].command_region_alpha = command_region_count > 0 and command_region_color.alpha or 0
  self.frame[0].command_region_padding[0] = options.surface_is_srgb and 1 or 0
  for index = 0, CommandRegions.visible_boundary_limit - 1 do
    local boundary = command_regions.boundaries["boundary_" .. (index + 1)]
    local offset = index * 4
    self.frame[0].command_region_boundaries[offset] = boundary and boundary.column or 0
    self.frame[0].command_region_boundaries[offset + 1] = boundary and boundary.row or 0
    self.frame[0].command_region_boundaries[offset + 2] = boundary and CommandRegions.role_value(boundary.role) or 0
    self.frame[0].command_region_boundaries[offset + 3] = 0
  end
  return {
    byte_count = ffi.sizeof("KiwiFrameUniform"),
    command_regions = command_regions,
    cursor = cursor,
    data = self.frame,
    delta = delta,
    hyperlinks = hyperlinks,
    search = search,
    selection = selection,
    time = time,
  }
end

function PreparedFrame:complete_snapshot(plan, frame)
  assert(plan == self.pending_model, "prepared frame snapshot does not match the pending model plan")
  assert(type(frame) == "table" and frame.data == self.frame,
    "prepared frame snapshot needs this producer's frame uniform")
  local atlas = self.font.glyph_cache.atlas
  return {
    atlas_bytes = self.font.glyph_cache.pixel_bytes,
    atlas_height = atlas.height,
    atlas_pixels = self.font.glyph_cache.pixels,
    atlas_width = atlas.width,
    cell_count = self.capacity,
    cells = self.cells,
    frame = frame.data,
    glyph_count = plan.glyph_count,
    glyphs = self.glyphs,
  }
end

function PreparedFrame:atlas_descriptor()
  local atlas = self.font.glyph_cache.atlas
  return {
    format = "r8unorm",
    generation = self.atlas_generation,
    height = atlas.height,
    width = atlas.width,
  }
end

function PreparedFrame:destroy()
  self.text_backend:destroy()
end

return PreparedFrame
