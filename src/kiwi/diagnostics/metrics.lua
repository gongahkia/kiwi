local Metrics = {}
Metrics.__index = Metrics

function Metrics.new(context, font, model)
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
  }, Metrics)
end

function Metrics:record(frame_seconds, prepare_seconds, renderer)
  self.frame_number = self.frame_number + 1
  self.cpu_frame_ms = frame_seconds * 1000
  self.cpu_prepare_ms = prepare_seconds * 1000
  self.renderer = renderer.diagnostics
end

function Metrics:snapshot()
  local xscale, yscale = self.context.window:content_scale()
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
  }
end

function Metrics:report(now)
  if now - self.last_report < 1 then
    return
  end
  self.last_report = now
  local item = self:snapshot()
  io.stdout:write(string.format(
    "frame=%d cpu=%.3fms prepare=%.3fms cells=%d dirty=%d ranges=%d upload=%d cells/%d B draws=%d atlas=%d (%dx%d %.1f%%) drawable=%dx%d backend=%s adapter=%s vendor=%s gpu=%s\n",
    item.frame,
    item.cpu_frame_ms,
    item.cpu_prepare_ms,
    item.terminal_cells,
    item.dirty_cells,
    item.dirty_ranges,
    item.cells_uploaded,
    item.bytes_uploaded,
    item.draw_calls,
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
