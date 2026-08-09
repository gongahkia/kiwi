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
    gpu_timing = context.timestamp_query_supported
      and "unsupported (adapter exposes timestamps; M0 defers query readback to preserve the baseline)"
      or "unsupported (adapter does not expose timestamp-query feature)",
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
  local child_status = pty and pty.exit_status
  return {
    frame = self.frame_number,
    cpu_frame_ms = self.cpu_frame_ms,
    cpu_prepare_ms = self.cpu_prepare_ms,
    terminal_cells = self.model.columns * self.model.rows,
    dirty_cells = self.renderer.dirty_cells,
    dirty_ranges = self.renderer.dirty_ranges,
    cells_uploaded = self.renderer.cells_uploaded,
    bytes_uploaded = self.renderer.bytes_uploaded,
    full_update = self.renderer.full_update,
    draw_calls = self.renderer.draw_calls,
    glyph_count = self.font.atlas:glyph_count(),
    atlas_width = self.font.atlas.width,
    atlas_height = self.font.atlas.height,
    atlas_occupancy = self.font.atlas:occupancy(),
    drawable_width = self.context.width,
    drawable_height = self.context.height,
    content_scale_x = xscale,
    content_scale_y = yscale,
    backend = self.context.adapter_info.backend_name,
    adapter = self.context.adapter_info.device,
    vendor = self.context.adapter_info.vendor,
    gpu_timing = self.gpu_timing,
    pty_bytes_read = pty and pty.bytes_read or 0,
    pty_bytes_written = pty and pty.bytes_written or 0,
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
  }
end

function Metrics:report(now)
  if now - self.last_report < 1 then
    return
  end
  self.last_report = now
  local item = self:snapshot()
  io.stdout:write(string.format(
    "frame=%d cpu=%.3fms prepare=%.3fms grid=%dx%d screen=%s scrollback=%d mutations=%d dirty=%d ranges=%d upload=%d cells/%d B draws=%d pty=%d/%d B child=%s parser=%d B/%d actions/%d errors/%d ignored unknown=%d/%d/%d atlas=%d (%dx%d %.1f%%) drawable=%dx%d backend=%s adapter=%s vendor=%s gpu=%s\n",
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
    item.gpu_timing
  ))
end

return Metrics
