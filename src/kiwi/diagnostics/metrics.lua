local Metrics = {}
Metrics.__index = Metrics

function Metrics.new(context, font, model, runtime)
  return setmetatable({
    context = context,
    font = font,
    model = model,
    frame_number = 0,
    cpu_frame_ms = 0,
    cpu_prepare_ms = 0,
    last_report = -math.huge,
    runtime = runtime or {},
  }, Metrics)
end

function Metrics:set_runtime(runtime)
  self.runtime = runtime or {}
end

function Metrics:record(frame_seconds, prepare_seconds, renderer)
  self.frame_number = self.frame_number + 1
  self.cpu_frame_ms = frame_seconds * 1000
  self.cpu_prepare_ms = prepare_seconds * 1000
  self.renderer = renderer.diagnostics
end

function Metrics:snapshot()
  local xscale, yscale = self.context.window:content_scale()
  local pty = self.runtime.pty
  local parser = self.runtime.parser
  local clipboard = self.runtime.clipboard
  local child_status = pty and pty.exit_status
  local atlas = self.font.glyph_cache and self.font.glyph_cache.atlas or self.font.atlas
  local glyph_cache_stats = self.font.glyph_cache and self.font.glyph_cache.stats or {}
  local kitty_graphics = self.model.kitty_graphics and self.model.kitty_graphics:view() or { image_count = 0, stats = {} }
  local font_stats = self.font.stats or {}
  local renderer = self.renderer or {}
  local kitty_images = renderer.kitty_images or { instances = 0, over_instances = 0, textures = 0, under_instances = 0, uploads = 0 }
  local wide_clusters = 0
  local grapheme_clusters = 0
  if self.model.cell_at_index then
    for index = 0, self.model.columns * self.model.rows - 1 do
      local cell = self.model:cell_at_index(index)
      if cell.codepoints and not cell.continuation then grapheme_clusters = grapheme_clusters + 1 end
      if cell.width == 2 then wide_clusters = wide_clusters + 1 end
    end
  end
  return {
    frame = self.frame_number,
    cpu_frame_ms = self.cpu_frame_ms,
    cpu_prepare_ms = self.cpu_prepare_ms,
    terminal_cells = self.model.columns * self.model.rows,
    dirty_cells = renderer.dirty_cells or 0,
    dirty_ranges = renderer.dirty_ranges or 0,
    cells_uploaded = renderer.cells_uploaded or 0,
    bytes_uploaded = renderer.bytes_uploaded or 0,
    full_update = renderer.full_update or false,
    draw_calls = renderer.draw_calls or 0,
    pass_cpu = renderer.pass_cpu or { enabled = false, frame = 0, samples = {}, history = {} },
    gpu_timing = renderer.gpu_timing or { enabled = false, status = "unavailable", samples = {}, history = {} },
    pass_budgets = renderer.pass_budgets or { enabled = false, warnings = {}, passes = {} },
    inspector = renderer.inspector or { enabled = false, passes = {} },
    text_backend = renderer.text_backend or { abi_version = 1, active = "atlas", fallback = false },
    extensions = renderer.extensions or { enabled = true, diagnostics = {}, disabled = {} },
    gpu_recovery = self.runtime.recovery and self.runtime.recovery:snapshot() or { history = {}, limits = {}, policy = "unavailable" },
    glyph_count = atlas:glyph_count(),
    atlas_width = atlas.width,
    atlas_height = atlas.height,
    atlas_occupancy = atlas:occupancy(),
    unicode_version = require("kiwi.unicode.properties").version,
    primary_font = self.font.font_path or "legacy atlas",
    primary_face_id = self.font.primary and self.font.primary.id or nil,
    fallback_faces_loaded = self.font.faces and #self.font.faces - 1 or 0,
    wide_clusters = wide_clusters,
    grapheme_clusters = grapheme_clusters,
    over_limit_clusters = self.model.stats and self.model.stats.text and self.model.stats.text.over_limit_clusters or 0,
    shaping_rows_invalidated = renderer.shaping_rows_invalidated or 0,
    rows_reshaped = renderer.rows_reshaped or 0,
    runs_reshaped = renderer.runs_reshaped or 0,
    glyphs_produced = renderer.glyphs_produced or 0,
    visible_shaped_runs = renderer.visible_shaped_runs or 0,
    visible_shaped_glyphs = renderer.visible_shaped_glyphs or 0,
    shaping_cpu_ms = renderer.shaping_cpu_ms or 0,
    shape_cache_hits = renderer.shape_cache_hits or 0,
    shape_cache_misses = renderer.shape_cache_misses or 0,
    glyph_instances_uploaded = renderer.glyph_instances_uploaded or 0,
    glyph_bytes_uploaded = renderer.glyph_bytes_uploaded or 0,
    glyph_instances_dropped = renderer.glyph_instances_dropped or 0,
    atlas_hits = glyph_cache_stats.hits or 0,
    atlas_misses = glyph_cache_stats.misses or 0,
    atlas_failures = glyph_cache_stats.failures or 0,
    atlas_negative_hits = glyph_cache_stats.negative_hits or 0,
    color_glyphs_unsupported = glyph_cache_stats.color_unsupported or 0,
    atlas_pages = self.font.glyph_cache and 1 or 0,
    fallback_hits = font_stats.fallback_hits or 0,
    fallback_misses = font_stats.fallback_misses or 0,
    drawable_width = self.context.width,
    drawable_height = self.context.height,
    content_scale_x = xscale,
    content_scale_y = yscale,
    backend = self.context.adapter_info.backend_name,
    adapter = self.context.adapter_info.device,
    vendor = self.context.adapter_info.vendor,
    pty_bytes_read = pty and pty.bytes_read or 0,
    pty_bytes_written = pty and pty.bytes_written or 0,
    pty_last_read_bytes = pty and pty.last_read_bytes or 0,
    pty_last_read_calls = pty and pty.last_read_calls or 0,
    parser_bytes = parser and parser.stats.bytes or 0,
    parser_actions = parser and parser.stats.actions or 0,
    parser_errors = parser and parser.stats.errors or 0,
    parser_ignored = parser and parser.stats.ignored or 0,
    terminal_mutations = self.model.stats and self.model.stats.mutations or 0,
    scrollback_lines = self.model.scrollback and self.model.scrollback:size() or 0,
    active_screen = self.model.active_screen == self.model.primary and "primary" or "alternate",
    child_pid = pty and pty.pid or nil,
    child_state = child_status and (child_status.kind .. (child_status.code and (":" .. child_status.code) or child_status.signal and (":" .. child_status.signal) or "")) or "running",
    unknown_csi = self.model.stats and self.model.stats.unknown.csi or 0,
    unknown_esc = self.model.stats and self.model.stats.unknown.esc or 0,
    unknown_osc = self.model.stats and self.model.stats.unknown.osc or 0,
    unknown_samples = self.model.stats and self.model.stats.unknown_samples or {},
    kitty_graphics = {
      cpu_bytes = kitty_graphics.stats.cpu_bytes or 0,
      decoded = kitty_graphics.stats.decoded or 0,
      evicted = kitty_graphics.stats.evicted or 0,
      gpu_bytes = kitty_graphics.stats.gpu_bytes or 0,
      image_count = kitty_graphics.image_count or 0,
      last_error = kitty_graphics.stats.last_error,
      rejected = kitty_graphics.stats.rejected or 0,
    },
    kitty_images = {
      instances = kitty_images.instances or 0,
      over_instances = kitty_images.over_instances or 0,
      textures = kitty_images.textures or 0,
      under_instances = kitty_images.under_instances or 0,
      uploads = kitty_images.uploads or 0,
    },
    clipboard = clipboard and clipboard:snapshot() or { maximum_bytes = 0, counters = {} },
  }
end

local function unknown_sample_text(sample)
  local detail = sample.detail
  if sample.family == "csi" and type(detail) == "table" then
    return string.format(
      "csi#%d private=%q parameters=%s intermediates=%q final=%q",
      sample.count,
      detail.private or "",
      table.concat(detail.parameters or {}, ";"),
      detail.intermediates or "",
      detail.final or ""
    )
  end
  if sample.family == "osc" and type(detail) == "table" then
    return string.format("osc#%d command=%s", sample.count, tostring(detail.command))
  end
  return string.format("%s#%d detail=%q", sample.family, sample.count, tostring(detail))
end

function Metrics:report(now)
  if now - self.last_report < 1 then
    return
  end
  self.last_report = now
  local item = self:snapshot()
  local gpu_status = type(item.gpu_timing) == "table" and item.gpu_timing.status or item.gpu_timing
  local budget_warnings = #(item.pass_budgets and item.pass_budgets.warnings or {})
  local text_backend = item.text_backend or {}
  local text_backend_status = text_backend.active or "atlas"
  if text_backend.fallback then text_backend_status = text_backend_status .. ":fallback(" .. (text_backend.fallback_reason or "unknown") .. ")" end
  io.stdout:write(string.format(
    "frame=%d cpu=%.3fms prepare=%.3fms grid=%dx%d screen=%s scrollback=%d mutations=%d dirty=%d ranges=%d upload=%d cells/%d B draws=%d pty=%d/%d B last-read=%d B/%d calls child=%s parser=%d B/%d actions/%d errors/%d ignored unknown=%d/%d/%d atlas=%d (%dx%d %.1f%%) drawable=%dx%d backend=%s adapter=%s vendor=%s gpu=%s budget-warnings=%d\n",
    item.frame,
    item.cpu_frame_ms,
    item.cpu_prepare_ms,
    self.model.columns,
    self.model.rows,
    item.active_screen,
    item.scrollback_lines,
    item.terminal_mutations,
    item.dirty_cells,
    item.dirty_ranges,
    item.cells_uploaded,
    item.bytes_uploaded,
    item.draw_calls,
    item.pty_bytes_read,
    item.pty_bytes_written,
    item.pty_last_read_bytes,
    item.pty_last_read_calls,
    item.child_pid and (tostring(item.child_pid) .. ":" .. item.child_state) or item.child_state,
    item.parser_bytes,
    item.parser_actions,
    item.parser_errors,
    item.parser_ignored,
    item.unknown_csi,
    item.unknown_esc,
    item.unknown_osc,
    item.glyph_count,
    item.atlas_width,
    item.atlas_height,
    item.atlas_occupancy * 100,
    item.drawable_width,
    item.drawable_height,
    item.backend,
    item.adapter,
    item.vendor,
    gpu_status,
    budget_warnings
  ))
  if #item.unknown_samples > 0 then
    local samples = {}
    for index, sample in ipairs(item.unknown_samples) do
      samples[index] = unknown_sample_text(sample)
    end
    io.stdout:write("unknown-samples: ", table.concat(samples, " | "), "\n")
  end
  if item.kitty_graphics.rejected > 0 or item.kitty_graphics.image_count > 0 then
    io.stdout:write(string.format(
      "kitty-graphics=images:%d cpu:%dB gpu:%dB decoded:%d evicted:%d rejected:%d last:%s\n",
      item.kitty_graphics.image_count,
      item.kitty_graphics.cpu_bytes,
      item.kitty_graphics.gpu_bytes,
      item.kitty_graphics.decoded,
      item.kitty_graphics.evicted,
      item.kitty_graphics.rejected,
      item.kitty_graphics.last_error or "none"
    ))
  end
  if item.kitty_images.instances > 0 or item.kitty_images.textures > 0 then
    io.stdout:write(string.format(
      "kitty-images=instances:%d under:%d over:%d textures:%d uploads:%d\n",
      item.kitty_images.instances,
      item.kitty_images.under_instances,
      item.kitty_images.over_instances,
      item.kitty_images.textures,
      item.kitty_images.uploads
    ))
  end
  if item.inspector.enabled then
    io.stdout:write(require("kiwi.renderer.inspector").format(item.inspector), "\n")
  end
  io.stdout:write(string.format(
    "text=backend=%s unicode-%s primary=%s#%s clusters=%d wide=%d visible=%d runs/%d glyphs fallbacks=%d shape=%.3fms %d rows/%d runs glyphs=%d cache=%d/%d glyph-upload=%d/%d B dropped=%d atlas=%d pages/%d/%d/%d negative=%d color-unsupported=%d fallback=%d/%d over-limit=%d\n",
    text_backend_status,
    item.unicode_version,
    item.primary_font,
    item.primary_face_id or "none",
    item.grapheme_clusters,
    item.wide_clusters,
    item.visible_shaped_runs,
    item.visible_shaped_glyphs,
    item.fallback_faces_loaded,
    item.shaping_cpu_ms,
    item.shaping_rows_invalidated,
    item.rows_reshaped,
    item.runs_reshaped,
    item.glyphs_produced,
    item.shape_cache_hits,
    item.shape_cache_misses,
    item.glyph_instances_uploaded,
    item.glyph_bytes_uploaded,
    item.glyph_instances_dropped,
    item.atlas_hits,
    item.atlas_misses,
    item.atlas_failures,
    item.atlas_pages,
    item.atlas_negative_hits,
    item.color_glyphs_unsupported,
    item.fallback_hits,
    item.fallback_misses,
    item.over_limit_clusters
  ))
end

return Metrics
